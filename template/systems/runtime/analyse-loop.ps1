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
    [string]$Model = 'Sonnet',
    
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
. "$PSScriptRoot\modules\cleanup.ps1"
. "$PSScriptRoot\modules\rate-limit-handler.ps1"

# Import MCP tool functions (for direct PowerShell calls)
. "$PSScriptRoot\..\mcp\tools\session-initialize\script.ps1"
. "$PSScriptRoot\..\mcp\tools\session-get-state\script.ps1"
. "$PSScriptRoot\..\mcp\tools\session-update\script.ps1"
. "$PSScriptRoot\..\mcp\tools\task-get-next\script.ps1"
. "$PSScriptRoot\..\mcp\tools\task-mark-analysing\script.ps1"
. "$PSScriptRoot\..\mcp\tools\task-mark-skipped\script.ps1"

# Load settings for analysis mode
$settingsPath = Join-Path $PSScriptRoot "..\..\defaults\settings.default.json"
$settings = @{ analysis = @{ mode = 'batch' } }
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

# Check if task completed analysis (moved to analysed or needs-input)
function Test-AnalysisCompletion {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TaskId
    )
    
    $tasksBaseDir = Join-Path $PSScriptRoot "..\..\workspace\tasks"
    $analysedDir = Join-Path $tasksBaseDir "analysed"
    $needsInputDir = Join-Path $tasksBaseDir "needs-input"
    $skippedDir = Join-Path $tasksBaseDir "skipped"
    
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
    
    return @{
        completed = $false
        status = 'unknown'
        reason = "Task not found in expected status folders"
    }
}

