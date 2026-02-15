<#
.SYNOPSIS
Git worktree lifecycle management for per-task isolation.

.DESCRIPTION
Each task gets its own git branch and worktree, created at analysis start
and persisting through execution. On completion, the branch is squash-merged
to main and the worktree is cleaned up.

Worktree path convention:
  {repo-parent}/worktrees/{repo-name}/task-{short-id}-{slug}/

Branch naming:
  task/{short-id}-{slug}

Shared infrastructure via directory junctions:
  .bot/.control/        -> central control (process registry, settings)
  .bot/workspace/tasks/ -> central task queue (todo, done, etc.)
#>

# --- Internal State ---
$script:WorktreeMapPath = $null

# Large, regenerable directories excluded from gitignored file copying
$script:NoiseDirectories = @(
    'bin', 'obj', 'node_modules', 'packages',
    'Debug', 'Release', 'x64', 'x86',
    '.vs', '.idea', '.vscode',
    '__pycache__', '.mypy_cache',
    '.git', '.control', '.playwright-mcp',
    'TestResults'
)

# --- Internal Helpers ---

function Get-BaseBranch {
    param([string]$ProjectRoot)
    $branch = git -C $ProjectRoot symbolic-ref --short HEAD 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $branch) { $branch = 'main' }
    return $branch
}

function Initialize-WorktreeMap {
    param([string]$BotRoot)
    $controlDir = Join-Path $BotRoot ".control"
    $script:WorktreeMapPath = Join-Path $controlDir "worktree-map.json"
}

function Read-WorktreeMap {
    if (-not $script:WorktreeMapPath -or -not (Test-Path $script:WorktreeMapPath)) {
        return @{}
    }
    try {
        $content = Get-Content $script:WorktreeMapPath -Raw
        if ([string]::IsNullOrWhiteSpace($content)) { return @{} }
        $json = $content | ConvertFrom-Json
        $map = @{}
        foreach ($prop in $json.PSObject.Properties) {
            $map[$prop.Name] = $prop.Value
        }
        return $map
    } catch {
        return @{}
    }
}

function Write-WorktreeMap {
    param([hashtable]$Map)
    if (-not $script:WorktreeMapPath) { return }
    $dir = Split-Path $script:WorktreeMapPath -Parent
    if (-not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }
    $tempFile = "$($script:WorktreeMapPath).tmp"
    $Map | ConvertTo-Json -Depth 10 | Set-Content -Path $tempFile -Encoding utf8NoBOM -NoNewline
    Move-Item -Path $tempFile -Destination $script:WorktreeMapPath -Force
}

function Get-TaskSlug {
    param([string]$TaskName)
    $slug = $TaskName.ToLower()
    $slug = $slug -replace '[^a-z0-9]+', '-'
    $slug = $slug -replace '^-|-$', ''
    if ($slug.Length -gt 50) { $slug = $slug.Substring(0, 50) -replace '-$', '' }
    return $slug
}

function Remove-Junctions {
    <#
    .SYNOPSIS
    Remove directory junctions from a worktree without following into shared dirs
    #>
    param([string]$WorktreePath)

    $junctionPaths = @(
        (Join-Path $WorktreePath ".bot\.control"),
        (Join-Path $WorktreePath ".bot\workspace\tasks")
    )
    foreach ($jp in $junctionPaths) {
        if ((Test-Path $jp) -and (Get-Item $jp).Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
            # cmd rmdir removes the junction link without following into target
            cmd /c rmdir "$jp" 2>$null
        }
    }
}

# --- Exported Functions ---

