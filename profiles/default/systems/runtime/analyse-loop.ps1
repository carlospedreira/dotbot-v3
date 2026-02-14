<#
.SYNOPSIS
Orchestration loop for pre-flight task analysis (98-Analyse workflow)

.DESCRIPTION
Manages the analysis loop for pre-flight task preparation:
- Fetches todo tasks based on configured mode (batch or on-demand)
- Builds prompt from 98-analyse-task template
- Invokes Claude for analysis
- Handles needs-input state transitions
- Auto-continues to next task after completion

.PARAMETER MaxTasks
Maximum number of tasks to analyse before stopping (default: unlimited)

.PARAMETER AutoContinueDelay
Seconds to wait between tasks (default: 3)

.PARAMETER Model
Claude model to use (Opus, Sonnet, or Haiku; default: Sonnet for cost efficiency)

.PARAMETER ShowDebug
Show raw JSON events in dark gray

.PARAMETER ShowVerbose
Show detailed tool results and metadata

.PARAMETER Mode
Analysis mode: 'batch' (analyse all todo upfront) or 'on-demand' (analyse as needed)
Defaults to value from settings.default.json

.EXAMPLE
.\analyse-loop.ps1

.EXAMPLE
.\analyse-loop.ps1 -MaxTasks 5 -Model Opus

.EXAMPLE
.\analyse-loop.ps1 -Mode on-demand
#>

param(
    [Parameter(Mandatory = $false)]
    [int]$MaxTasks = 0,  # 0 = unlimited
    
    [Parameter(Mandatory = $false)]
    [int]$AutoContinueDelay = 3,
    
    [Parameter(Mandatory = $false)]
    [ValidateSet('Opus', 'Sonnet', 'Haiku')]
[string]$Model = 'Opus',
    
    [Parameter(Mandatory = $false)]
    [switch]$ShowDebug,
    
    [Parameter(Mandatory = $false)]
    [switch]$ShowVerbose,
    
    [Parameter(Mandatory = $false)]
    [ValidateSet('batch', 'on-demand')]
    [string]$Mode
)

# Map model parameter to Claude model name
$modelMap = @{
    'Opus'   = 'claude-opus-4-5-20251101'
    'Sonnet' = 'claude-sonnet-4-5-20250929'
    'Haiku'  = 'claude-haiku-4-5-20251001'
}

$claudeModelName = $modelMap[$Model]
$env:CLAUDE_MODEL = $claudeModelName

# Set phase for activity logging - all activity in this loop is 'analysis' phase
$env:DOTBOT_CURRENT_PHASE = 'analysis'

# Control directory for signal files (.bot/.control - analyse-loop is at .bot/systems/runtime)
$controlDir = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) ".control"

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
. "$PSScriptRoot\modules\rate-limit-handler.ps1"

# Import MCP tool functions (for direct PowerShell calls)
# Note: session-initialize/get-state/update are NOT imported here.
# The analysis loop uses signal files (.control/analysing.signal) for status,
# not the session lock system, to avoid conflicts with the run-loop.
. "$PSScriptRoot\..\mcp\tools\task-get-next\script.ps1"
. "$PSScriptRoot\..\mcp\tools\task-mark-analysing\script.ps1"
. "$PSScriptRoot\..\mcp\tools\task-mark-skipped\script.ps1"

# Load settings for analysis mode and model
$settingsPath = Join-Path $PSScriptRoot "..\..\defaults\settings.default.json"
$settings = @{ analysis = @{ mode = 'batch'; model = 'Opus' } }
if (Test-Path $settingsPath) {
    try {
        $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
    } catch {
        Write-Warning "Failed to load settings: $_"
    }
}

# Determine analysis mode (parameter overrides settings)
if (-not $Mode) {
    $Mode = if ($settings.analysis -and $settings.analysis.mode) { $settings.analysis.mode } else { 'batch' }
}

# Determine model (parameter overrides settings)
if (-not $PSBoundParameters.ContainsKey('Model')) {
    $Model = if ($settings.analysis -and $settings.analysis.model) { $settings.analysis.model } else { 'Opus' }
}

