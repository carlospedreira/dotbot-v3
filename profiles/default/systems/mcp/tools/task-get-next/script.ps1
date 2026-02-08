# Import task index module
$indexModule = Join-Path $PSScriptRoot "..\..\modules\TaskIndexCache.psm1"
if (-not (Get-Module TaskIndexCache)) {
    Import-Module $indexModule -Force
}

# Initialize index on first use
$tasksBaseDir = Join-Path $PSScriptRoot "..\..\..\..\workspace\tasks"
Initialize-TaskIndex -TasksBaseDir $tasksBaseDir

function Invoke-TaskGetNext {
    param(
        [hashtable]$Arguments
    )

    $verbose = $Arguments['verbose'] -eq $true
    $preferAnalysed = $Arguments['prefer_analysed']
    
    # Default to preferring analysed tasks (can be overridden)
    if ($null -eq $preferAnalysed) {
        $preferAnalysed = $true
    }

    Write-Verbose "[task-get-next] Using cached task index (prefer_analysed: $preferAnalysed)"

    $index = Get-TaskIndex
    $nextTask = $null
    $taskStatus = 'todo'
    
    # Priority order:
    # 1. Analysed tasks (ready for implementation, already pre-processed)
    # 2. Todo tasks (need analysis first, or legacy mode)
    
    if ($preferAnalysed) {
        # Check for analysed tasks first
        $analysedTasks = @($index.Analysed.Values) | Sort-Object priority
        if ($analysedTasks.Count -gt 0) {
            $nextTask = $analysedTasks | Select-Object -First 1
            $taskStatus = 'analysed'
            Write-Verbose "[task-get-next] Found analysed task: $($nextTask.id)"
        }
    }
    
    # Only fall back to todo tasks when not preferring analysed
    if (-not $nextTask -and -not $preferAnalysed) {
        $nextTask = Get-NextTask
        $taskStatus = 'todo'
    }

    if (-not $nextTask) {
        # Check if there are tasks in other states that might explain why nothing is available
        $analysingCount = $index.Analysing.Count
        $needsInputCount = $index.NeedsInput.Count
        
        $statusMessage = "No pending tasks available."
        if ($analysingCount -gt 0) {
            $statusMessage += " $analysingCount task(s) being analysed."
        }
        if ($needsInputCount -gt 0) {
            $statusMessage += " $needsInputCount task(s) waiting for input."
        }
        
        Write-Verbose "[task-get-next] No eligible tasks found"
        return @{
            success = $true
            task = $null
            message = $statusMessage
            analysing_count = $analysingCount
            needs_input_count = $needsInputCount
        }
    }

    Write-Verbose "[task-get-next] Selected task: $($nextTask.id) - $($nextTask.name) (Priority: $($nextTask.priority), Status: $taskStatus)"

    # Return the highest priority task
    if ($verbose) {
        $taskObj = @{
            id = $nextTask.id
            name = $nextTask.name
            status = $taskStatus
            priority = $nextTask.priority
            effort = $nextTask.effort
            category = $nextTask.category
            description = $nextTask.description
            dependencies = $nextTask.dependencies
            acceptance_criteria = $nextTask.acceptance_criteria
            steps = $nextTask.steps
            applicable_agents = $nextTask.applicable_agents
            applicable_standards = $nextTask.applicable_standards
            file_path = $nextTask.file_path
            needs_interview = $nextTask.needs_interview
        }
    } else {
        $taskObj = @{
            id = $nextTask.id
            name = $nextTask.name
            status = $taskStatus
            priority = $nextTask.priority
            effort = $nextTask.effort
            category = $nextTask.category
        }
    }

    $sourceLabel = if ($taskStatus -eq 'analysed') { 'analysed (ready)' } else { 'todo (needs analysis)' }
    
    return @{
        success = $true
        task = $taskObj
        message = "Next task to work on: $($nextTask.name) (Priority: $($nextTask.priority), Effort: $($nextTask.effort), Source: $sourceLabel)"
    }
}