function New-TaskWorktree {
    <#
    .SYNOPSIS
    Create a git branch and worktree for a task, with junctions and artifact copying.

    .OUTPUTS
    Hashtable with: worktree_path, branch_name, success, message
    #>
    param(
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$TaskName,
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$BotRoot
    )

    Initialize-WorktreeMap -BotRoot $BotRoot

    $shortId = $TaskId.Substring(0, [Math]::Min(8, $TaskId.Length))
    $slug = Get-TaskSlug -TaskName $TaskName
    $branchName = "task/$shortId-$slug"

    # Worktree path: {repo-parent}/worktrees/{repo-name}/task-{shortId}-{slug}/
    $repoParent = Split-Path $ProjectRoot -Parent
    $repoName = Split-Path $ProjectRoot -Leaf
    $worktreeDir = Join-Path $repoParent "worktrees\$repoName"
    $worktreePath = Join-Path $worktreeDir "task-$shortId-$slug"

    if (-not (Test-Path $worktreeDir)) {
        New-Item -Path $worktreeDir -ItemType Directory -Force | Out-Null
    }

    # If worktree already exists, return it
    if (Test-Path $worktreePath) {
        # Ensure map entry exists
        $map = Read-WorktreeMap
        if (-not $map.ContainsKey($TaskId)) {
            $map[$TaskId] = @{
                worktree_path = $worktreePath
                branch_name   = $branchName
                task_name     = $TaskName
                created_at    = (Get-Date).ToUniversalTime().ToString("o")
            }
            Write-WorktreeMap -Map $map
        }
        return @{
            worktree_path = $worktreePath
            branch_name   = $branchName
            success       = $true
            message       = "Worktree already exists"
        }
    }

    try {
        # Create branch from the repo's current branch and check it out in the worktree
        $baseBranch = Get-BaseBranch -ProjectRoot $ProjectRoot
        $output = git -C $ProjectRoot worktree add -b $branchName $worktreePath $baseBranch 2>&1
        if ($LASTEXITCODE -ne 0) {
            # Branch may already exist from an interrupted run — try without -b
            $output = git -C $ProjectRoot worktree add $worktreePath $branchName 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "git worktree add failed: $($output -join ' ')"
            }
        }

        # --- Set up junctions for shared infrastructure ---

        # 1. .bot/.control/ — gitignored, won't exist in worktree
        $worktreeControlDir = Join-Path $worktreePath ".bot\.control"
        $mainControlDir = Join-Path $BotRoot ".control"
        if (-not (Test-Path $worktreeControlDir)) {
            $controlParent = Split-Path $worktreeControlDir -Parent
            if (-not (Test-Path $controlParent)) {
                New-Item -Path $controlParent -ItemType Directory -Force | Out-Null
            }
            New-Item -ItemType Junction -Path $worktreeControlDir -Target $mainControlDir | Out-Null
        }

        # 2. .bot/workspace/tasks/ — has tracked .gitkeep files, replace with junction
        $worktreeTasksDir = Join-Path $worktreePath ".bot\workspace\tasks"
        $mainTasksDir = Join-Path $BotRoot "workspace\tasks"
        if (Test-Path $worktreeTasksDir) {
            Remove-Item -Path $worktreeTasksDir -Recurse -Force
        }
        $tasksParent = Split-Path $worktreeTasksDir -Parent
        if (-not (Test-Path $tasksParent)) {
            New-Item -Path $tasksParent -ItemType Directory -Force | Out-Null
        }
        New-Item -ItemType Junction -Path $worktreeTasksDir -Target $mainTasksDir | Out-Null

        # Copy non-noisy gitignored build artifacts
        Copy-BuildArtifacts -ProjectRoot $ProjectRoot -WorktreePath $worktreePath

        # Register in worktree map
        $map = Read-WorktreeMap
        $map[$TaskId] = @{
            worktree_path = $worktreePath
            branch_name   = $branchName
            task_name     = $TaskName
            created_at    = (Get-Date).ToUniversalTime().ToString("o")
        }
        Write-WorktreeMap -Map $map

        return @{
            worktree_path = $worktreePath
            branch_name   = $branchName
            success       = $true
            message       = "Worktree created at $worktreePath"
        }
    } catch {
        return @{
            worktree_path = $null
            branch_name   = $branchName
            success       = $false
            message       = "Failed to create worktree: $($_.Exception.Message)"
        }
    }
}