# Build prompt builder function for analysis
function Build-AnalysisPrompt {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PromptTemplate,
        
        [Parameter(Mandatory = $true)]
        [object]$Task,
        
        [Parameter(Mandatory = $true)]
        [string]$SessionId
    )
    
    # Start with template
    $prompt = $PromptTemplate
    
    # Replace basic task info
    $prompt = $prompt -replace '\{\{SESSION_ID\}\}', $SessionId
    $prompt = $prompt -replace '\{\{TASK_ID\}\}', $Task.id
    $prompt = $prompt -replace '\{\{TASK_NAME\}\}', $Task.name
    $prompt = $prompt -replace '\{\{TASK_CATEGORY\}\}', $Task.category
    $prompt = $prompt -replace '\{\{TASK_PRIORITY\}\}', $Task.priority
    $prompt = $prompt -replace '\{\{TASK_EFFORT\}\}', $Task.effort
    $prompt = $prompt -replace '\{\{TASK_DESCRIPTION\}\}', $Task.description

    # Replace needs_interview flag (default to false if not set)
    $needsInterview = if ($Task.needs_interview) { 'true' } else { 'false' }
    $prompt = $prompt -replace '\{\{NEEDS_INTERVIEW\}\}', $needsInterview
    
    # Format and replace acceptance criteria
    $acceptanceCriteria = if ($Task.acceptance_criteria) {
        ($Task.acceptance_criteria | ForEach-Object { "- $_" }) -join "`n"
    } else {
        "No specific acceptance criteria defined."
    }
    $prompt = $prompt -replace '\{\{ACCEPTANCE_CRITERIA\}\}', $acceptanceCriteria
    
    # Format and replace steps
    $steps = if ($Task.steps) {
        ($Task.steps | ForEach-Object { "- $_" }) -join "`n"
    } else {
        "No specific steps defined."
    }
    $prompt = $prompt -replace '\{\{TASK_STEPS\}\}', $steps
    
    return $prompt
}

# Check if task completed analysis (moved to analysed, needs-input, or picked up by executor)
function Test-AnalysisCompletion {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TaskId
    )
    
    $tasksBaseDir = Join-Path $PSScriptRoot "..\..\workspace\tasks"
    $analysedDir = Join-Path $tasksBaseDir "analysed"
    $needsInputDir = Join-Path $tasksBaseDir "needs-input"
    $skippedDir = Join-Path $tasksBaseDir "skipped"
    $inProgressDir = Join-Path $tasksBaseDir "in-progress"
    $doneDir = Join-Path $tasksBaseDir "done"
    
    # Check if task is in analysed folder
    if (Test-Path $analysedDir) {
        $files = Get-ChildItem -Path $analysedDir -Filter "*.json" -File
        foreach ($file in $files) {
            try {
                $content = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json
                if ($content.id -eq $TaskId) {
                    return @{
                        completed = $true
                        status = 'analysed'
                        reason = "Task analysis complete - ready for implementation"
                    }
                }
            } catch {}
        }
    }
    
    # Check if task is in needs-input folder
    if (Test-Path $needsInputDir) {
        $files = Get-ChildItem -Path $needsInputDir -Filter "*.json" -File
        foreach ($file in $files) {
            try {
                $content = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json
                if ($content.id -eq $TaskId) {
                    $inputType = if ($content.pending_question) { "question" } else { "split proposal" }
                    return @{
                        completed = $true
                        status = 'needs-input'
                        reason = "Task paused for human input - $inputType pending"
                    }
                }
            } catch {}
        }
    }
    
    # Check if task was skipped
    if (Test-Path $skippedDir) {
        $files = Get-ChildItem -Path $skippedDir -Filter "*.json" -File
        foreach ($file in $files) {
            try {
                $content = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json
                if ($content.id -eq $TaskId) {
                    return @{
                        completed = $true
                        status = 'skipped'
                        reason = "Task skipped during analysis: $($content.skip_reason)"
                    }
                }
            } catch {}
        }
    }
    
    # Check if executor already picked up the task (in-progress)
    if (Test-Path $inProgressDir) {
        $files = Get-ChildItem -Path $inProgressDir -Filter "*.json" -File
        foreach ($file in $files) {
            try {
                $content = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json
                if ($content.id -eq $TaskId) {
                    return @{
                        completed = $true
                        status = 'in-progress'
                        reason = "Task picked up by executor - now in progress"
                    }
                }
            } catch {}
        }
    }
    
    # Check if executor already completed the task (done)
    if (Test-Path $doneDir) {
        $files = Get-ChildItem -Path $doneDir -Filter "*.json" -File
        foreach ($file in $files) {
            try {
                $content = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json
                if ($content.id -eq $TaskId) {
                    return @{
                        completed = $true
                        status = 'done'
                        reason = "Task already completed by executor"
                    }
                }
            } catch {}
        }
    }
    
    return @{
        completed = $false
        status = 'unknown'
        reason = "Task not found in expected status folders"
    }
}

