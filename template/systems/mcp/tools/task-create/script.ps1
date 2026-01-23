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
        created_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
        updated_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
        completed_at = $null
    }
    
    # Define file path
    $tasksDir = Join-Path $PSScriptRoot "..\..\..\..\state\tasks\todo"
    
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
