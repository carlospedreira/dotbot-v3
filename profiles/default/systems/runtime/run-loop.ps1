<#
.SYNOPSIS
Main orchestration loop for autonomous task implementation using Go Mode

.DESCRIPTION
Manages the outer loop of autonomous task execution:
- Initializes session state
- Fetches next task from queue
- Builds prompt from template
- Invokes Claude with Go Mode
- Detects completion and handles errors
- Auto-continues to next task with delay

.PARAMETER MaxTasks
Maximum number of tasks to process before stopping (default: unlimited)

.PARAMETER AutoContinueDelay
Seconds to wait between tasks (default: 3)

.PARAMETER MaxRetriesPerTask
Maximum retry attempts per task (default: 2)

.PARAMETER ConsecutiveFailureThreshold
Number of consecutive failures before pausing (default: 3)

.PARAMETER Model
Claude model to use (Opus, Sonnet, or Haiku; default: Opus)

.PARAMETER ShowDebug
Show raw JSON events in dark gray

.PARAMETER ShowVerbose
Show detailed tool results and metadata

.EXAMPLE
.\run-autonomous-loop.ps1

.EXAMPLE
.\run-autonomous-loop.ps1 -MaxTasks 10 -AutoContinueDelay 5 -Model Sonnet

.EXAMPLE
.\run-autonomous-loop.ps1 -ShowDebug -ShowVerbose
#>

param(
    [Parameter(Mandatory = $false)]
    [int]$MaxTasks = 0,  # 0 = unlimited
    
    [Parameter(Mandatory = $false)]
    [int]$AutoContinueDelay = 3,
    
    [Parameter(Mandatory = $false)]
    [int]$MaxRetriesPerTask = 2,
    
    [Parameter(Mandatory = $false)]
    [int]$ConsecutiveFailureThreshold = 3,
    
    [Parameter(Mandatory = $false)]
    [ValidateSet('Opus', 'Sonnet', 'Haiku')]
    [string]$Model = 'Opus',
    
    [Parameter(Mandatory = $false)]
    [switch]$ShowDebug,
    
    [Parameter(Mandatory = $false)]
    [switch]$ShowVerbose
)

# Map model parameter to Claude model name
$modelMap = @{
    'Opus'   = 'claude-opus-4-5-20251101'
    'Sonnet' = 'claude-sonnet-4-5-20250929'
    'Haiku'  = 'claude-haiku-4-5-20251001'
}

$claudeModelName = $modelMap[$Model]
$env:CLAUDE_MODEL = $claudeModelName

# Set phase for activity logging - all activity in this loop is 'execution' phase
$env:DOTBOT_CURRENT_PHASE = 'execution'

# Control directory for signal files (.bot/.control - run-loop is at .bot/systems/runtime)
$controlDir = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) ".control"

# Load settings for execution model
$settingsPath = Join-Path $PSScriptRoot "..\..\defaults\settings.default.json"
$settings = @{ execution = @{ model = 'Opus' } }
if (Test-Path $settingsPath) {
    try {
        $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
    } catch {
        Write-Warning "Failed to load settings: $_"
    }
}

# Determine model (parameter overrides settings)
if (-not $PSBoundParameters.ContainsKey('Model')) {
    $Model = if ($settings.execution -and $settings.execution.model) { $settings.execution.model } else { 'Opus' }
}

# Import ClaudeCLI module
Import-Module "$PSScriptRoot\ClaudeCLI\ClaudeCLI.psm1" -Force

# Import DotBotTheme for consistent UI
Import-Module "$PSScriptRoot\modules\DotBotTheme.psm1" -Force
$t = Get-DotBotTheme

# Import module functions
. "$PSScriptRoot\modules\ui-rendering.ps1"
. "$PSScriptRoot\modules\control-signals.ps1"

# Import TaskIndexCache (no caching - always reads fresh)
Import-Module "$PSScriptRoot\..\mcp\modules\TaskIndexCache.psm1" -Force
Import-Module "$PSScriptRoot\..\mcp\modules\SessionTracking.psm1" -Force
. "$PSScriptRoot\modules\cleanup.ps1"
. "$PSScriptRoot\modules\task-reset.ps1"
. "$PSScriptRoot\modules\prompt-builder.ps1"
. "$PSScriptRoot\modules\get-failure-reason.ps1"
. "$PSScriptRoot\modules\test-task-completion.ps1"
. "$PSScriptRoot\modules\create-problem-log.ps1"
. "$PSScriptRoot\modules\rate-limit-handler.ps1"