# Get next task for analysis
# Checks two sources:
# 1. Tasks in analysing/ that returned from needs-input (question answered, need re-analysis)
# 2. Tasks in todo/ that haven't been analysed yet
function Get-NextTodoTask {
    param(
        [switch]$Verbose
    )

    # First priority: check for analysing tasks that came back from needs-input
    $index = Get-TaskIndex
    $resumedTasks = @($index.Analysing.Values) | Sort-Object priority
    foreach ($candidate in $resumedTasks) {
        # Read the full JSON to check for answered questions
        if ($candidate.file_path -and (Test-Path $candidate.file_path)) {
            try {
                $content = Get-Content -Path $candidate.file_path -Raw | ConvertFrom-Json
                # Task has answered questions and no pending question = ready to resume analysis
                if ($content.questions_resolved -and $content.questions_resolved.Count -gt 0 -and -not $content.pending_question) {
                    Write-Status "Found resumed task (question answered): $($candidate.name)" -Type Info
                    $taskObj = @{
                        id = $content.id
                        name = $content.name
                        status = 'analysing'
                        priority = [int]$content.priority
                        effort = $content.effort
                        category = $content.category
                    }
                    if ($Verbose.IsPresent) {
                        $taskObj.description = $content.description
                        $taskObj.dependencies = $content.dependencies
                        $taskObj.acceptance_criteria = $content.acceptance_criteria
                        $taskObj.steps = $content.steps
                        $taskObj.applicable_agents = $content.applicable_agents
                        $taskObj.applicable_standards = $content.applicable_standards
                        $taskObj.file_path = $candidate.file_path
                        $taskObj.questions_resolved = $content.questions_resolved
                        $taskObj.claude_session_id = $content.claude_session_id
                        $taskObj.needs_interview = $content.needs_interview
                    }
                    return @{
                        success = $true
                        task = $taskObj
                        message = "Resumed task (question answered): $($content.name)"
                    }
                }
            } catch {
                Write-Warning "Failed to read analysing task: $($candidate.file_path) - $_"
            }
        }
    }

    # Second priority: get next todo task
    $result = Invoke-TaskGetNext -Arguments @{ prefer_analysed = $false; verbose = $Verbose.IsPresent }

    # Only return if it's a todo task (not analysed)
    if ($result.task -and $result.task.status -eq 'todo') {
        return $result
    }

    # No tasks available
    return @{
        success = $true
        task = $null
        message = "No tasks available for analysis."
    }
}

# Banner and configuration display
Write-Card -Title "ANALYSE LOOP (98-Preflight)" -Width 50 -BorderStyle Rounded -BorderColor Label -TitleColor Label -Lines @(
    "$($t.Amber)Pre-flight task analysis$($t.Reset)"
)

$maxTasksValue = if ($MaxTasks -eq 0) { 'unlimited' } else { $MaxTasks }
$configLines = @(
    "$($t.Label)Max tasks:$($t.Reset)         $($t.Cyan)$maxTasksValue$($t.Reset)"
    "$($t.Label)Auto-continue:$($t.Reset)     $($t.Cyan)${AutoContinueDelay}s$($t.Reset)"
    "$($t.Label)Model:$($t.Reset)             $($t.Purple)$Model$($t.Reset)"
    "$($t.Label)Mode:$($t.Reset)              $($t.Cyan)$Mode$($t.Reset)"
)
if ($ShowDebug) { $configLines += "$($t.Label)Debug:$($t.Reset)             $($t.Green)enabled$($t.Reset)" }
if ($ShowVerbose) { $configLines += "$($t.Label)Verbose:$($t.Reset)           $($t.Green)enabled$($t.Reset)" }

Write-Card -Title "CONFIGURATION" -Width 50 -BorderStyle Rounded -BorderColor Label -TitleColor Label -Lines $configLines

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