function Complete-TaskWorktree {
    <#
    .SYNOPSIS
    Squash-merge a task branch to main, then clean up the worktree and branch.

    .OUTPUTS
    Hashtable with: success, merge_commit, message, conflict_files
    #>
    param(
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$BotRoot
    )

    Initialize-WorktreeMap -BotRoot $BotRoot
    $map = Read-WorktreeMap

    if (-not $map.ContainsKey($TaskId)) {
        return @{
            success        = $true
            merge_commit   = $null
            message        = "No worktree found for task $TaskId (no merge needed)"
            conflict_files = @()
        }
    }

    $entry = $map[$TaskId]
    $worktreePath = $entry.worktree_path
    $branchName = $entry.branch_name
    $taskName = $entry.task_name
    $shortId = $TaskId.Substring(0, [Math]::Min(8, $TaskId.Length))

    try {
        # Ensure main repo is on its base branch
        $baseBranch = Get-BaseBranch -ProjectRoot $ProjectRoot
        $currentBranch = git -C $ProjectRoot rev-parse --abbrev-ref HEAD 2>$null
        if ($currentBranch -ne $baseBranch) {
            git -C $ProjectRoot checkout $baseBranch 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "Failed to checkout $baseBranch branch" }
        }

        # Rebase task branch onto base branch (brings task commits up to date)
        $rebaseOutput = git -C $worktreePath rebase $baseBranch 2>&1
        if ($LASTEXITCODE -ne 0) {
            git -C $worktreePath rebase --abort 2>$null
            $conflictLines = @($rebaseOutput | ForEach-Object { "$_" } | Where-Object { $_ -match 'CONFLICT|error|fatal' })
            return @{
                success        = $false
                merge_commit   = $null
                message        = "Rebase failed - conflicts detected"
                conflict_files = $conflictLines
            }
        }

        # Squash merge into main
        $mergeOutput = git -C $ProjectRoot merge --squash $branchName 2>&1
        if ($LASTEXITCODE -ne 0) {
            git -C $ProjectRoot reset --hard HEAD 2>$null
            return @{
                success        = $false
                merge_commit   = $null
                message        = "Squash merge failed: $($mergeOutput -join ' ')"
                conflict_files = @()
            }
        }

        # Commit if there are staged changes (task may have made no code changes)
        $staged = git -C $ProjectRoot diff --cached --name-only 2>$null
        if ($staged) {
            git -C $ProjectRoot commit -m "feat: $taskName [task:$shortId]" 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) {
                return @{
                    success        = $false
                    merge_commit   = $null
                    message        = "Commit failed after squash merge"
                    conflict_files = @()
                }
            }
        }

        $mergeCommit = git -C $ProjectRoot rev-parse HEAD 2>$null

        # Remove junctions before worktree removal to prevent following into shared dirs
        Remove-Junctions -WorktreePath $worktreePath

        # Remove worktree and branch
        git -C $ProjectRoot worktree remove $worktreePath --force 2>$null
        git -C $ProjectRoot branch -D $branchName 2>$null

        # Remove from registry
        $map.Remove($TaskId)
        Write-WorktreeMap -Map $map

        return @{
            success        = $true
            merge_commit   = $mergeCommit
            message        = "Squash-merged to $baseBranch and cleaned up"
            conflict_files = @()
        }
    } catch {
        return @{
            success        = $false
            merge_commit   = $null
            message        = "Error during merge: $($_.Exception.Message)"
            conflict_files = @()
        }
    }
}

function Get-TaskWorktreePath {
    <#
    .SYNOPSIS
    Look up the worktree path for a given task ID.

    .OUTPUTS
    Path string or $null if not found / not on disk
    #>
    param(
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$BotRoot
    )

    Initialize-WorktreeMap -BotRoot $BotRoot
    $map = Read-WorktreeMap
    if ($map.ContainsKey($TaskId)) {
        $path = $map[$TaskId].worktree_path
        if (Test-Path $path) { return $path }
    }
    return $null
}

function Get-TaskWorktreeInfo {
    <#
    .SYNOPSIS
    Look up the full worktree registry entry for a task ID.

    .OUTPUTS
    PSObject with worktree_path, branch_name, task_name, created_at — or $null
    #>
    param(
        [Parameter(Mandatory)][string]$TaskId,
        [Parameter(Mandatory)][string]$BotRoot
    )

    Initialize-WorktreeMap -BotRoot $BotRoot
    $map = Read-WorktreeMap
    if ($map.ContainsKey($TaskId)) { return $map[$TaskId] }
    return $null
}

