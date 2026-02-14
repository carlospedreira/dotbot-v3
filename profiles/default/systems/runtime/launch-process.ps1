<#
.SYNOPSIS
Unified process launcher replacing both loop scripts and ad-hoc Start-Job calls.

.DESCRIPTION
Every Claude invocation is a tracked process. Creates a process registry entry,
builds the appropriate prompt, invokes Claude, and manages the lifecycle.

.PARAMETER Type
Process type: analysis, execution, kickstart, planning, commit, task-creation

.PARAMETER TaskId
Optional: specific task ID (for analysis/execution types)

.PARAMETER Prompt
Optional: custom prompt text (for kickstart/planning/commit/task-creation)

.PARAMETER Continue
If set, continue to next task after completion (analysis/execution only)

.PARAMETER Model
Claude model to use (default: Opus)

.PARAMETER ShowDebug
Show raw JSON events

.PARAMETER ShowVerbose
Show detailed tool results

.PARAMETER MaxTasks
Max tasks to process with -Continue (0 = unlimited)

.PARAMETER Description
Human-readable description for UI display

.PARAMETER ProcessId
Optional: resume an existing process by ID (skips creation)
#>

param(
    [Parameter(Mandatory)]
    [ValidateSet('analysis', 'execution', 'kickstart', 'planning', 'commit', 'task-creation')]
    [string]$Type,

    [string]$TaskId,
    [string]$Prompt,
    [switch]$Continue,
    [ValidateSet('Opus', 'Sonnet', 'Haiku')]
    [string]$Model,
    [switch]$ShowDebug,
    [switch]$ShowVerbose,
    [int]$MaxTasks = 0,
    [string]$Description,
    [string]$ProcessId
)

# --- Configuration ---
$modelMap = @{
    'Opus'   = 'claude-opus-4-5-20251101'
    'Sonnet' = 'claude-sonnet-4-5-20250929'
    'Haiku'  = 'claude-haiku-4-5-20251001'
}

# Determine phase for activity logging
$phaseMap = @{
    'analysis'      = 'analysis'
    'execution'     = 'execution'
    'kickstart'     = 'execution'
    'planning'      = 'execution'
    'commit'        = 'execution'
    'task-creation' = 'execution'
}

$env:DOTBOT_CURRENT_PHASE = $phaseMap[$Type]

# Resolve paths
$botRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$controlDir = Join-Path $botRoot ".control"
$processesDir = Join-Path $controlDir "processes"
$projectRoot = Split-Path -Parent $botRoot

# Ensure directories exist
if (-not (Test-Path $processesDir)) {
    New-Item -Path $processesDir -ItemType Directory -Force | Out-Null
}

# Import modules
Import-Module "$PSScriptRoot\ClaudeCLI\ClaudeCLI.psm1" -Force
Import-Module "$PSScriptRoot\modules\DotBotTheme.psm1" -Force
$t = Get-DotBotTheme

. "$PSScriptRoot\modules\ui-rendering.ps1"
. "$PSScriptRoot\modules\prompt-builder.ps1"
. "$PSScriptRoot\modules\rate-limit-handler.ps1"

# Import task-based modules for analysis/execution types
if ($Type -in @('analysis', 'execution')) {
    Import-Module "$PSScriptRoot\..\mcp\modules\TaskIndexCache.psm1" -Force
    Import-Module "$PSScriptRoot\..\mcp\modules\SessionTracking.psm1" -Force
    . "$PSScriptRoot\modules\cleanup.ps1"
    . "$PSScriptRoot\modules\get-failure-reason.ps1"
    . "$PSScriptRoot\modules\test-task-completion.ps1"
    . "$PSScriptRoot\modules\create-problem-log.ps1"

    # MCP tool functions
    . "$PSScriptRoot\..\mcp\tools\session-initialize\script.ps1"
    . "$PSScriptRoot\..\mcp\tools\session-get-state\script.ps1"
    . "$PSScriptRoot\..\mcp\tools\session-get-stats\script.ps1"
    . "$PSScriptRoot\..\mcp\tools\session-update\script.ps1"
    . "$PSScriptRoot\..\mcp\tools\session-increment-completed\script.ps1"
    . "$PSScriptRoot\..\mcp\tools\task-get-next\script.ps1"
    . "$PSScriptRoot\..\mcp\tools\task-mark-in-progress\script.ps1"
    . "$PSScriptRoot\..\mcp\tools\task-mark-skipped\script.ps1"
}

