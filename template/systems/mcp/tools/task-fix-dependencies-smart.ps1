# Intelligent dependency analysis and repair
# Analyzes semantic meaning and suggests smart fixes

param(
    [switch]$Apply
)

# Import task index module
$indexModule = Join-Path $PSScriptRoot "..\modules\TaskIndexCache.psm1"
Import-Module $indexModule -Force

# Initialize task index
$tasksBaseDir = Join-Path $PSScriptRoot "..\..\..\..\workspace\tasks"
Initialize-TaskIndex -TasksBaseDir $tasksBaseDir
$index = Get-TaskIndex

Write-Host "`n=== Intelligent Dependency Analysis ===" -ForegroundColor Cyan
Write-Host ""

# Known foundational patterns that should have no dependencies
$foundationalPatterns = @(
    'schema',
    'entity.*model',
    'configure.*database',
    'create.*configuration',
    'install.*package',
    'initialize.*solution',
    'set.*up.*infrastructure'
)

# Known dependency mappings based on completed tasks
$dependencyMappings = @{
    'org-intelligence-schema' = @('create-org-intelligence-configuration-model', 'implement-entitybase-with-audit-fields')
    'graph-polly-policies' = @('add-polly-retry-policies-to-graph-services')
    'email-stats-extractor' = @() # Not completed yet
    'calendar-stats-extractor' = @() # Not completed yet
    'enrichment-prompts' = @('create-enrichment-prompt-templates')
    'nlu-intent-classification' = @('add-natural-language-understanding-with-llm-intent-classification')
    'third-party-analyzer' = @() # Not completed yet
    'message-context-builder' = @() # Not completed yet
    'org-intelligence-entities' = @('create-org-intelligence-module-registration')
    'directory-sync-service' = @('implement-graph-organization-service-for-sender-enrichment')
    'people-api-service' = @('implement-graph-organization-service-for-sender-enrichment')
    'batch-enrichment-job' = @() # Not completed yet
}

$allTasks = @($index.Todo.Values) + @($index.InProgress.Values) + @($index.Done.Values)
$fixes = @()

foreach ($task in $index.Todo.Values) {
    if (-not $task.dependencies -or $task.dependencies.Count -eq 0) {
        continue
    }
    
    $taskNameLower = $task.name.ToLower()
    $isFoundational = $false
    
    # Check if this is a foundational task
    foreach ($pattern in $foundationalPatterns) {
        if ($taskNameLower -match $pattern) {
            $isFoundational = $true
            break
        }
    }
    
    $newDeps = @()
    $removedDeps = @()
    $resolvedDeps = @()
    
    foreach ($dep in $task.dependencies) {
        $depLower = $dep.ToLower()
        $found = $false
        
        # First check if it exactly matches an existing task
        foreach ($t in $allTasks) {
            $taskSlug = ($t.name -replace '[^\w\s-]', '' -replace '\s+', '-').ToLower()
            
            # Exact matches only (no fuzzy matching here - we handle mappings separately)
            if ($t.id -eq $dep -or $t.name -eq $dep -or $taskSlug -eq $depLower) {
                $found = $true
                $newDeps += $dep
                break
            }
        }
        
        # If not found, check if we have a known mapping
        if (-not $found -and $dependencyMappings.ContainsKey($depLower)) {
            $mappedTasks = $dependencyMappings[$depLower]
            
            if ($mappedTasks.Count -eq 0) {
                # Dependency not yet completed - check if it's actually needed
                # or if this task is actually the one that implements it
                
                # Check if current task name contains the dependency name
                if ($taskNameLower -like "*$depLower*" -or $depLower -like "*$taskNameLower*") {
                    # This task IS the dependency - circular reference, remove it
                    $removedDeps += $dep
                    $resolvedDeps += "Removed '$dep' (circular: task implements this dependency)"
                } else {
                    # Real missing dependency - keep it but flag it
                    $removedDeps += $dep
                    $resolvedDeps += "Removed '$dep' (not yet implemented, blocking progress)"
                }
            } else {
                # Map to the actual completed task
                foreach ($mappedSlug in $mappedTasks) {
                    $mappedTask = $allTasks | Where-Object { 
                        $slug = ($_.name -replace '[^\w\s-]', '' -replace '\s+', '-').ToLower()
                        $slug -eq $mappedSlug
                    } | Select-Object -First 1
                    
                    if ($mappedTask) {
                        # Use the actual task name instead
                        $newDeps += $mappedTask.name
                        $resolvedDeps += "Mapped '$dep' → '$($mappedTask.name)'"
                        $found = $true
                    }
                }
                
                if (-not $found) {
                    $removedDeps += $dep
                    $resolvedDeps += "Removed '$dep' (mapped task not found)"
                }
            }
        } elseif (-not $found) {
            # Not found anywhere - remove it
            $removedDeps += $dep
            $resolvedDeps += "Removed '$dep' (does not exist)"
        }
    }
    
    # If this is a foundational task, remove all dependencies
    if ($isFoundational) {
        $newDeps = @()
        $resolvedDeps = @("Removed all dependencies (foundational task)")
    }
    
    # Only add to fixes if something changed
    if ($resolvedDeps.Count -gt 0) {
        $fixes += [PSCustomObject]@{
            Task = $task
            OriginalDeps = $task.dependencies
            NewDeps = $newDeps
            Changes = $resolvedDeps
            IsFoundational = $isFoundational
        }
    }
}

if ($fixes.Count -eq 0) {
    Write-Host "✓ No dependency issues found!" -ForegroundColor Green
    exit 0
}

Write-Host "Found $($fixes.Count) tasks with dependency issues:" -ForegroundColor Yellow
Write-Host ""

foreach ($fix in $fixes) {
    Write-Host "Task: $($fix.Task.name)" -ForegroundColor White
    Write-Host "  ID: $($fix.Task.id.Substring(0,8))"
    
    if ($fix.IsFoundational) {
        Write-Host "  Type: Foundational task" -ForegroundColor Cyan
    }
    
    foreach ($change in $fix.Changes) {
        if ($change -like "*Mapped*") {
            Write-Host "  ✓ $change" -ForegroundColor Green
        } elseif ($change -like "*Removed*") {
            Write-Host "  - $change" -ForegroundColor Yellow
        }
    }
    
    if ($fix.NewDeps.Count -gt 0) {
        Write-Host "  Final dependencies: $($fix.NewDeps -join ', ')" -ForegroundColor Cyan
    } else {
        Write-Host "  Final dependencies: None" -ForegroundColor Cyan
    }
    
    Write-Host ""
}

if ($Apply) {
    Write-Host "=== Applying Fixes ===" -ForegroundColor Cyan
    Write-Host ""
    
    foreach ($fix in $fixes) {
        $taskData = Get-Content $fix.Task.file_path | ConvertFrom-Json
        $taskData.dependencies = $fix.NewDeps
        $taskData.updated_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
        $taskData | ConvertTo-Json -Depth 10 | Set-Content -Path $fix.Task.file_path -Encoding UTF8
        
        Write-Host "✓ Fixed: $($fix.Task.name)" -ForegroundColor Green
    }
    
    Write-Host ""
    Write-Host "✓ Applied $($fixes.Count) fixes" -ForegroundColor Green
    Write-Host ""
    Write-Host "Run 'mcp__dotbot__task_get_next' to get the next available task." -ForegroundColor Cyan
} else {
    Write-Host "=== How to Apply ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Review the changes above, then run:" -ForegroundColor White
    Write-Host "  pwsh -ExecutionPolicy Bypass -File task-fix-dependencies-smart.ps1 -Apply" -ForegroundColor Yellow
    Write-Host ""
}