# Get next task for analysis (only from todo/ folder, not analysed/)
function Get-NextTodoTask {
    param(
        [switch]$Verbose
    )
    
    $result = Invoke-TaskGetNext -Arguments @{ prefer_analysed = $false; verbose = $Verbose.IsPresent }
    
    # Only return if it's a todo task (not analysed)
    if ($result.task -and $result.task.status -eq 'todo') {
        return $result
    }
    
    # No todo tasks available
    return @{
        success = $true
        task = $null
        message = "No todo tasks available for analysis."
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

# Initialize session
Write-Header "Startup"
Write-Status "Initializing analysis session..." -Type Process
$sessionResult = Invoke-SessionInitialize -Arguments @{ session_type = "analysis" }

if (-not $sessionResult.success) {
    Write-Status "Failed to initialize session: $($sessionResult.error)" -Type Error
    exit 1
}

$sessionId = $sessionResult.session.session_id
Write-Status "Session initialized" -Type Success
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
} | ConvertTo-Json | Set-Content -Path $runningSignal -Force

Write-Host ""

# Load prompt template
$promptTemplate = Get-Content "$PSScriptRoot\..\..\prompts\workflows\98-analyse-task.md" -Raw

# Initialize task index
$tasksBaseDir = Join-Path $PSScriptRoot "..\..\workspace\tasks"
Initialize-TaskIndex -TasksBaseDir $tasksBaseDir

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
        
        # Check for control signals
        $signal = Test-ControlSignals -ControlDir $controlDir
        if ($signal -eq 'stop') {
            Write-Host ""
            Write-Status "Stop signal received - halting analysis loop" -Type Error
            Remove-Item (Join-Path $controlDir "stop.signal") -Force -ErrorAction SilentlyContinue
            break
        }
        
        if ($signal -eq 'pause') {
            Write-Host ""
            Write-Status "Pause signal received - waiting for resume..." -Type Warn
            $pauseSignalPath = Join-Path $controlDir "pause.signal"
            
            Write-ActivityLog -Type "text" -Message "Analysis loop paused..."
            
            while ($true) {
                Start-Sleep -Seconds 1
                $currentSignal = Test-ControlSignals -ControlDir $controlDir
                
                if ($currentSignal -eq 'stop') {
                    Write-Host ""
                    Write-Status "Stop signal received while paused" -Type Error
                    Remove-Item (Join-Path $controlDir "stop.signal") -Force -ErrorAction SilentlyContinue
                    Remove-Item $pauseSignalPath -Force -ErrorAction SilentlyContinue
                    break
                }
                
                if ($currentSignal -ne 'pause') {
                    Write-Status "Resuming analysis loop" -Type Success
                    break
                }
            }
            
            if ((Test-ControlSignals -ControlDir $controlDir) -eq 'stop') {
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
            Write-Status "No todo tasks available for analysis" -Type Info
            
            # In batch mode, we're done when no todo tasks remain
            if ($Mode -eq 'batch') {
                Write-Status "Batch analysis complete - all tasks analysed or pending input" -Type Complete
                break
            }
            
            # In on-demand mode, wait for new tasks
            Write-ActivityLog -Type "text" -Message "Waiting for new tasks to analyse..."
            
            while ($true) {
                Start-Sleep -Seconds 5
                
                $signal = Test-ControlSignals -ControlDir $controlDir
                if ($signal -eq 'stop') {
                    Write-Host ""
                    Write-Status "Stop signal received while waiting" -Type Error
                    Remove-Item (Join-Path $controlDir "stop.signal") -Force -ErrorAction SilentlyContinue
                    $script:shouldStop = $true
                    break
                }
                
                Reset-TaskIndex
                $taskResult = Get-NextTodoTask
                if ($taskResult.task) {
                    Write-Status "New task found for analysis!" -Type Success
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
        
        # Need full task details for analysis prompt
        $fullTaskResult = Invoke-TaskGetNext -Arguments @{ prefer_analysed = $false; verbose = $true }
        if ($fullTaskResult.task -and $fullTaskResult.task.id -eq $task.id) {
            $task = $fullTaskResult.task
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
        
        # Update session with current task
        Invoke-SessionUpdate -Arguments @{ current_task_id = $task.id } | Out-Null
        $env:DOTBOT_CURRENT_TASK_ID = $task.id
        Write-ActivityLog -Type "text" -Message "Analysing task: $($task.name)"
        
        # Build prompt from template
        $prompt = Build-AnalysisPrompt `
            -PromptTemplate $promptTemplate `
            -Task $task `
            -SessionId $sessionId
        
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
                $waitResult = Wait-ForRateLimitReset -RateLimitInfo $rateLimitInfo -ControlDir $controlDir
                
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
                }
                'needs-input' {
                    Write-Status "Task paused for human input" -Type Warn
                    # Don't increment - task needs human before it can be used
                }
                'skipped' {
                    Write-Status "Task skipped during analysis" -Type Warn
                    $tasksAnalysed++  # Count as processed
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
        
        # Display result summary
        Write-Host ""
        if ($completionCheck.completed -and $completionCheck.status -eq 'analysed') {
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
                
                $signal = Test-ControlSignals -ControlDir $controlDir
                if ($signal -eq 'stop') {
                    Write-Host ""
                    Write-Status "Stop signal received during delay" -Type Error
                    Remove-Item (Join-Path $controlDir "stop.signal") -Force -ErrorAction SilentlyContinue
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
                        $currentSignal = Test-ControlSignals -ControlDir $controlDir
                        
                        if ($currentSignal -eq 'stop') {
                            Write-Host ""
                            Write-Status "Stop signal received while paused" -Type Error
                            Remove-Item (Join-Path $controlDir "stop.signal") -Force -ErrorAction SilentlyContinue
                            Remove-Item $pauseSignalPath -Force -ErrorAction SilentlyContinue
                            $script:shouldStop = $true
                            break
                        }
                        
                        if ($currentSignal -ne 'pause') {
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
        
        # Separator for next loop
        Write-Separator -Width 60
    }
    
} finally {
    # Clean up session
    Write-Header "Cleanup"
    Write-Status "Cleaning up analysis session..." -Type Process
    
    # Update status to stopped
    Invoke-SessionUpdate -Arguments @{ status = "stopped" } | Out-Null
    
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