# Import MCP tool functions (for direct PowerShell calls)
. "$PSScriptRoot\..\mcp\tools\session-initialize\script.ps1"
. "$PSScriptRoot\..\mcp\tools\session-get-state\script.ps1"
. "$PSScriptRoot\..\mcp\tools\session-get-stats\script.ps1"
. "$PSScriptRoot\..\mcp\tools\session-update\script.ps1"
. "$PSScriptRoot\..\mcp\tools\session-increment-completed\script.ps1"
. "$PSScriptRoot\..\mcp\tools\task-get-next\script.ps1"
. "$PSScriptRoot\..\mcp\tools\task-mark-in-progress\script.ps1"
. "$PSScriptRoot\..\mcp\tools\task-mark-skipped\script.ps1"

# Banner and configuration display
Write-Card -Title "GO MODE AUTONOMOUS LOOP" -Width 45 -BorderStyle Rounded -BorderColor Label -TitleColor Label -Lines @(
    "$($t.Amber)Autonomous task execution$($t.Reset)"
)

$maxTasksValue = if ($MaxTasks -eq 0) { 'unlimited' } else { $MaxTasks }
$configLines = @(
    "$($t.Label)Max tasks:$($t.Reset)         $($t.Cyan)$maxTasksValue$($t.Reset)"
    "$($t.Label)Auto-continue:$($t.Reset)     $($t.Cyan)${AutoContinueDelay}s$($t.Reset)"
    "$($t.Label)Max retries:$($t.Reset)       $($t.Cyan)$MaxRetriesPerTask$($t.Reset)"
    "$($t.Label)Failure threshold:$($t.Reset) $($t.Cyan)$ConsecutiveFailureThreshold$($t.Reset)"
    "$($t.Label)Model:$($t.Reset)             $($t.Purple)$Model$($t.Reset)"
)
if ($ShowDebug) { $configLines += "$($t.Label)Debug:$($t.Reset)             $($t.Green)enabled$($t.Reset)" }
if ($ShowVerbose) { $configLines += "$($t.Label)Verbose:$($t.Reset)           $($t.Green)enabled$($t.Reset)" }

Write-Card -Title "CONFIGURATION" -Width 45 -BorderStyle Rounded -BorderColor Label -TitleColor Label -Lines $configLines

# Cleanup temporary Claude directories
Write-Header "Startup"
Write-Status "Cleaning up temporary directories..." -Type Process

# Find git root by walking up from current directory
$projectRoot = $PWD.Path
while ($projectRoot -and -not (Test-Path (Join-Path $projectRoot ".git"))) {
    $parent = Split-Path -Parent $projectRoot
    if ($parent -eq $projectRoot) {
        # Reached filesystem root without finding .git - use parent of .bot folder
        $projectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        break
    }
    $projectRoot = $parent
}

$cleanupCount = Clear-TemporaryClaudeDirectories -ProjectRoot $projectRoot
if ($cleanupCount -gt 0) {
    Write-Status "Removed $cleanupCount temp directories" -Type Success
} else {
    Write-Status "No temp directories found" -Type Complete
}

# Clean up old Claude sessions at startup
$oldSessionsRemoved = Clear-OldClaudeSessions -ProjectRoot $projectRoot -MaxAgeDays 7
if ($oldSessionsRemoved -gt 0) {
    Write-Status "Cleaned up $oldSessionsRemoved old Claude sessions" -Type Success
}

# Reset any in-progress tasks to todo
Write-Status "Checking for unfinished tasks..." -Type Process
$tasksBaseDir = Join-Path $PSScriptRoot "..\..\workspace\tasks"
$resetInProgressTasks = Reset-InProgressTasks -TasksBaseDir $tasksBaseDir
$resetSkippedTasks = Reset-SkippedTasks -TasksBaseDir $tasksBaseDir
$totalReset = $resetInProgressTasks.Count + $resetSkippedTasks.Count

