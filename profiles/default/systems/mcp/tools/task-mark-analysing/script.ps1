function Invoke-TaskMarkAnalysing {
    param(
        [hashtable]$Arguments
    )
    
    # Extract arguments
    $taskId = $Arguments['task_id']
    
    # Validate required fields
    if (-not $taskId) {
        throw "Task ID is required"
    }
    
    # Define tasks directories
    $tasksBaseDir = Join-Path $PSScriptRoot "..\..\..\..\workspace\tasks"
    $todoDir = Join-Path $tasksBaseDir "todo"
    $analysingDir = Join-Path $tasksBaseDir "analysing"
    
    # Find the task file in todo
    $taskFile = $null
    if (Test-Path $todoDir) {
        $files = Get-ChildItem -Path $todoDir -Filter "*.json" -File
        foreach ($file in $files) {
            try {
                $content = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json
                if ($content.id -eq $taskId) {
                    $taskFile = $file
                    break
                }
            } catch {
                # Continue searching
            }
        }
    }
    
    if (-not $taskFile) {
        throw "Task with ID '$taskId' not found in todo status"
    }
    
    # Read task content
    $taskContent = Get-Content -Path $taskFile.FullName -Raw | ConvertFrom-Json
    
    # Update task properties
    $taskContent.status = 'analysing'
    $taskContent.updated_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
    
    # Add analysis_started_at timestamp
    if (-not $taskContent.PSObject.Properties['analysis_started_at']) {
        $taskContent | Add-Member -NotePropertyName 'analysis_started_at' -NotePropertyValue $null -Force
    }
    $taskContent.analysis_started_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
    
    # Ensure analysing directory exists
    if (-not (Test-Path $analysingDir)) {
        New-Item -ItemType Directory -Force -Path $analysingDir | Out-Null
    }
    
    # Move file to analysing directory
    $newFilePath = Join-Path $analysingDir $taskFile.Name
    
    # Save updated task to new location
    $taskContent | ConvertTo-Json -Depth 10 | Set-Content -Path $newFilePath -Encoding UTF8
    Remove-Item -Path $taskFile.FullName -Force
    
    # Return result
    return @{
        success = $true
        message = "Task marked as analysing"
        task_id = $taskId
        task_name = $taskContent.name
        old_status = 'todo'
        new_status = 'analysing'
        analysis_started_at = $taskContent.analysis_started_at
        file_path = $newFilePath
    }
}
