function Invoke-TaskCreateBulk {
    param(
        [hashtable]$Arguments
    )
    
    # Extract arguments
    $tasks = $Arguments['tasks']
    
    # Validate required fields
    if (-not $tasks) {
        throw "Tasks array is required"
    }
    
    if ($tasks.Count -eq 0) {
        throw "At least one task must be provided"
    }
    
    # Validate categories and efforts
    $validCategories = @('core', 'feature', 'enhancement', 'bugfix', 'infrastructure', 'ui-ux')
    $validEfforts = @('XS', 'S', 'M', 'L', 'XL')
    
    # Define tasks directory
    $tasksDir = Join-Path $PSScriptRoot "..\..\..\..\state\tasks\todo"
    
    # Ensure directory exists
    if (-not (Test-Path $tasksDir)) {
        New-Item -ItemType Directory -Force -Path $tasksDir | Out-Null
    }
    
    # Process each task
    $createdTasks = @()
    $errors = @()
    $basePriority = 1
    
    for ($i = 0; $i -lt $tasks.Count; $i++) {
        $task = $tasks[$i]
        
        try {
            # Validate required fields for this task
            if (-not $task.name) {
                throw "Task #$($i+1): name is required"
            }
            
            if (-not $task.description) {
                throw "Task #$($i+1): description is required"
            }
            
            # Validate category if provided
            if ($task.category -and $task.category -notin $validCategories) {
                throw "Task #$($i+1): Invalid category. Must be one of: $($validCategories -join ', ')"
            }
            
            # Validate effort if provided
            if ($task.effort -and $task.effort -notin $validEfforts) {
                throw "Task #$($i+1): Invalid effort. Must be one of: $($validEfforts -join ', ')"
            }
            
            # Set defaults
            $category = if ($task.category) { $task.category } else { 'feature' }
            $priority = if ($task.priority) { [int]$task.priority } else { $basePriority + $i }
            $effort = if ($task.effort) { $task.effort } else { 'M' }
            $dependencies = if ($task.dependencies) { $task.dependencies } else { @() }
            $acceptanceCriteria = if ($task.acceptance_criteria) { $task.acceptance_criteria } else { @() }
            $steps = if ($task.steps) { $task.steps } else { @() }
            $applicableStandards = if ($task.applicable_standards) { $task.applicable_standards } else { @() }
            $applicableAgents = if ($task.applicable_agents) { $task.applicable_agents } else { @() }
            
            # Generate unique ID
            $id = [System.Guid]::NewGuid().ToString()
            
            # Create task object
            $newTask = @{
                id = $id
                name = $task.name
                description = $task.description
                category = $category
                priority = $priority
                effort = $effort
                status = 'todo'
                dependencies = $dependencies
                acceptance_criteria = $acceptanceCriteria
                steps = $steps
                applicable_standards = $applicableStandards
                applicable_agents = $applicableAgents
                created_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
                updated_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
                completed_at = $null
            }
            
            # Create filename from name (sanitized)
            $fileName = ($task.name -replace '[^\w\s-]', '' -replace '\s+', '-').ToLower()
            if ($fileName.Length -gt 50) {
                $fileName = $fileName.Substring(0, 50)
            }
            $fileName = "$fileName-$($id.Split('-')[0]).json"
            $filePath = Join-Path $tasksDir $fileName
            
            # Save task to file
            $newTask | ConvertTo-Json -Depth 10 | Set-Content -Path $filePath -Encoding UTF8
            
            # Add to created list
            $createdTasks += @{
                id = $id
                name = $task.name
                file_path = $filePath
                priority = $priority
            }
            
        } catch {
            $errors += @{
                index = $i
                name = $task.name
                error = $_.Exception.Message
            }
        }
    }
    
    # Return result
    return @{
        success = ($errors.Count -eq 0)
        created_count = $createdTasks.Count
        error_count = $errors.Count
        created_tasks = $createdTasks
        errors = $errors
        message = if ($errors.Count -eq 0) {
            "Successfully created $($createdTasks.Count) tasks"
        } else {
            "Created $($createdTasks.Count) tasks with $($errors.Count) errors"
        }
    }
}