# Initialize session (local ID only - analysis loop uses signal files, not session locks)
Write-Header "Startup"
Write-Status "Initializing analysis session..." -Type Process
$sessionId = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH-mm-ssZ")
Write-Status "Analysis session ready" -Type Success
Write-Label "Session ID" $sessionId -ValueColor Cyan

# Create running signal to indicate analysis loop is active
if (-not (Test-Path $controlDir)) {
    New-Item -Path $controlDir -ItemType Directory -Force | Out-Null
}
$runningSignal = Join-Path $controlDir "analysing.signal"
@{
    started_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    session_id = $sessionId
    mode = $Mode
    pid = $PID
} | ConvertTo-Json | Set-Content -Path $runningSignal -Force

Write-Host ""

# Load prompt template
$promptTemplate = Get-Content "$PSScriptRoot\..\..\prompts\workflows\98-analyse-task.md" -Raw

# Initialize task index
$tasksBaseDir = Join-Path $PSScriptRoot "..\..\workspace\tasks"
Initialize-TaskIndex -TasksBaseDir $tasksBaseDir

# Clean up old Claude sessions at startup
$oldSessionsRemoved = Clear-OldClaudeSessions -ProjectRoot $projectRoot -MaxAgeDays 7
if ($oldSessionsRemoved -gt 0) {
    Write-Status "Cleaned up $oldSessionsRemoved old Claude sessions" -Type Success
}

