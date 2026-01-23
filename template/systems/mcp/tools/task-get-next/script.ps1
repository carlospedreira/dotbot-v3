# Import task index module
$indexModule = Join-Path $PSScriptRoot "..\..\modules\TaskIndexCache.psm1"
if (-not (Get-Module TaskIndexCache)) {
    Import-Module $indexModule -Force
}

# Initialize index on first use
$tasksBaseDir = Join-Path $PSScriptRoot "..\..\..\..\state\tasks"
Initialize-TaskIndex -TasksBaseDir $tasksBaseDir

function Invoke-TaskGetNext {
    param(
        [hashtable]$Arguments
    )

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
    return @{
        success = $true
        task = @{
            id = $nextTask.id
            name = $nextTask.name
            description = $nextTask.description
            category = $nextTask.category
            priority = $nextTask.priority
            effort = $nextTask.effort
            dependencies = $nextTask.dependencies
            acceptance_criteria = $nextTask.acceptance_criteria
            steps = $nextTask.steps
            applicable_agents = $nextTask.applicable_agents
            applicable_standards = $nextTask.applicable_standards
            file_path = $nextTask.file_path
        }
        message = "Next task to work on: $($nextTask.name) (Priority: $($nextTask.priority), Effort: $($nextTask.effort))"
    }
}
