function Invoke-TaskCreate {
    param(
        [hashtable]$Arguments
    )
    
    # Extract arguments
    $name = $Arguments['name']
    $description = $Arguments['description']
    $category = $Arguments['category']
    $priority = $Arguments['priority']
    $effort = $Arguments['effort']
    $dependencies = $Arguments['dependencies']
    $acceptanceCriteria = $Arguments['acceptance_criteria']
    $steps = $Arguments['steps']
    $applicableStandards = $Arguments['applicable_standards']
    $applicableAgents = $Arguments['applicable_agents']
    $needsInterview = $Arguments['needs_interview'] -eq $true
    
    # Validate required fields
    if (-not $name) {
        throw "Task name is required"
    }
    
    if (-not $description) {
        throw "Task description is required"
    }
    
    # Validate category
    $validCategories = @('core', 'feature', 'enhancement', 'bugfix', 'infrastructure', 'ui-ux')
    if ($category -and $category -notin $validCategories) {
        throw "Invalid category. Must be one of: $($validCategories -join ', ')"
    }
    
    # Validate effort
    $validEfforts = @('XS', 'S', 'M', 'L', 'XL')
    if ($effort -and $effort -notin $validEfforts) {
        throw "Invalid effort. Must be one of: $($validEfforts -join ', ')"
    }
    
    # Set defaults
    if (-not $category) { $category = 'feature' }
    if (-not $priority) { $priority = 50 }
    if (-not $effort) { $effort = 'M' }
    if (-not $dependencies) { $dependencies = @() }
    if (-not $acceptanceCriteria) { $acceptanceCriteria = @() }
    if (-not $steps) { $steps = @() }
    if (-not $applicableStandards) { $applicableStandards = @() }
    if (-not $applicableAgents) { $applicableAgents = @() }
    # needsInterview is already a boolean, no default needed
    
    # Validate dependencies exist
    if ($dependencies -and $dependencies.Count -gt 0) {
        # Import task index module
        $indexModule = Join-Path $PSScriptRoot "..\..\modules\TaskIndexCache.psm1"
        if (-not (Get-Module TaskIndexCache)) {
            Import-Module $indexModule -Force
        }
        
        # Initialize index
        $tasksBaseDir = Join-Path $PSScriptRoot "..\..\..\..\workspace\tasks"
        Initialize-TaskIndex -TasksBaseDir $tasksBaseDir
        $index = Get-TaskIndex
        
        $invalidDeps = @()
        foreach ($dep in $dependencies) {
            $depLower = $dep.ToLower()
            $found = $false
            
            # Check all tasks (todo, in-progress, done)
            $allTasks = @($index.Todo.Values) + @($index.InProgress.Values) + @($index.Done.Values)
            
            foreach ($task in $allTasks) {
                # Check ID match
                if ($task.id -eq $dep) { $found = $true; break }
                
                # Check name match
                if ($task.name -eq $dep) { $found = $true; break }
                
                # Check slug match (generated from name)
                $taskSlug = ($task.name -replace '[^\w\s-]', '' -replace '\s+', '-').ToLower()
                if ($taskSlug -eq $depLower) { $found = $true; break }
                
                # Fuzzy match
                if ($taskSlug -like "*$depLower*" -or $depLower -like "*$taskSlug*") { $found = $true; break }
            }
            
            if (-not $found) {
                $invalidDeps += $dep
            }
        }
        
        if ($invalidDeps.Count -gt 0) {
            $depList = $invalidDeps -join "', '"
            throw "Invalid dependencies: '$depList'. These tasks do not exist. Create dependency tasks first or remove these dependencies."
        }
    }
    
    # Generate unique ID
    $id = [System.Guid]::NewGuid().ToString()
    
    # Create task object
    $task = @{
        id = $id
        name = $name
        description = $description
        category = $category
        priority = [int]$priority
        effort = $effort
        status = 'todo'
        dependencies = $dependencies
        acceptance_criteria = $acceptanceCriteria
        steps = $steps
        applicable_standards = $applicableStandards
        applicable_agents = $applicableAgents
        needs_interview = $needsInterview
        created_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
        updated_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
        completed_at = $null
    }
    
    # Define file path
    $tasksDir = Join-Path $PSScriptRoot "..\..\..\..\workspace\tasks\todo"
    
    # Ensure directory exists
    if (-not (Test-Path $tasksDir)) {
        New-Item -ItemType Directory -Force -Path $tasksDir | Out-Null
    }
    
    # Create filename from name (sanitized)
    $fileName = ($name -replace '[^\w\s-]', '' -replace '\s+', '-').ToLower()
    if ($fileName.Length -gt 50) {
        $fileName = $fileName.Substring(0, 50)
    }
    $fileName = "$fileName-$($id.Split('-')[0]).json"
    $filePath = Join-Path $tasksDir $fileName
    
    # Save task to file
    $task | ConvertTo-Json -Depth 10 | Set-Content -Path $filePath -Encoding UTF8
    
    # Return result
    return @{
        success = $true
        task_id = $id
        file_path = $filePath
        message = "Task '$name' created successfully with ID: $id"
    }
}