if ($Type -eq 'analysis') {
    . "$PSScriptRoot\..\mcp\tools\task-mark-analysing\script.ps1"
}

# Load settings for model defaults
$settingsPath = Join-Path $botRoot "defaults\settings.default.json"
$settings = @{ execution = @{ model = 'Opus' }; analysis = @{ model = 'Opus' } }
if (Test-Path $settingsPath) {
    try { $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json } catch {}
}

# Resolve model (parameter > settings > default)
if (-not $Model) {
    $Model = switch ($Type) {
        'analysis' { if ($settings.analysis?.model) { $settings.analysis.model } else { 'Opus' } }
        default    { if ($settings.execution?.model) { $settings.execution.model } else { 'Opus' } }
    }
}

$claudeModelName = $modelMap[$Model]
$env:CLAUDE_MODEL = $claudeModelName

# --- Process Registry ---

function New-ProcessId {
    "proc-$([guid]::NewGuid().ToString().Substring(0,6))"
}

function Write-ProcessFile {
    param([string]$Id, [hashtable]$Data)
    $filePath = Join-Path $processesDir "$Id.json"
    $tempFile = "$filePath.tmp"
    $Data | ConvertTo-Json -Depth 10 | Set-Content -Path $tempFile -Encoding utf8NoBOM -NoNewline
    Move-Item -Path $tempFile -Destination $filePath -Force
}

function Read-ProcessFile {
    param([string]$Id)
    $filePath = Join-Path $processesDir "$Id.json"
    if (Test-Path $filePath) {
        try { Get-Content $filePath -Raw | ConvertFrom-Json } catch { $null }
    }
}

