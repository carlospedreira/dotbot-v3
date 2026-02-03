# Script to analyze and optionally fix tasks with invalid dependencies
# Usage: pwsh -ExecutionPolicy Bypass -File task-fix-dependencies.ps1 [-Fix]

param(
    [switch]$Fix,
    [switch]$RemoveAll
)

# Import task index module
$indexModule = Join-Path $PSScriptRoot "..\modules\TaskIndexCache.psm1"
Import-Module $indexModule -Force

# Initialize task index
$tasksBaseDir = Join-Path $PSScriptRoot "..\..\..\workspace\tasks"
Initialize-TaskIndex -TasksBaseDir $tasksBaseDir

# Force index rebuild
$index = Get-TaskIndex

Write-Host "`n=== Task Dependency Analysis ===" -ForegroundColor Cyan
Write-Host "Total tasks: $($index.Todo.Count + $index.InProgress.Count + $index.Done.Count)"
Write-Host "  - Todo: $($index.Todo.Count)"
Write-Host "  - In Progress: $($index.InProgress.Count)"
Write-Host "  - Done: $($index.Done.Count)"
Write-Host ""

# Analyze dependencies
$tasksWithInvalidDeps = @()
$allTasks = @($index.Todo.Values) + @($index.InProgress.Values) + @($index.Done.Values)

foreach ($task in $index.Todo.Values) {
    if (-not $task.dependencies -or $task.dependencies.Count -eq 0) {
        continue
    }
    
    $invalidDeps = @()
    foreach ($dep in $task.dependencies) {
        $depLower = $dep.ToLower()
        $found = $false
        
        foreach ($t in $allTasks) {
            # Check ID match
            if ($t.id -eq $dep) { $found = $true; break }
            
            # Check name match
            if ($t.name -eq $dep) { $found = $true; break }
            
            # Check slug match
            $taskSlug = ($t.name -replace '[^\w\s-]', '' -replace '\s+', '-').ToLower()
            if ($taskSlug -eq $depLower) { $found = $true; break }
            
            # Fuzzy match
            if ($taskSlug -like "*$depLower*" -or $depLower -like "*$taskSlug*") { $found = $true; break }
        }
        
        if (-not $found) {
            $invalidDeps += $dep
        }
    }
    
    if ($invalidDeps.Count -gt 0) {
        $tasksWithInvalidDeps += [PSCustomObject]@{
            Id = $task.id
            Name = $task.name
            FilePath = $task.file_path
            AllDependencies = $task.dependencies
            InvalidDependencies = $invalidDeps
            ValidDependencies = @($task.dependencies | Where-Object { $_ -notin $invalidDeps })
        }
    }
}

if ($tasksWithInvalidDeps.Count -eq 0) {
    Write-Host "✓ No tasks with invalid dependencies found!" -ForegroundColor Green
    exit 0
}

Write-Host "⚠ Found $($tasksWithInvalidDeps.Count) tasks with invalid dependencies:" -ForegroundColor Yellow
Write-Host ""

foreach ($task in $tasksWithInvalidDeps) {
    Write-Host "Task: $($task.Name)" -ForegroundColor White
    Write-Host "  ID: $($task.Id.Substring(0,8))"
    Write-Host "  Invalid dependencies: $($task.InvalidDependencies -join ', ')" -ForegroundColor Red
    if ($task.ValidDependencies.Count -gt 0) {
        Write-Host "  Valid dependencies: $($task.ValidDependencies -join ', ')" -ForegroundColor Green
    }
    Write-Host ""
}

# Fix logic
if ($Fix -or $RemoveAll) {
    Write-Host "=== Fixing Tasks ===" -ForegroundColor Cyan
    Write-Host ""
    
    foreach ($task in $tasksWithInvalidDeps) {
        $taskData = Get-Content $task.FilePath | ConvertFrom-Json
        
        if ($RemoveAll) {
            # Remove all dependencies
            $taskData.dependencies = @()
            Write-Host "✓ Removed all dependencies from: $($task.Name)" -ForegroundColor Green
        } else {
            # Remove only invalid dependencies
            $taskData.dependencies = @($task.ValidDependencies)
            Write-Host "✓ Removed invalid dependencies from: $($task.Name)" -ForegroundColor Green
        }
        
        $taskData.updated_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
        $taskData | ConvertTo-Json -Depth 10 | Set-Content -Path $task.FilePath -Encoding UTF8
    }
    
    Write-Host ""
    Write-Host "✓ Fixed $($tasksWithInvalidDeps.Count) tasks" -ForegroundColor Green
    Write-Host ""
    Write-Host "Run 'mcp__dotbot__task_get_next' to get the next available task." -ForegroundColor Cyan
} else {
    Write-Host "=== How to Fix ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Option 1: Remove ALL dependencies from these tasks:" -ForegroundColor White
    Write-Host "  pwsh -ExecutionPolicy Bypass -File task-fix-dependencies.ps1 -RemoveAll" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Option 2: Remove only INVALID dependencies (keep valid ones):" -ForegroundColor White
    Write-Host "  pwsh -ExecutionPolicy Bypass -File task-fix-dependencies.ps1 -Fix" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Option 3: Manually create the missing dependency tasks first" -ForegroundColor White
    Write-Host ""
}
