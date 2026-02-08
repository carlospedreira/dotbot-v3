<#
.SYNOPSIS
Task reset utilities for autonomous task management

.DESCRIPTION
Provides functions for resetting in-progress and skipped tasks back to todo status
#>

function Reset-InProgressTasks {
    <#
    .SYNOPSIS
    Reset all in-progress tasks to todo status
    
    .PARAMETER TasksBaseDir
    Base directory containing task subdirectories (todo, in-progress, done)
    
    .OUTPUTS
    Array of hashtables with reset task information
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$TasksBaseDir
    )
    
    $resetTasks = @()
    $inProgressDir = Join-Path $TasksBaseDir "in-progress"
    
    if (-not (Test-Path $inProgressDir)) {
        return $resetTasks
    }
    
    $inProgressTasks = Get-ChildItem -Path $inProgressDir -Filter "*.json" -File -ErrorAction SilentlyContinue
    
    if ($inProgressTasks.Count -eq 0) {
        return $resetTasks
    }
    
    foreach ($taskFile in $inProgressTasks) {
        try {
            $taskContent = Get-Content -Path $taskFile.FullName -Raw | ConvertFrom-Json
            $taskId = $taskContent.id
            $taskName = $taskContent.name
            
            # If task has analysis data, return to analysed; otherwise to todo
            $hasAnalysis = $taskContent.analysis -and $taskContent.analysis.PSObject.Properties.Count -gt 0
            if ($hasAnalysis) {
                $targetDir = Join-Path $TasksBaseDir "analysed"
                $targetStatus = "analysed"
            } else {
                $targetDir = Join-Path $TasksBaseDir "todo"
                $targetStatus = "todo"
            }

            # Ensure target directory exists
            if (-not (Test-Path $targetDir)) {
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            }

            $targetPath = Join-Path $targetDir $taskFile.Name

            # Update status
            $taskContent.status = $targetStatus
            $taskContent.started_at = $null
            $taskContent.updated_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

            # Write to target directory
            $taskContent | ConvertTo-Json -Depth 10 | Set-Content -Path $targetPath -Force
            
            # Remove from in-progress
            Remove-Item -Path $taskFile.FullName -Force
            
            $resetTasks += @{
                id = $taskId
                name = $taskName
                file = $taskFile.Name
            }
        } catch {
            Write-Warning "Error processing task: $($taskFile.Name) - $($_.Exception.Message)"
        }
    }
    
    return $resetTasks
}

function Reset-SkippedTasks {
    <#
    .SYNOPSIS
    Reset all skipped tasks to todo status
    
    .PARAMETER TasksBaseDir
    Base directory containing task subdirectories (todo, in-progress, skipped, done)
    
    .OUTPUTS
    Array of hashtables with reset task information
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$TasksBaseDir
    )
    
    $resetTasks = @()
    $skippedDir = Join-Path $TasksBaseDir "skipped"
    
    if (-not (Test-Path $skippedDir)) {
        return $resetTasks
    }
    
    $skippedTasks = Get-ChildItem -Path $skippedDir -Filter "*.json" -File -ErrorAction SilentlyContinue
    
    if ($skippedTasks.Count -eq 0) {
        return $resetTasks
    }
    
    foreach ($taskFile in $skippedTasks) {
        try {
            $taskContent = Get-Content -Path $taskFile.FullName -Raw | ConvertFrom-Json
            $taskId = $taskContent.id
            $taskName = $taskContent.name
            
            # Move to todo directory
            $todoDir = Join-Path $TasksBaseDir "todo"
            $todoPath = Join-Path $todoDir $taskFile.Name
            
            # Update status
            $taskContent.status = "todo"
            $taskContent.updated_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            
            # Preserve skip_history as audit trail
            # (don't clear it - this is intentional to maintain history for debugging)
            
            # Write to todo directory
            $taskContent | ConvertTo-Json -Depth 10 | Set-Content -Path $todoPath -Force
            
            # Remove from skipped
            Remove-Item -Path $taskFile.FullName -Force
            
            $resetTasks += @{
                id = $taskId
                name = $taskName
                file = $taskFile.Name
                skip_count = ($taskContent.skip_history | Measure-Object).Count
            }
        } catch {
            Write-Warning "Error processing skipped task: $($taskFile.Name) - $($_.Exception.Message)"
        }
    }
    
    return $resetTasks
}