if ($totalReset -gt 0) {
    Write-Status "Found $totalReset unfinished tasks" -Type Warn
    
    if ($resetInProgressTasks.Count -gt 0) {
        Write-Phosphor "  In-Progress tasks moved to todo:" -Color Label
        foreach ($resetTask in $resetInProgressTasks) {
            Write-Led $resetTask.name -State Warn -Color Amber
        }
    }
    
    if ($resetSkippedTasks.Count -gt 0) {
        Write-Phosphor "  Skipped tasks moved to todo:" -Color Label
        foreach ($resetTask in $resetSkippedTasks) {
            Write-Host "  $($t.Amber)○$($t.Reset) $($t.Label)$($resetTask.name)$($t.Reset) $($t.Bezel)(skipped $($resetTask.skip_count)x)$($t.Reset)"
        }
    }
} else {
    Write-Status "No unfinished tasks" -Type Complete
}

# Read environment overrides
if ($env:AUTO_CONTINUE_DELAY) {
    $AutoContinueDelay = [int]$env:AUTO_CONTINUE_DELAY
}
if ($env:MAX_RETRIES_PER_TASK) {
    $MaxRetriesPerTask = [int]$env:MAX_RETRIES_PER_TASK
}
if ($env:CONSECUTIVE_FAILURE_THRESHOLD) {
    $ConsecutiveFailureThreshold = [int]$env:CONSECUTIVE_FAILURE_THRESHOLD
}

# Initialize session
Write-Status "Initializing session..." -Type Process
$sessionResult = Invoke-SessionInitialize -Arguments @{ session_type = "autonomous" }

if (-not $sessionResult.success) {
    Write-Status "Failed to initialize session: $($sessionResult.error)" -Type Error
    exit 1
}

$sessionId = $sessionResult.session.session_id
Write-Status "Session initialized" -Type Success
Write-Label "Session ID" $sessionId -ValueColor Cyan
if ($sessionResult.session.current_task_id) {
    Write-Status "Session has existing current_task_id: $($sessionResult.session.current_task_id)" -Type Warn
}

# Create running signal to indicate autonomous loop is active
if (-not (Test-Path $controlDir)) {
    New-Item -Path $controlDir -ItemType Directory -Force | Out-Null
}
$runningSignal = Join-Path $controlDir "running.signal"
@{
    started_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    session_id = $sessionId
    pid = $PID
} | ConvertTo-Json | Set-Content -Path $runningSignal -Force

Write-Host ""

# Track session progress
$sessionState = @{
    session_id = $sessionId
    started_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    tasks_completed = @()
    tasks_attempted = @()
    commits = @()
    notes = @()
}

# Load prompt template
$promptTemplate = Get-Content "$PSScriptRoot\..\..\prompts\workflows\99-autonomous-task.md" -Raw

# Get all standards files
$standardsDir = Join-Path $PSScriptRoot "..\..\prompts\standards\global"
$standardsFiles = @()
if (Test-Path $standardsDir) {
    $standardsFiles = Get-ChildItem -Path $standardsDir -Filter "*.md" -File | 
        ForEach-Object { ".bot/prompts/standards/global/$($_.Name)" }
}

$standardsList = $standardsFiles -join "`n- "
if ($standardsList) {
    $standardsList = "- $standardsList"
} else {
    $standardsList = "No standards files found."
}


# Load product-specific documentation
$productDir = Join-Path $PSScriptRoot "..\..\workspace\product"
$productMissionFile = Join-Path $productDir "mission.md"
$productEntityModelFile = Join-Path $productDir "entity-model.md"

$productMission = if (Test-Path $productMissionFile) {
    "Read the product mission and context from: .bot/workspace/product/mission.md"
} else {
    "No product mission file found."
}

$entityModel = if (Test-Path $productEntityModelFile) {
    "Read the entity model design from: .bot/workspace/product/entity-model.md"
} else {
    "No entity model file found."
}