function Get-GitignoredCopyPaths {
    <#
    .SYNOPSIS
    Find gitignored files that exist in the repo, excluding noisy regenerable dirs.

    .OUTPUTS
    Array of relative paths (small config files like .env)
    #>
    param(
        [Parameter(Mandatory)][string]$ProjectRoot
    )

    try {
        $ignoredFiles = git -C $ProjectRoot ls-files --others --ignored --exclude-standard 2>$null
        if (-not $ignoredFiles -or $LASTEXITCODE -ne 0) { return @() }

        $paths = @()
        foreach ($relativePath in $ignoredFiles) {
            $parts = $relativePath -split '[/\\]'
            $isNoisy = $false
            foreach ($part in $parts) {
                if ($script:NoiseDirectories -contains $part) {
                    $isNoisy = $true
                    break
                }
            }
            if (-not $isNoisy) {
                $paths += $relativePath
            }
        }
        return $paths
    } catch {
        return @()
    }
}

function Copy-BuildArtifacts {
    <#
    .SYNOPSIS
    Copy non-noisy gitignored files from main repo to worktree.
    #>
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$WorktreePath
    )

    $paths = Get-GitignoredCopyPaths -ProjectRoot $ProjectRoot
    if ($paths.Count -eq 0) { return }

    foreach ($relativePath in $paths) {
        $sourcePath = Join-Path $ProjectRoot $relativePath
        $destPath = Join-Path $WorktreePath $relativePath

        if (-not (Test-Path $sourcePath)) { continue }

        $destParent = Split-Path $destPath -Parent
        if (-not (Test-Path $destParent)) {
            New-Item -Path $destParent -ItemType Directory -Force | Out-Null
        }

        try {
            if (Test-Path $sourcePath -PathType Container) {
                Copy-Item -Path $sourcePath -Destination $destPath -Recurse -Force
            } else {
                Copy-Item -Path $sourcePath -Destination $destPath -Force
            }
        } catch {
            # Non-critical — skip files that can't be copied
        }
    }
}

function Remove-OrphanWorktrees {
    <#
    .SYNOPSIS
    Clean up worktrees for tasks that are no longer active (done/skipped/cancelled).
    Called on process startup.
    #>
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [Parameter(Mandatory)][string]$BotRoot
    )

    Initialize-WorktreeMap -BotRoot $BotRoot
    $map = Read-WorktreeMap
    if ($map.Count -eq 0) { return }

    $tasksBaseDir = Join-Path $BotRoot "workspace\tasks"
    $activeDirs = @('todo', 'analysing', 'needs-input', 'analysed', 'in-progress')
    $orphanIds = @()

    foreach ($taskId in @($map.Keys)) {
        $isActive = $false
        foreach ($dir in $activeDirs) {
            $dirPath = Join-Path $tasksBaseDir $dir
            if (-not (Test-Path $dirPath)) { continue }
            $files = Get-ChildItem -Path $dirPath -Filter "*.json" -File -ErrorAction SilentlyContinue
            foreach ($f in $files) {
                try {
                    $content = Get-Content -Path $f.FullName -Raw | ConvertFrom-Json
                    if ($content.id -eq $taskId) {
                        $isActive = $true
                        break
                    }
                } catch {}
            }
            if ($isActive) { break }
        }
        if (-not $isActive) { $orphanIds += $taskId }
    }

    foreach ($taskId in $orphanIds) {
        $entry = $map[$taskId]
        $worktreePath = $entry.worktree_path
        $branchName = $entry.branch_name

        # Remove junctions first
        if ($worktreePath -and (Test-Path $worktreePath)) {
            Remove-Junctions -WorktreePath $worktreePath
        }

        git -C $ProjectRoot worktree remove $worktreePath --force 2>$null
        git -C $ProjectRoot branch -D $branchName 2>$null

        $map.Remove($taskId)
    }

    if ($orphanIds.Count -gt 0) {
        Write-WorktreeMap -Map $map
    }
}

# --- Module Exports ---
Export-ModuleMember -Function @(
    'New-TaskWorktree'
    'Complete-TaskWorktree'
    'Get-TaskWorktreePath'
    'Get-TaskWorktreeInfo'
    'Get-GitignoredCopyPaths'
    'Copy-BuildArtifacts'
    'Remove-OrphanWorktrees'
)
