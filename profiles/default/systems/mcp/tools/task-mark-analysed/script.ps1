function Invoke-TaskMarkAnalysed {
    param(
        [hashtable]$Arguments
    )
    
    # Extract arguments
    $taskId = $Arguments['task_id']
    $analysis = $Arguments['analysis']
    
    # Validate required fields
    if (-not $taskId) {
        throw "Task ID is required"
    }
    
    if (-not $analysis) {
        throw "Analysis data is required"
    }
    
    # Define tasks directories
    $tasksBaseDir = Join-Path $PSScriptRoot "..\..\..\..\workspace\tasks"
    $analysingDir = Join-Path $tasksBaseDir "analysing"
    $needsInputDir = Join-Path $tasksBaseDir "needs-input"
    $analysedDir = Join-Path $tasksBaseDir "analysed"
    
    # Find the task file (can be in analysing or needs-input)
    $taskFile = $null
    $currentStatus = $null
    
    foreach ($searchDir in @($analysingDir, $needsInputDir)) {
        if (Test-Path $searchDir) {
            $files = Get-ChildItem -Path $searchDir -Filter "*.json" -File
            foreach ($file in $files) {
                try {
                    $content = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json
                    if ($content.id -eq $taskId) {
                        $taskFile = $file
                        $currentStatus = if ($searchDir -eq $analysingDir) { 'analysing' } else { 'needs-input' }
                        break
                    }
                } catch {
                    # Continue searching
                }
            }
            if ($taskFile) { break }
        }
    }
    
    if (-not $taskFile) {
        throw "Task with ID '$taskId' not found in analysing or needs-input status"
    }
    
    # Read task content
    $taskContent = Get-Content -Path $taskFile.FullName -Raw | ConvertFrom-Json
    
    # Update task properties
    $taskContent.status = 'analysed'
    $taskContent.updated_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
    
    # Add analysis_completed_at timestamp
    if (-not $taskContent.PSObject.Properties['analysis_completed_at']) {
        $taskContent | Add-Member -NotePropertyName 'analysis_completed_at' -NotePropertyValue $null -Force
    }
    $taskContent.analysis_completed_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
    
    # Add analysed_by field
    if (-not $taskContent.PSObject.Properties['analysed_by']) {
        $taskContent | Add-Member -NotePropertyName 'analysed_by' -NotePropertyValue $null -Force
    }
    $taskContent.analysed_by = $env:CLAUDE_MODEL
    if (-not $taskContent.analysed_by) {
        $taskContent.analysed_by = 'unknown'
    }
    
    # Store analysis data
    if (-not $taskContent.PSObject.Properties['analysis']) {
        $taskContent | Add-Member -NotePropertyName 'analysis' -NotePropertyValue $null -Force
    }
    
    # Add analysed_at to the analysis object
    $analysisWithTimestamp = $analysis.Clone()
    $analysisWithTimestamp['analysed_at'] = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
    $analysisWithTimestamp['analysed_by'] = $taskContent.analysed_by
    
    $taskContent.analysis = $analysisWithTimestamp
    
    # Clear any pending questions (they should have been resolved)
    if ($taskContent.PSObject.Properties['pending_question']) {
        $taskContent.pending_question = $null
    }
    
    # Ensure analysed directory exists
    if (-not (Test-Path $analysedDir)) {
        New-Item -ItemType Directory -Force -Path $analysedDir | Out-Null
    }
    
    # Move file to analysed directory
    $newFilePath = Join-Path $analysedDir $taskFile.Name
    
    # Save updated task to new location
    $taskContent | ConvertTo-Json -Depth 20 | Set-Content -Path $newFilePath -Encoding UTF8
    Remove-Item -Path $taskFile.FullName -Force
    
    # Return result
    return @{
        success = $true
        message = "Task marked as analysed and ready for implementation"
        task_id = $taskId
        task_name = $taskContent.name
        old_status = $currentStatus
        new_status = 'analysed'
        analysis_completed_at = $taskContent.analysis_completed_at
        file_path = $newFilePath
    }
}
