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

    Write-Verbose "[task-get-next] Using cached task index"

    $nextTask = Get-NextTask

    if (-not $nextTask) {
        Write-Verbose "[task-get-next] No eligible tasks found"
        return @{
            success = $true
            task = $null
            message = "No pending tasks available. All tasks are either complete, in-progress, or have unmet dependencies."
        }
    }

    Write-Verbose "[task-get-next] Selected task: $($nextTask.id) - $($nextTask.name) (Priority: $($nextTask.priority))"

    # Return the highest priority task
    if ($verbose) {
        $taskObj = @{
            id = $nextTask.id
            name = $nextTask.name
            status = 'todo'
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
        }
    } else {
        $taskObj = @{
            id = $nextTask.id
            name = $nextTask.name
            status = 'todo'
            priority = $nextTask.priority
            effort = $nextTask.effort
            category = $nextTask.category
        }
    }

    return @{
        success = $true
        task = $taskObj
        message = "Next task to work on: $($nextTask.name) (Priority: $($nextTask.priority), Effort: $($nextTask.effort))"
    }
}