try {
    $tasksAnalysed = 0
    
    # Main loop
    while ($true) {
        # Check if we've hit max tasks
        if ($MaxTasks -gt 0 -and $tasksAnalysed -ge $MaxTasks) {
            Write-Host ""
            Write-Status "Reached maximum task limit ($MaxTasks)" -Type Warn
            break
        }
        
        # Check for control signals (use analysis-specific stop signal)
        $signal = Test-ControlSignals -ControlDir $controlDir -LoopType 'analysis'
        if ($signal -eq 'stop') {
            Write-Host ""
            Write-Status "Stop signal received - halting analysis loop" -Type Error
            Remove-Item (Join-Path $controlDir "stop-analysis.signal") -Force -ErrorAction SilentlyContinue
            break
        }

        if ($signal -eq 'pause') {
            Write-Host ""
            Write-Status "Pause signal received - waiting for resume..." -Type Warn
            $pauseSignalPath = Join-Path $controlDir "pause.signal"

            Write-ActivityLog -Type "text" -Message "Analysis loop paused..."

            while ($true) {
                Start-Sleep -Seconds 1
                $currentSignal = Test-ControlSignals -ControlDir $controlDir -LoopType 'analysis'

                if ($currentSignal -eq 'stop') {
                    Write-Host ""
                    Write-Status "Stop signal received while paused" -Type Error
                    Remove-Item (Join-Path $controlDir "stop-analysis.signal") -Force -ErrorAction SilentlyContinue
                    Remove-Item $pauseSignalPath -Force -ErrorAction SilentlyContinue
                    break
                }

                if ($currentSignal -ne 'pause') {
                    # Update theme on resume (user may have changed it while paused)
                    if (Update-DotBotTheme) {
                        $t = Get-DotBotTheme
                    }
                    Write-Status "Resuming analysis loop" -Type Success
                    break
                }
            }

            if ((Test-ControlSignals -ControlDir $controlDir -LoopType 'analysis') -eq 'stop') {
                break
            }
        }

        # Get next todo task for analysis
        Write-Status "Fetching next task for analysis..." -Type Process
        Reset-TaskIndex
        $taskResult = Get-NextTodoTask -Verbose
        
        if (-not $taskResult.success) {
            Write-Status "Error fetching task: $($taskResult.message)" -Type Error
            break
        }
        
        if (-not $taskResult.task) {
            Write-Status "No tasks available for analysis" -Type Info

            # In batch mode, check if there are needs-input tasks we should wait for
            if ($Mode -eq 'batch') {
                $index = Get-TaskIndex
                $needsInputCount = $index.NeedsInput.Count
                if ($needsInputCount -gt 0) {
                    Write-Status "$needsInputCount task(s) awaiting input - waiting for answers..." -Type Warn
                    # Wait for answers before exiting batch mode
                    while ($true) {
                        Start-Sleep -Seconds 5

                        $signal = Test-ControlSignals -ControlDir $controlDir -LoopType 'analysis'
                        if ($signal -eq 'stop') {
                            Write-Host ""
                            Write-Status "Stop signal received while waiting for input" -Type Error
                            Remove-Item (Join-Path $controlDir "stop-analysis.signal") -Force -ErrorAction SilentlyContinue
                            $script:shouldStop = $true
                            break
                        }

                        Reset-TaskIndex
                        $taskResult = Get-NextTodoTask -Verbose
                        if ($taskResult.task) {
                            Write-Status "Task ready for analysis (question answered or new task)!" -Type Success
                            break
                        }

                        # Check if all needs-input resolved (moved to analysed/done/etc)
                        $freshIndex = Get-TaskIndex
                        if ($freshIndex.NeedsInput.Count -eq 0 -and $freshIndex.Todo.Count -eq 0) {
                            # Check for resumed analysing tasks one more time
                            $taskResult = Get-NextTodoTask -Verbose
                            if ($taskResult.task) {
                                break
                            }
                            Write-Status "All questions resolved - batch analysis complete" -Type Complete
                            $script:shouldStop = $true
                            break
                        }
                    }

                    if ($script:shouldStop) {
                        break
                    }

                    if (-not $taskResult.task) {
                        continue
                    }
                } else {
                    Write-Status "Batch analysis complete - all tasks analysed" -Type Complete
                    break
                }
            }

            # In on-demand mode, wait for new tasks or answered questions
            Write-ActivityLog -Type "text" -Message "Waiting for new tasks or answered questions..."
            
            while ($true) {
                Start-Sleep -Seconds 5

                $signal = Test-ControlSignals -ControlDir $controlDir -LoopType 'analysis'
                if ($signal -eq 'stop') {
                    Write-Host ""
                    Write-Status "Stop signal received while waiting" -Type Error
                    Remove-Item (Join-Path $controlDir "stop-analysis.signal") -Force -ErrorAction SilentlyContinue
                    $script:shouldStop = $true
                    break
                }

                Reset-TaskIndex
                $taskResult = Get-NextTodoTask -Verbose
                if ($taskResult.task) {
                    Write-Status "Task found for analysis!" -Type Success
                    break
                }
            }
            
            if ($script:shouldStop) {
                break
            }
            
            if (-not $taskResult.task) {
                continue
            }
        }
        
        Write-Status "Task retrieved" -Type Success
        Write-Phosphor "  $($t.Bezel)ID:$($t.Reset) $($t.Label)$($taskResult.task.id)$($t.Reset)" -Color Label
        Write-Phosphor "  $($t.Bezel)Name:$($t.Reset) $($t.Cyan)$($taskResult.task.name)$($t.Reset)" -Color Label
        
        $task = $taskResult.task
        $isResumedTask = ($task.status -eq 'analysing')

        # Need full task details for analysis prompt
        if ($isResumedTask) {
            # Resumed task already has verbose data from Get-NextTodoTask
            # (it reads the full JSON to check questions_resolved)
        } else {
            $fullTaskResult = Invoke-TaskGetNext -Arguments @{ prefer_analysed = $false; verbose = $true }
            if ($fullTaskResult.task -and $fullTaskResult.task.id -eq $task.id) {
                $task = $fullTaskResult.task
            }
        }
        
        # Build task card lines
        $taskLines = @(
            "$($t.Label)ID:$($t.Reset)       $($t.Purple)$($task.id)$($t.Reset)"
            "$($t.Label)Category:$($t.Reset) $($t.Cyan)$($task.category)$($t.Reset)"
            "$($t.Label)Priority:$($t.Reset) $($t.Cyan)$($task.priority)$($t.Reset)"
            "$($t.Label)Effort:$($t.Reset)   $($t.Cyan)$($task.effort)$($t.Reset)"
        )
        
        if ($task.description) {
            $taskLines += ""
            $taskLines += "$($t.Amber)Description:$($t.Reset)"
            $wrappedLines = Wrap-Text $task.description 58
            foreach ($line in $wrappedLines) {
                $taskLines += "$($t.Label)$line$($t.Reset)"
            }
        }
        
        Write-Host ""
        Write-Card -Title "ANALYSING: $($task.name)" -Width 65 -BorderStyle Rounded -BorderColor Label -TitleColor Label -Lines $taskLines
        
        $env:DOTBOT_CURRENT_TASK_ID = $task.id
        Write-ActivityLog -Type "text" -Message "Analysing task: $($task.name)"

        # Generate new Claude session ID
        # NOTE: Session continuation via --session-id doesn't work for programmatic resumption
        # after needs-input. The prompt includes resolved questions context instead.
        $claudeSessionId = [System.Guid]::NewGuid().ToString()
        $env:CLAUDE_SESSION_ID = $claudeSessionId

        if ($isResumedTask) {
            Write-Status "Starting new session (previous: $($task.claude_session_id))" -Type Info
        }

        # Update signal file with Claude session ID
        $signalPath = Join-Path $controlDir "analysing.signal"
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
        $prompt = Build-AnalysisPrompt `
            -PromptTemplate $promptTemplate `
            -Task $task `
            -SessionId $sessionId
        
        # Build resolved questions context for resumed tasks
        $resolvedQuestionsContext = ""
        if ($isResumedTask -and $task.questions_resolved) {
            $resolvedQuestionsContext = "`n## Previously Resolved Questions`n`n"
            $resolvedQuestionsContext += "This task was previously paused for human input. The following questions have been answered:`n`n"
            foreach ($q in $task.questions_resolved) {
                $resolvedQuestionsContext += "**Q:** $($q.question)`n"
                $resolvedQuestionsContext += "**A:** $($q.answer)`n`n"
            }
            $resolvedQuestionsContext += "Use these answers to guide your analysis. The task is already in ``analysing`` status - do NOT call ``task_mark_analysing`` again.`n"
        }

        # Build completion goal
        $completionGoal = @"
Analyse task $($task.id) completely. When analysis is finished:
- If all context is gathered: Call task_mark_analysed with the full analysis object
- If you need human input: Call task_mark_needs_input with a question or split_proposal
- If blocked by issues: Call task_mark_skipped with a reason

Do NOT implement the task. Your job is research and preparation only.
"@
        
        $fullPrompt = @"
$prompt
$resolvedQuestionsContext
## Completion Goal

$completionGoal
"@
        
        # Invoke Claude with streaming
        Write-Header "Claude Analysis Session"
        Write-Status "Starting Claude analysis session..." -Type Process
        
        try {
            $streamArgs = @{
                Prompt = $fullPrompt
                Model = $claudeModelName
                SessionId = $claudeSessionId
                PersistSession = $false  # Don't persist - session continuation doesn't work for programmatic resumption
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
            
            $rateLimitInfo = Get-RateLimitResetTime -Message $rateLimitMsg
            
            if ($rateLimitInfo) {
                # Wait for rate limit to reset (use analysis-specific stop signal)
                $waitResult = Wait-ForRateLimitReset -RateLimitInfo $rateLimitInfo -ControlDir $controlDir -LoopType 'analysis'

                if ($waitResult -eq "stop") {
                    $script:shouldStop = $true
                    break
                }
                
                # Retry this task
                continue
            }
        }
        
        # Check for completion (task should be in analysed, needs-input, or skipped)
        $completionCheck = Test-AnalysisCompletion -TaskId $task.id
        
        if ($completionCheck.completed) {
            Write-Host ""
            
            switch ($completionCheck.status) {
                'analysed' {
                    Write-Status "Task analysis complete!" -Type Complete
                    $tasksAnalysed++
                    # Clean up session data - analysis complete, no need to resume
                    Remove-ClaudeSession -SessionId $claudeSessionId -ProjectRoot $projectRoot | Out-Null
                }
                'needs-input' {
                    Write-Status "Task paused for human input" -Type Warn
                    # Don't increment - task needs human before it can be used
                    # Session is preserved for resumption - don't clean up
                }
                'skipped' {
                    Write-Status "Task skipped during analysis" -Type Warn
                    $tasksAnalysed++  # Count as processed
                    # Clean up session data - task skipped
                    Remove-ClaudeSession -SessionId $claudeSessionId -ProjectRoot $projectRoot | Out-Null
                }
                'in-progress' {
                    Write-Status "Task picked up by executor!" -Type Complete
                    $tasksAnalysed++
                    # Clean up session data - task moved to execution
                    Remove-ClaudeSession -SessionId $claudeSessionId -ProjectRoot $projectRoot | Out-Null
                }
                'done' {
                    Write-Status "Task already completed by executor!" -Type Complete
                    $tasksAnalysed++
                    # Clean up session data - task done
                    Remove-ClaudeSession -SessionId $claudeSessionId -ProjectRoot $projectRoot | Out-Null
                }
            }
            
            Write-Label "Status" $completionCheck.status -ValueColor Cyan
            Write-Label "Reason" $completionCheck.reason -ValueColor Green
        } else {
            Write-Host ""
            Write-Status "Analysis may be incomplete" -Type Warn
            Write-Label "Reason" $completionCheck.reason -ValueColor Amber
            
            # Task didn't complete properly - may need retry or manual intervention
            # For now, just continue to next task
        }
        
        # Clear task context for next iteration
        $env:DOTBOT_CURRENT_TASK_ID = $null
        $env:CLAUDE_SESSION_ID = $null
        
        # Display result summary
        Write-Host ""
        if ($completionCheck.completed -and $completionCheck.status -in @('analysed', 'in-progress', 'done')) {
            Write-Panel -BorderStyle Rounded -BorderColor Green -Lines @(
                "$($t.Green)✓ ANALYSIS COMPLETE$($t.Reset)"
            )
        } elseif ($completionCheck.completed -and $completionCheck.status -eq 'needs-input') {
            Write-Panel -BorderStyle Rounded -BorderColor Amber -Lines @(
                "$($t.Amber)⏸ AWAITING INPUT$($t.Reset)"
            )
        } else {
            Write-Panel -BorderStyle Rounded -BorderColor Red -Lines @(
                "$($t.Red)✗ ANALYSIS INCOMPLETE$($t.Reset)"
            )
        }
        
        # Auto-continue delay with signal checking
        if ($AutoContinueDelay -gt 0) {
            Write-Host ""
            Write-Phosphor "Waiting ${AutoContinueDelay}s before next task..." -Color Bezel
            for ($i = 0; $i -lt $AutoContinueDelay; $i++) {
                Start-Sleep -Seconds 1

                $signal = Test-ControlSignals -ControlDir $controlDir -LoopType 'analysis'
                if ($signal -eq 'stop') {
                    Write-Host ""
                    Write-Status "Stop signal received during delay" -Type Error
                    Remove-Item (Join-Path $controlDir "stop-analysis.signal") -Force -ErrorAction SilentlyContinue
                    $script:shouldStop = $true
                    break
                }

                if ($signal -eq 'pause') {
                    Write-Host ""
                    Write-Status "Pause signal received during delay" -Type Warn
                    $pauseSignalPath = Join-Path $controlDir "pause.signal"

                    Write-ActivityLog -Type "text" -Message "Analysis loop paused..."

                    while ($true) {
                        Start-Sleep -Seconds 1
                        $currentSignal = Test-ControlSignals -ControlDir $controlDir -LoopType 'analysis'

                        if ($currentSignal -eq 'stop') {
                            Write-Host ""
                            Write-Status "Stop signal received while paused" -Type Error
                            Remove-Item (Join-Path $controlDir "stop-analysis.signal") -Force -ErrorAction SilentlyContinue
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
    Write-Status "Cleaning up analysis session..." -Type Process
    
    # Log stopped activity
    Write-ActivityLog -Type "text" -Message "Analysis loop stopped."
    
    # Remove running signal
    $runningSignal = Join-Path $controlDir "analysing.signal"
    if (Test-Path $runningSignal) {
        Remove-Item $runningSignal -Force -ErrorAction SilentlyContinue
    }
    
    Write-Status "Session cleanup complete" -Type Success
    
    # Print final stats
    Write-Host ""
    $summaryLines = @(
        "$($t.Label)Session ID:$($t.Reset)       $($t.Bezel)$sessionId$($t.Reset)"
        "$($t.Label)Tasks analysed:$($t.Reset)   $($t.Green)$tasksAnalysed$($t.Reset)"
        "$($t.Label)Mode:$($t.Reset)             $($t.Cyan)$Mode$($t.Reset)"
    )
    Write-Card -Title "ANALYSIS SUMMARY" -Width 50 -BorderStyle Rounded -BorderColor Label -TitleColor Label -Lines $summaryLines
}

Write-Host ""
Write-Status "Analysis loop stopped" -Type Info