function Write-ProcessActivity {
    param([string]$Id, [string]$ActivityType, [string]$Message)
    $logPath = Join-Path $processesDir "$Id.activity.jsonl"
    $event = @{
        timestamp = (Get-Date).ToUniversalTime().ToString("o")
        type = $ActivityType
        message = $Message
        task_id = $env:DOTBOT_CURRENT_TASK_ID
        phase = $env:DOTBOT_CURRENT_PHASE
    } | ConvertTo-Json -Compress

    $maxRetries = 3
    for ($r = 0; $r -lt $maxRetries; $r++) {
        try {
            $fs = [System.IO.FileStream]::new($logPath, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
            $sw = [System.IO.StreamWriter]::new($fs, [System.Text.Encoding]::UTF8)
            $sw.WriteLine($event)
            $sw.Close()
            $fs.Close()
            break
        } catch {
            if ($r -lt ($maxRetries - 1)) { Start-Sleep -Milliseconds (50 * ($r + 1)) }
        }
    }

    # Also write to global activity.jsonl for oscilloscope backward compat
    try { Write-ActivityLog -Type $ActivityType -Message $Message } catch {}
}

function Test-ProcessStopSignal {
    param([string]$Id)
    $stopFile = Join-Path $processesDir "$Id.stop"
    Test-Path $stopFile
}

# --- Initialize Process ---
$procId = if ($ProcessId) { $ProcessId } else { New-ProcessId }
$sessionId = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH-mm-ssZ")
$claudeSessionId = [System.Guid]::NewGuid().ToString()

# Set process ID env var for dual-write activity logging in ClaudeCLI
$env:DOTBOT_PROCESS_ID = $procId

$processData = @{
    id              = $procId
    type            = $Type
    status          = 'starting'
    task_id         = $TaskId
    task_name       = $null
    continue        = [bool]$Continue
    model           = $Model
    pid             = $PID
    session_id      = $sessionId
    claude_session_id = $claudeSessionId
    started_at      = (Get-Date).ToUniversalTime().ToString("o")
    last_heartbeat  = (Get-Date).ToUniversalTime().ToString("o")
    heartbeat_status = "Starting $Type process"
    heartbeat_next_action = $null
    last_whisper_index = 0
    completed_at    = $null
    failed_at       = $null
    tasks_completed = 0
    error           = $null
    workflow        = $null
    description     = $Description
}

Write-ProcessFile -Id $procId -Data $processData

# Banner
Write-Card -Title "PROCESS: $($Type.ToUpper())" -Width 50 -BorderStyle Rounded -BorderColor Label -TitleColor Label -Lines @(
    "$($t.Label)ID:$($t.Reset)    $($t.Cyan)$procId$($t.Reset)"
    "$($t.Label)Model:$($t.Reset) $($t.Purple)$Model$($t.Reset)"
    "$($t.Label)Type:$($t.Reset)  $($t.Amber)$Type$($t.Reset)"
)

Write-ProcessActivity -Id $procId -ActivityType "text" -Message "Process $procId started ($Type)"

# --- Task-based types: analysis/execution ---
if ($Type -in @('analysis', 'execution')) {
    # Initialize session for execution type
    if ($Type -eq 'execution') {
        $sessionResult = Invoke-SessionInitialize -Arguments @{ session_type = "autonomous" }
        if ($sessionResult.success) {
            $sessionId = $sessionResult.session.session_id
        }
    }

    # Load prompt templates
    $templateFile = switch ($Type) {
        'analysis'  { Join-Path $botRoot "prompts\workflows\98-analyse-task.md" }
        'execution' { Join-Path $botRoot "prompts\workflows\99-autonomous-task.md" }
    }
    $promptTemplate = Get-Content $templateFile -Raw

    $processData.workflow = switch ($Type) {
        'analysis'  { "98-analyse-task.md" }
        'execution' { "99-autonomous-task.md" }
    }

    # Standards and product context (execution only)
    $standardsList = ""
    $productMission = ""
    $entityModel = ""
    if ($Type -eq 'execution') {
        $standardsDir = Join-Path $botRoot "prompts\standards\global"
        if (Test-Path $standardsDir) {
            $standardsFiles = Get-ChildItem -Path $standardsDir -Filter "*.md" -File |
                ForEach-Object { ".bot/prompts/standards/global/$($_.Name)" }
            $standardsList = if ($standardsFiles) { "- " + ($standardsFiles -join "`n- ") } else { "No standards files found." }
        }
        $productDir = Join-Path $botRoot "workspace\product"
        $productMission = if (Test-Path (Join-Path $productDir "mission.md")) { "Read the product mission and context from: .bot/workspace/product/mission.md" } else { "No product mission file found." }
        $entityModel = if (Test-Path (Join-Path $productDir "entity-model.md")) { "Read the entity model design from: .bot/workspace/product/entity-model.md" } else { "No entity model file found." }
    }

    # Task reset for analysis and execution
    . "$PSScriptRoot\modules\task-reset.ps1"
    $tasksBaseDir = Join-Path $botRoot "workspace\tasks"

    # Recover orphaned analysing tasks (both types benefit from this)
    Reset-AnalysingTasks -TasksBaseDir $tasksBaseDir -ProcessesDir $processesDir | Out-Null

    if ($Type -eq 'execution') {
        Reset-InProgressTasks -TasksBaseDir $tasksBaseDir | Out-Null
        Reset-SkippedTasks -TasksBaseDir $tasksBaseDir | Out-Null
    }

    # Initialize task index for analysis
    if ($Type -eq 'analysis') {
        Initialize-TaskIndex -TasksBaseDir $tasksBaseDir
    }

    $tasksProcessed = 0
    $maxRetriesPerTask = 2
    $consecutiveFailureThreshold = 3

    # Update process status to running
    $processData.status = 'running'
    Write-ProcessFile -Id $procId -Data $processData

    try {
        while ($true) {
            # Check max tasks
            if ($MaxTasks -gt 0 -and $tasksProcessed -ge $MaxTasks) {
                Write-Status "Reached maximum task limit ($MaxTasks)" -Type Warn
                break
            }

            # Check stop signal
            if (Test-ProcessStopSignal -Id $procId) {
                Write-Status "Stop signal received" -Type Error
                $processData.status = 'stopped'
                $processData.failed_at = (Get-Date).ToUniversalTime().ToString("o")
                Write-ProcessFile -Id $procId -Data $processData
                Write-ProcessActivity -Id $procId -ActivityType "text" -Message "Process stopped by user"
                break
            }

            # Get next task
            Write-Status "Fetching next task..." -Type Process
            if ($Type -eq 'analysis') {
                Reset-TaskIndex
                # For analysis: get todo tasks only
                $taskResult = Invoke-TaskGetNext -Arguments @{ prefer_analysed = $false; verbose = $true }
                # Only accept todo tasks for analysis
                if ($taskResult.task -and $taskResult.task.status -ne 'todo') {
                    $taskResult = @{ success = $true; task = $null; message = "No todo tasks for analysis" }
                }
            } else {
                # For execution: prefer analysed, then todo
                $taskResult = Invoke-TaskGetNext -Arguments @{ verbose = $true }
            }

            # Use specific task if provided
            if ($TaskId -and $tasksProcessed -eq 0) {
                # First iteration with specific TaskId - fetch that specific task
                # TaskId was provided, the task-get-next result may not match
                # We'll proceed with what we got from task-get-next, the prompt already has the task context
            }

            if (-not $taskResult.success) {
                Write-Status "Error fetching task: $($taskResult.message)" -Type Error
                break
            }

            if (-not $taskResult.task) {
                if ($Continue) {
                    Write-Status "No tasks available - waiting..." -Type Info
                    Write-ProcessActivity -Id $procId -ActivityType "text" -Message "Waiting for new tasks..."

                    # Wait loop for new tasks
                    $foundTask = $false
                    while ($true) {
                        Start-Sleep -Seconds 5
                        if (Test-ProcessStopSignal -Id $procId) { break }
                        Reset-TaskIndex
                        if ($Type -eq 'analysis') {
                            $taskResult = Invoke-TaskGetNext -Arguments @{ prefer_analysed = $false; verbose = $true }
                            if ($taskResult.task -and $taskResult.task.status -ne 'todo') { $taskResult = @{ success = $true; task = $null } }
                        } else {
                            $taskResult = Invoke-TaskGetNext -Arguments @{ verbose = $true }
                        }
                        if ($taskResult.task) { $foundTask = $true; break }
                    }
                    if (-not $foundTask) { break }
                } else {
                    Write-Status "No tasks available" -Type Info
                    break
                }
            }

            $task = $taskResult.task
            $processData.task_id = $task.id
            $processData.task_name = $task.name
            $processData.heartbeat_status = "Working on: $($task.name)"
            Write-ProcessFile -Id $procId -Data $processData

            $env:DOTBOT_CURRENT_TASK_ID = $task.id
            Write-Status "Task: $($task.name)" -Type Success
            Write-ProcessActivity -Id $procId -ActivityType "text" -Message "Started task: $($task.name)"

            # Mark task status
            if ($Type -eq 'execution') {
                Invoke-TaskMarkInProgress -Arguments @{ task_id = $task.id } | Out-Null
                Invoke-SessionUpdate -Arguments @{ current_task_id = $task.id } | Out-Null
            }

            # Generate new Claude session ID per task
            $claudeSessionId = [System.Guid]::NewGuid().ToString()
            $env:CLAUDE_SESSION_ID = $claudeSessionId
            $processData.claude_session_id = $claudeSessionId
            Write-ProcessFile -Id $procId -Data $processData

            # Build prompt
            if ($Type -eq 'execution') {
                $prompt = Build-TaskPrompt `
                    -PromptTemplate $promptTemplate `
                    -Task $task `
                    -SessionId $sessionId `
                    -ProductMission $productMission `
                    -EntityModel $entityModel `
                    -StandardsList $standardsList

                $fullPrompt = @"
$prompt

## Process Context

- **Process ID:** $procId
- **Instance Type:** execution

Use the Process ID when calling `steering_heartbeat` (pass it as `process_id`). Also pass `instance_type: "execution"` for backward compatibility.

## Completion Goal

Task $($task.id) is complete: all acceptance criteria met, verification passed, and task marked done.

Work on this task autonomously. When complete, ensure you call task_mark_done via MCP.
"@
            } else {
                # Analysis prompt
                $prompt = $promptTemplate
                $prompt = $prompt -replace '\{\{SESSION_ID\}\}', $sessionId
                $prompt = $prompt -replace '\{\{TASK_ID\}\}', $task.id
                $prompt = $prompt -replace '\{\{TASK_NAME\}\}', $task.name
                $prompt = $prompt -replace '\{\{TASK_CATEGORY\}\}', $task.category
                $prompt = $prompt -replace '\{\{TASK_PRIORITY\}\}', $task.priority
                $prompt = $prompt -replace '\{\{TASK_EFFORT\}\}', $task.effort
                $prompt = $prompt -replace '\{\{TASK_DESCRIPTION\}\}', $task.description
                $needsInterview = if ($task.needs_interview) { 'true' } else { 'false' }
                $prompt = $prompt -replace '\{\{NEEDS_INTERVIEW\}\}', $needsInterview
                $acceptanceCriteria = if ($task.acceptance_criteria) { ($task.acceptance_criteria | ForEach-Object { "- $_" }) -join "`n" } else { "No specific acceptance criteria defined." }
                $prompt = $prompt -replace '\{\{ACCEPTANCE_CRITERIA\}\}', $acceptanceCriteria
                $steps = if ($task.steps) { ($task.steps | ForEach-Object { "- $_" }) -join "`n" } else { "No specific steps defined." }
                $prompt = $prompt -replace '\{\{TASK_STEPS\}\}', $steps

                $fullPrompt = @"
$prompt

## Process Context

- **Process ID:** $procId
- **Instance Type:** analysis

Use the Process ID when calling `steering_heartbeat` (pass it as `process_id`). Also pass `instance_type: "analysis"` for backward compatibility.

## Completion Goal

Analyse task $($task.id) completely. When analysis is finished:
- If all context is gathered: Call task_mark_analysed with the full analysis object
- If you need human input: Call task_mark_needs_input with a question or split_proposal
- If blocked by issues: Call task_mark_skipped with a reason

Do NOT implement the task. Your job is research and preparation only.
"@
            }

            # Invoke Claude with retries
            $attemptNumber = 0
            $taskSuccess = $false

            while ($attemptNumber -le $maxRetriesPerTask) {
                $attemptNumber++

                if ($attemptNumber -gt 1) {
                    Write-Status "Retry attempt $attemptNumber of $maxRetriesPerTask" -Type Warn
                }

                # Check stop signal before each attempt
                if (Test-ProcessStopSignal -Id $procId) {
                    $processData.status = 'stopped'
                    $processData.failed_at = (Get-Date).ToUniversalTime().ToString("o")
                    Write-ProcessFile -Id $procId -Data $processData
                    break
                }

                Write-Header "Claude Session"
                try {
                    $streamArgs = @{
                        Prompt = $fullPrompt
                        Model = $claudeModelName
                        SessionId = $claudeSessionId
                        PersistSession = $false
                    }
                    if ($ShowDebug) { $streamArgs['ShowDebugJson'] = $true }
                    if ($ShowVerbose) { $streamArgs['ShowVerbose'] = $true }

                    Invoke-ClaudeStream @streamArgs
                    $exitCode = 0
                } catch {
                    Write-Status "Error: $($_.Exception.Message)" -Type Error
                    $exitCode = 1
                }

                # Update heartbeat
                $processData.last_heartbeat = (Get-Date).ToUniversalTime().ToString("o")
                Write-ProcessFile -Id $procId -Data $processData

                # Check rate limit
                $rateLimitMsg = Get-LastRateLimitInfo
                if ($rateLimitMsg) {
                    Write-Status "Rate limit detected!" -Type Warn
                    $rateLimitInfo = Get-RateLimitResetTime -Message $rateLimitMsg
                    if ($rateLimitInfo) {
                        $processData.heartbeat_status = "Rate limited - waiting..."
                        Write-ProcessFile -Id $procId -Data $processData
                        Write-ProcessActivity -Id $procId -ActivityType "rate_limit" -Message $rateLimitMsg

                        # Simple wait - check stop signal periodically
                        $waitSeconds = $rateLimitInfo.wait_seconds
                        if (-not $waitSeconds -or $waitSeconds -lt 30) { $waitSeconds = 60 }
                        for ($w = 0; $w -lt $waitSeconds; $w++) {
                            Start-Sleep -Seconds 1
                            if (Test-ProcessStopSignal -Id $procId) { break }
                        }

                        $attemptNumber--  # Don't count rate limit as attempt
                        continue
                    }
                }

                # Check completion
                if ($Type -eq 'execution') {
                    $completionCheck = Test-TaskCompletion -TaskId $task.id
                    if ($completionCheck.completed) {
                        Write-Status "Task completed!" -Type Complete
                        Invoke-SessionIncrementCompleted -Arguments @{} | Out-Null
                        $taskSuccess = $true
                        break
                    }
                } else {
                    # Analysis: check if task moved to analysed/needs-input/skipped
                    $taskDirs = @('analysed', 'needs-input', 'skipped', 'in-progress', 'done')
                    $taskFound = $false
                    foreach ($dir in $taskDirs) {
                        $checkDir = Join-Path $botRoot "workspace\tasks\$dir"
                        if (Test-Path $checkDir) {
                            $files = Get-ChildItem -Path $checkDir -Filter "*.json" -File
                            foreach ($f in $files) {
                                try {
                                    $content = Get-Content -Path $f.FullName -Raw | ConvertFrom-Json
                                    if ($content.id -eq $task.id) {
                                        $taskFound = $true
                                        $taskSuccess = $true
                                        Write-Status "Analysis complete (status: $dir)" -Type Complete
                                        break
                                    }
                                } catch {}
                            }
                            if ($taskFound) { break }
                        }
                    }
                    if ($taskSuccess) { break }
                }

                # Task not completed - handle failure
                if ($Type -eq 'execution') {
                    $failureReason = Get-FailureReason -ExitCode $exitCode -Stdout "" -Stderr "" -TimedOut $false
                    if (-not $failureReason.recoverable) {
                        Write-Status "Non-recoverable failure - skipping" -Type Error
                        try {
                            Invoke-TaskMarkSkipped -Arguments @{ task_id = $task.id; skip_reason = "non-recoverable" } | Out-Null
                        } catch {}
                        break
                    }
                }

                if ($attemptNumber -ge $maxRetriesPerTask) {
                    Write-Status "Max retries exhausted" -Type Error
                    if ($Type -eq 'execution') {
                        try {
                            Invoke-TaskMarkSkipped -Arguments @{ task_id = $task.id; skip_reason = "max-retries" } | Out-Null
                        } catch {}
                    }
                    break
                }
            }

            # Update process data
            $env:DOTBOT_CURRENT_TASK_ID = $null
            $env:CLAUDE_SESSION_ID = $null

            if ($taskSuccess) {
                $tasksProcessed++
                $processData.tasks_completed = $tasksProcessed
                $processData.heartbeat_status = "Completed: $($task.name)"
                Write-ProcessFile -Id $procId -Data $processData
                Write-ProcessActivity -Id $procId -ActivityType "text" -Message "Task completed: $($task.name)"

                # Clean up Claude session
                try { Remove-ClaudeSession -SessionId $claudeSessionId -ProjectRoot $projectRoot | Out-Null } catch {}
            } else {
                Write-ProcessActivity -Id $procId -ActivityType "text" -Message "Task failed: $($task.name)"

                # Update session failure counters (execution only)
                if ($Type -eq 'execution') {
                    try {
                        $state = Invoke-SessionGetState -Arguments @{}
                        $newFailures = $state.state.consecutive_failures + 1
                        Invoke-SessionUpdate -Arguments @{
                            consecutive_failures = $newFailures
                            tasks_skipped = $state.state.tasks_skipped + 1
                        } | Out-Null

                        if ($newFailures -ge $consecutiveFailureThreshold) {
                            Write-Status "$consecutiveFailureThreshold consecutive failures - stopping" -Type Error
                            break
                        }
                    } catch {}
                }
            }

            # Continue to next task?
            if (-not $Continue) { break }

            # Clear task ID for next iteration
            $TaskId = $null
            $processData.task_id = $null
            $processData.task_name = $null

            # Delay between tasks
            Write-Phosphor "Waiting 3s before next task..." -Color Bezel
            for ($i = 0; $i -lt 3; $i++) {
                Start-Sleep -Seconds 1
                if (Test-ProcessStopSignal -Id $procId) { break }
            }

            if (Test-ProcessStopSignal -Id $procId) {
                $processData.status = 'stopped'
                $processData.failed_at = (Get-Date).ToUniversalTime().ToString("o")
                Write-ProcessFile -Id $procId -Data $processData
                break
            }
        }
    } finally {
        # Final cleanup
        if ($processData.status -eq 'running') {
            $processData.status = 'completed'
            $processData.completed_at = (Get-Date).ToUniversalTime().ToString("o")
        }
        Write-ProcessFile -Id $procId -Data $processData
        Write-ProcessActivity -Id $procId -ActivityType "text" -Message "Process $procId finished ($($processData.status))"

        if ($Type -eq 'execution') {
            try { Invoke-SessionUpdate -Arguments @{ status = "stopped" } | Out-Null } catch {}
        }
    }
}

# --- Prompt-based types: kickstart, planning, commit, task-creation ---
elseif ($Type -in @('kickstart', 'planning', 'commit', 'task-creation')) {
    # Determine workflow template
    $workflowFile = switch ($Type) {
        'kickstart'     { Join-Path $botRoot "prompts\workflows\01-plan-product.md" }
        'planning'      { Join-Path $botRoot "prompts\workflows\03-plan-roadmap.md" }
        'commit'        { Join-Path $botRoot "prompts\workflows\02-commit-and-push.md" }
        'task-creation' { Join-Path $botRoot "prompts\workflows\04-new-tasks.md" }
    }

    $processData.workflow = switch ($Type) {
        'kickstart'     { "01-plan-product.md" }
        'planning'      { "03-plan-roadmap.md" }
        'commit'        { "02-commit-and-push.md" }
        'task-creation' { "04-new-tasks.md" }
    }

    # Build prompt
    $systemPrompt = ""
    if (Test-Path $workflowFile) {
        $systemPrompt = Get-Content $workflowFile -Raw
    }

    # For prompt-based types, append the custom prompt
    if ($Prompt) {
        $fullPrompt = @"
$systemPrompt

## Additional Context

$Prompt
"@
    } else {
        $fullPrompt = $systemPrompt
    }

    if (-not $Description) {
        $Description = switch ($Type) {
            'kickstart'     { "Kickstart project setup" }
            'planning'      { "Plan roadmap" }
            'commit'        { "Commit and push changes" }
            'task-creation' { "Create new tasks" }
        }
    }

    $processData.status = 'running'
    $processData.description = $Description
    $processData.heartbeat_status = $Description
    Write-ProcessFile -Id $procId -Data $processData
    Write-ProcessActivity -Id $procId -ActivityType "text" -Message "$Description started"

    try {
        $streamArgs = @{
            Prompt = $fullPrompt
            Model = $claudeModelName
            SessionId = $claudeSessionId
            PersistSession = $false
        }
        if ($ShowDebug) { $streamArgs['ShowDebugJson'] = $true }
        if ($ShowVerbose) { $streamArgs['ShowVerbose'] = $true }

        Invoke-ClaudeStream @streamArgs

        $processData.status = 'completed'
        $processData.completed_at = (Get-Date).ToUniversalTime().ToString("o")
        $processData.heartbeat_status = "Completed: $Description"
    } catch {
        $processData.status = 'failed'
        $processData.failed_at = (Get-Date).ToUniversalTime().ToString("o")
        $processData.error = $_.Exception.Message
        $processData.heartbeat_status = "Failed: $($_.Exception.Message)"
        Write-Status "Process failed: $($_.Exception.Message)" -Type Error
    }

    Write-ProcessFile -Id $procId -Data $processData
    Write-ProcessActivity -Id $procId -ActivityType "text" -Message "Process $procId finished ($($processData.status))"
}

# Cleanup env vars
$env:DOTBOT_PROCESS_ID = $null
$env:DOTBOT_CURRENT_TASK_ID = $null
$env:DOTBOT_CURRENT_PHASE = $null

# Output process ID for caller to use
Write-Host ""
Write-Status "Process $procId finished with status: $($processData.status)" -Type Info

# Return process ID on stdout for programmatic consumption
Write-Output $procId