try {
    $tasksProcessed = 0
    
    # Main loop
    while ($true) {
        # Check if we've hit max tasks
        if ($MaxTasks -gt 0 -and $tasksProcessed -ge $MaxTasks) {
            Write-Host ""
            Write-Status "Reached maximum task limit ($MaxTasks)" -Type Warn
            break
        }
        
        # Check for control signals (use execution-specific stop signal)
        $signal = Test-ControlSignals -ControlDir $controlDir -LoopType 'execution'
        if ($signal -eq 'stop') {
            Write-Host ""
            Write-Status "Stop signal received - halting autonomous loop" -Type Error
            # Clear the signal
            Remove-Item (Join-Path $controlDir "stop-execution.signal") -Force -ErrorAction SilentlyContinue
            break
        }

        if ($signal -eq 'pause') {
            Write-Host ""
            Write-Status "Pause signal received - waiting for resume..." -Type Warn
            $pauseSignalPath = Join-Path $controlDir "pause.signal"

            # Log paused activity
            Write-ActivityLog -Type "text" -Message "Autonomous coding agent paused..."

            # Wait for resume using cached signal state (FileSystemWatcher updates automatically)
            while ($true) {
                Start-Sleep -Seconds 1

                # Refresh signal state from watcher cache
                $currentSignal = Test-ControlSignals -ControlDir $controlDir -LoopType 'execution'

                # Check for stop signal while paused
                if ($currentSignal -eq 'stop') {
                    Write-Host ""
                    Write-Status "Stop signal received while paused" -Type Error
                    Remove-Item (Join-Path $controlDir "stop-execution.signal") -Force -ErrorAction SilentlyContinue
                    Remove-Item $pauseSignalPath -Force -ErrorAction SilentlyContinue
                    break
                }

                # Check if pause signal was removed (resume)
                if ($currentSignal -ne 'pause') {
                    # Update theme on resume (user may have changed it while paused)
                    if (Update-DotBotTheme) {
                        $t = Get-DotBotTheme
                    }
                    Write-Status "Resuming autonomous loop" -Type Success
                    break
                }
            }

            # If we got a stop signal, exit the main loop
            if ((Test-ControlSignals -ControlDir $controlDir -LoopType 'execution') -eq 'stop') {
                break
            }
        }
        
        # Get next task
        Write-Status "Fetching next task..." -Type Process
        $taskResult = Invoke-TaskGetNext -Arguments @{} -Verbose
        
        if (-not $taskResult.success) {
            Write-Status "Error fetching task: $($taskResult.message)" -Type Error
            break
        }
        
        if (-not $taskResult.task) {
            # Log waiting activity (only if not already the last line)
            $activityFile = Join-Path $controlDir "activity.jsonl"
            $waitingMessage = "Waiting for new tasks..."
            $shouldLogWaiting = $true
            
            if (Test-Path $activityFile) {
                try {
                    $fs = [System.IO.FileStream]::new(
                        $activityFile,
                        [System.IO.FileMode]::Open,
                        [System.IO.FileAccess]::Read,
                        [System.IO.FileShare]::ReadWrite
                    )
                    $sr = [System.IO.StreamReader]::new($fs)
                    $allText = $sr.ReadToEnd()
                    $sr.Close()
                    $fs.Close()
                    $lines = $allText -split "`n" | Where-Object { $_.Trim() }
                    $lastLine = if ($lines.Count -gt 0) { $lines[-1] } else { $null }
                } catch {
                    $lastLine = $null
                }
                if ($lastLine) {
                    try {
                        $lastActivity = $lastLine | ConvertFrom-Json
                        if ($lastActivity.type -eq "text" -and $lastActivity.message -eq $waitingMessage) {
                            $shouldLogWaiting = $false
                        }
                    } catch {}
                }
            }
            
            if ($shouldLogWaiting) {
                Write-ActivityLog -Type "text" -Message $waitingMessage
                Write-Status "No tasks available - waiting for new tasks..." -Type Info
            }
            
            # Wait and check for new tasks or control signals
            while ($true) {
                Start-Sleep -Seconds 5

                # Check for control signals (use execution-specific stop signal)
                $signal = Test-ControlSignals -ControlDir $controlDir -LoopType 'execution'
                if ($signal -eq 'stop') {
                    Write-Host ""
                    Write-Status "Stop signal received while waiting" -Type Error
                    Remove-Item (Join-Path $controlDir "stop-execution.signal") -Force -ErrorAction SilentlyContinue
                    $script:shouldStop = $true
                    break
                }

                # Re-check for tasks
                Reset-TaskIndex
                $taskResult = Invoke-TaskGetNext -Arguments @{}
                if ($taskResult.task) {
                    Write-Status "New task found!" -Type Success
                    break
                }
            }
            
            # If stop signal received, exit main loop
            if ($script:shouldStop) {
                break
            }
            
            # If we found a task, continue with it (skip re-fetching)
            if (-not $taskResult.task) {
                continue
            }
        }
        
        Write-Status "Task retrieved" -Type Success
        Write-Phosphor "  $($t.Bezel)ID:$($t.Reset) $($t.Label)$($taskResult.task.id)$($t.Reset)" -Color Label
        Write-Phosphor "  $($t.Bezel)Name:$($t.Reset) $($t.Cyan)$($taskResult.task.name)$($t.Reset)" -Color Label
        
        $task = $taskResult.task
        $taskSource = if ($task.status -eq 'analysed') { 'analysed' } else { 'todo' }
        $hasAnalysis = $taskSource -eq 'analysed'
        
        # Build task card lines
        $sourceLabel = if ($hasAnalysis) { "$($t.Green)analysed (pre-flight ready)$($t.Reset)" } else { "$($t.Amber)todo (legacy mode)$($t.Reset)" }
        $taskLines = @(
            "$($t.Label)ID:$($t.Reset)       $($t.Purple)$($task.id)$($t.Reset)"
            "$($t.Label)Source:$($t.Reset)   $sourceLabel"
            "$($t.Label)Category:$($t.Reset) $($t.Cyan)$($task.category)$($t.Reset)"
            "$($t.Label)Priority:$($t.Reset) $($t.Cyan)$($task.priority)$($t.Reset)"
            "$($t.Label)Effort:$($t.Reset)   $($t.Cyan)$($task.effort)$($t.Reset)"
        )
        
        # Add description if available
        if ($task.description) {
            $taskLines += ""
            $taskLines += "$($t.Amber)Description:$($t.Reset)"
            $wrappedLines = Wrap-Text $task.description 58
            foreach ($line in $wrappedLines) {
                $taskLines += "$($t.Label)$line$($t.Reset)"
            }
        }
        
        # Add acceptance criteria if available
        if ($task.acceptance_criteria -and $task.acceptance_criteria.Count -gt 0) {
            $taskLines += ""
            $taskLines += "$($t.Amber)Acceptance Criteria:$($t.Reset)"
            foreach ($criterion in $task.acceptance_criteria) {
                $taskLines += "$($t.Bezel)[ ]$($t.Reset) $($t.Label)$criterion$($t.Reset)"
            }
        }
        
        # Add dependencies if any
        if ($task.dependencies -and $task.dependencies.Count -gt 0) {
            $taskLines += ""
            $taskLines += "$($t.Amber)Dependencies:$($t.Reset)"
            foreach ($dep in $task.dependencies) {
                $taskLines += "$($t.Bezel)→$($t.Reset) $($t.Label)$dep$($t.Reset)"
            }
        }
        
        Write-Host ""
        Write-Card -Title $task.name -Width 65 -BorderStyle Rounded -BorderColor Label -TitleColor Label -Lines $taskLines
        
        # Mark task as in-progress
        Write-Status "Marking task as in-progress..." -Type Process
        $markInProgressResult = Invoke-TaskMarkInProgress -Arguments @{ task_id = $task.id }
        if (-not $markInProgressResult.success) {
            Write-Status "Failed to mark task in-progress: $($markInProgressResult.message)" -Type Warn
        } else {
            Write-Status "Task marked in-progress" -Type Success
        }
        
        # Update session with current task
        Invoke-SessionUpdate -Arguments @{ current_task_id = $task.id } | Out-Null
        $env:DOTBOT_CURRENT_TASK_ID = $task.id
        $modeLabel = if ($hasAnalysis) { "pre-flight" } else { "legacy" }
        Write-ActivityLog -Type "text" -Message "Started task ($modeLabel): $($task.name)"

        # Generate Claude session ID for execution (new session per task)
        $claudeSessionId = [System.Guid]::NewGuid().ToString()
        $env:CLAUDE_SESSION_ID = $claudeSessionId

        # Update running signal with Claude session ID
        $signalPath = Join-Path $controlDir "running.signal"
        if (Test-Path $signalPath) {
            try {
                $signal = Get-Content $signalPath -Raw | ConvertFrom-Json
                $signal | Add-Member -NotePropertyName 'claude_session_id' -NotePropertyValue $claudeSessionId -Force
                $signal | Add-Member -NotePropertyName 'current_task_id' -NotePropertyValue $task.id -Force
                $tempFile = "$signalPath.tmp"
                $signal | ConvertTo-Json | Set-Content -Path $tempFile -Force
                Move-Item -Path $tempFile -Destination $signalPath -Force
            } catch {
                Write-Warning "Failed to update signal file: $_"
            }
        }

        # Build prompt from template
        $prompt = Build-TaskPrompt `
            -PromptTemplate $promptTemplate `
            -Task $task `
            -SessionId $sessionId `
            -ProductMission $productMission `
            -EntityModel $entityModel `
            -StandardsList $standardsList
        
        # Build completion promise for Go Mode
        $completionPromise = "Task $($task.id) is complete: all acceptance criteria met, verification passed, and task marked done."
        
        # Attempt task with retries
        $attemptNumber = 0
        $taskSuccess = $false
        
        while ($attemptNumber -le $MaxRetriesPerTask) {
            $attemptNumber++
            
            if ($attemptNumber -gt 1) {
                Write-Host ""
                Write-Status "Retry attempt $attemptNumber of $MaxRetriesPerTask" -Type Warn
            }
            
            # Invoke Claude with streaming output
            Write-Header "Claude Session"
            Write-Status "Starting Claude session..." -Type Process
            
            # Build full prompt with completion goal
            $fullPrompt = @"
$prompt

## Completion Goal

$completionPromise

Work on this task autonomously. When complete, ensure you call task_mark_done via MCP.
"@
            
            # Invoke Claude with streaming
            try {
                $streamArgs = @{
                    Prompt = $fullPrompt
                    Model = $claudeModelName
                    SessionId = $claudeSessionId
                    PersistSession = $false  # Execution doesn't need session persistence
                }
                if ($ShowDebug) { $streamArgs['ShowDebugJson'] = $true }
                if ($ShowVerbose) { $streamArgs['ShowVerbose'] = $true }

                Invoke-ClaudeStream @streamArgs
                $exitCode = 0
            } catch {
                Write-Status "Error: $($_.Exception.Message)" -Type Error
                $exitCode = 1
            }
            
            Write-Host ""
            Write-Status "Claude session completed" -Type Info
            if ($exitCode -eq 0) {
                Write-Led "Exit Code" -State On -Color Green
            } else {
                Write-Led "Exit Code" -State Error -Color Red
            }
            
            # Check for rate limit
            $rateLimitMsg = Get-LastRateLimitInfo
            if ($rateLimitMsg) {
                Write-Host ""
                Write-Status "Rate limit detected!" -Type Warn
                
                # Parse the rate limit message to get wait time
                $rateLimitInfo = Get-RateLimitResetTime -Message $rateLimitMsg
                
                if ($rateLimitInfo) {
                    # Wait for rate limit to reset (use execution-specific stop signal)
                    $waitResult = Wait-ForRateLimitReset -RateLimitInfo $rateLimitInfo -ControlDir $controlDir -LoopType 'execution'

                    if ($waitResult -eq "stop") {
                        # Stop signal received during wait
                        $script:shouldStop = $true
                        break
                    }
                    
                    # Don't count this as an attempt - retry immediately
                    $attemptNumber--
                    continue
                }
            }
            
            # Check for completion
            $completionCheck = Test-TaskCompletion -TaskId $task.id
            
            if ($completionCheck.completed) {
                Write-Host ""
                Write-Status "Task completed successfully!" -Type Complete
                Write-Label "Method" $completionCheck.method -ValueColor Cyan
                Write-Label "Reason" $completionCheck.reason -ValueColor Green
                
                # Increment completed counter
                Invoke-SessionIncrementCompleted -Arguments @{} | Out-Null
                
                $taskSuccess = $true
                break
            } else {
                Write-Host ""
                Write-Status "Task not completed" -Type Warn
                Write-Label "Reason" $completionCheck.reason -ValueColor Amber
                
                # Classify failure
                $failureReason = Get-FailureReason `
                    -ExitCode $exitCode `
                    -Stdout "" `
                    -Stderr "" `
                    -TimedOut $false
                
                Write-Label "Failure type" $failureReason.type -ValueColor Amber
                Write-Label "Description" $failureReason.description -ValueColor Cyan
                Write-Label "Suggested action" $failureReason.suggested_action -ValueColor Cyan
                
                # Handle non-recoverable failures
                if (-not $failureReason.recoverable) {
                    Write-Host ""
                    Write-Status "Non-recoverable failure - skipping task" -Type Error
                    
                    # Mark task as skipped via MCP
                    try {
                        $skipResult = Invoke-TaskMarkSkipped -Arguments @{
                            task_id = $task.id
                            skip_reason = "non-recoverable"
                        }
                        Write-Status "Marked as skipped: $($skipResult.skip_reason)" -Type Warn
                        $taskSuccess = $false  # Ensure we don't continue
                    } catch {
                        Write-Status "Error marking task as skipped: $($_.Exception.Message)" -Type Error
                    }
                    break
                }
                
                # Check if we should retry
                if ($attemptNumber -ge $MaxRetriesPerTask) {
                    Write-Host ""
                    Write-Status "Max retries exhausted - skipping task" -Type Error
                    
                    # Mark task as skipped via MCP
                    try {
                        $skipResult = Invoke-TaskMarkSkipped -Arguments @{
                            task_id = $task.id
                            skip_reason = "max-retries"
                        }
                        Write-Status "Marked as skipped: $($skipResult.skip_reason) (skip count: $($skipResult.skip_count))" -Type Warn
                        $taskSuccess = $false  # Ensure we don't continue
                    } catch {
                        Write-Status "Error marking task as skipped: $($_.Exception.Message)" -Type Error
                    }
                    break
                }
            }
        }
        
        # Check if we need to stop (e.g., from rate limit wait)
        if ($script:shouldStop) {
            break
        }
        
        # Update session state based on result
        $sessionState.tasks_attempted += @($task.id)
        
        if ($taskSuccess) {
            # Task completed - consecutive failures reset by Invoke-SessionIncrementCompleted
            $tasksProcessed++
            $sessionState.tasks_completed += @($task.id)
            $sessionState.notes += "Task $($task.id) ($($task.name)): COMPLETED"
            # Activity log is now captured in task-mark-done MCP tool
            # Clean up Claude session data (task complete, no need to preserve)
            Remove-ClaudeSession -SessionId $claudeSessionId -ProjectRoot $projectRoot | Out-Null
        } else {
            # Task failed - update counters
            $state = Invoke-SessionGetState -Arguments @{}
            $newFailures = $state.state.consecutive_failures + 1
            $sessionState.notes += "Task $($task.id) ($($task.name)): FAILED after $attemptNumber attempts"
            
            Invoke-SessionUpdate -Arguments @{ 
                consecutive_failures = $newFailures
                tasks_skipped = $state.state.tasks_skipped + 1
            } | Out-Null
            
            # Check if we should pause
            if ($newFailures -ge $ConsecutiveFailureThreshold) {
                Write-Host ""
                Write-Status "$ConsecutiveFailureThreshold consecutive failures - pausing" -Type Error
                Write-Phosphor "  Review failures and restart the autonomous loop when ready." -Color Label
                
                Invoke-SessionUpdate -Arguments @{ status = "paused" } | Out-Null
                break
            }
        }

        # Clear task context for next iteration
        $env:DOTBOT_CURRENT_TASK_ID = $null
        $env:CLAUDE_SESSION_ID = $null

        # Display task result summary
        Write-Host ""
        if ($taskSuccess) {
            Write-Panel -BorderStyle Rounded -BorderColor Green -Lines @(
                "$($t.Green)✓ TASK COMPLETED$($t.Reset)"
            )
        } else {
            Write-Panel -BorderStyle Rounded -BorderColor Red -Lines @(
                "$($t.Red)✗ TASK FAILED$($t.Reset)"
            )
        }
        
        # Auto-continue delay with signal checking
        if ($AutoContinueDelay -gt 0) {
            Write-Host ""
            Write-Phosphor "Waiting ${AutoContinueDelay}s before next task..." -Color Bezel
            for ($i = 0; $i -lt $AutoContinueDelay; $i++) {
                Start-Sleep -Seconds 1

                # Check for control signals during delay (use execution-specific stop signal)
                $signal = Test-ControlSignals -ControlDir $controlDir -LoopType 'execution'
                if ($signal -eq 'stop') {
                    Write-Host ""
                    Write-Status "Stop signal received during delay" -Type Error
                    Remove-Item (Join-Path $controlDir "stop-execution.signal") -Force -ErrorAction SilentlyContinue
                    $script:shouldStop = $true
                    break
                }

                if ($signal -eq 'pause') {
                    Write-Host ""
                    Write-Status "Pause signal received during delay" -Type Warn
                    $pauseSignalPath = Join-Path $controlDir "pause.signal"

                    # Log paused activity
                    Write-ActivityLog -Type "text" -Message "Autonomous coding agent paused..."

                    # Wait for resume using cached signal state
                    while ($true) {
                        Start-Sleep -Seconds 1
                        $currentSignal = Test-ControlSignals -ControlDir $controlDir -LoopType 'execution'

                        if ($currentSignal -eq 'stop') {
                            Write-Host ""
                            Write-Status "Stop signal received while paused" -Type Error
                            Remove-Item (Join-Path $controlDir "stop-execution.signal") -Force -ErrorAction SilentlyContinue
                            Remove-Item $pauseSignalPath -Force -ErrorAction SilentlyContinue
                            $script:shouldStop = $true
                            break
                        }

                        if ($currentSignal -ne 'pause') {
                            # Update theme on resume (user may have changed it while paused)
                            if (Update-DotBotTheme) {
                                $t = Get-DotBotTheme
                            }
                            Write-Status "Continuing after delay" -Type Success
                            break
                        }
                    }

                    if ($script:shouldStop) {
                        break
                    }
                }
            }

            # Check if we need to stop
            if ($script:shouldStop) {
                break
            }
        }

        # Update theme between tasks (user may have changed it)
        if (Update-DotBotTheme) {
            $t = Get-DotBotTheme
        }

        # Separator for next loop
        Write-Separator -Width 60
    }
    
} finally {
    # Clean up session
    Write-Header "Cleanup"
    Write-Status "Cleaning up session..." -Type Process
    
    # Cleanup temporary Claude directories
    Write-Status "Removing temporary Claude directories..." -Type Process
    
    # Find git root by walking up from current directory
    $projectRoot = $PWD.Path
    while ($projectRoot -and -not (Test-Path (Join-Path $projectRoot ".git"))) {
        $parent = Split-Path -Parent $projectRoot
        if ($parent -eq $projectRoot) {
            # Reached filesystem root without finding .git - use parent of .bot folder
            $projectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
            break
        }
        $projectRoot = $parent
    }
    
    $cleanupCount = Clear-TemporaryClaudeDirectories -ProjectRoot $projectRoot
    if ($cleanupCount -gt 0) {
        Write-Status "Removed $cleanupCount temp directories" -Type Success
    } else {
        Write-Status "No temp directories found" -Type Complete
    }
    
    # Update status to stopped
    Invoke-SessionUpdate -Arguments @{ status = "stopped" } | Out-Null
    
    # Log stopped activity
    Write-ActivityLog -Type "text" -Message "Autonomous coding agent stopped."
    
    # Remove running signal
    $runningSignal = Join-Path $controlDir "running.signal"
    if (Test-Path $runningSignal) {
        Remove-Item $runningSignal -Force -ErrorAction SilentlyContinue
    }
    
    # Release lock
    $lockFile = Join-Path $PSScriptRoot "..\..\workspace\sessions\runs\session.lock"
    if (Test-Path $lockFile) {
        Remove-Item $lockFile -Force
    }
    Write-Status "Session cleanup complete" -Type Success
    
    # Print final stats
    $stats = Invoke-SessionGetStats -Arguments @{}
    if ($stats.success) {
        Write-Host ""
        $summaryLines = @(
            "$($t.Label)Session ID:$($t.Reset)      $($t.Bezel)$($stats.session_id)$($t.Reset)"
            "$($t.Label)Runtime:$($t.Reset)         $($t.Cyan)$($stats.runtime_hours)h$($t.Reset)"
            ""
            "$($t.Label)Tasks completed:$($t.Reset) $($t.Green)$($stats.tasks_completed)$($t.Reset)"
            "$($t.Label)Tasks failed:$($t.Reset)    $($t.Red)$($stats.tasks_failed)$($t.Reset)"
            "$($t.Label)Tasks skipped:$($t.Reset)   $($t.Amber)$($stats.tasks_skipped)$($t.Reset)"
            ""
            "$($t.Label)Completion rate:$($t.Reset) $($t.Cyan)$($stats.completion_rate)%$($t.Reset)"
        )
        Write-Card -Title "SESSION SUMMARY" -Width 50 -BorderStyle Rounded -BorderColor Label -TitleColor Label -Lines $summaryLines
        
        if ($stats.summary) {
            Write-Host ""
            Write-Phosphor $stats.summary -Color Cyan
        }
    }
}

Write-Host ""
Write-Status "Autonomous loop stopped" -Type Info
