<#
.SYNOPSIS
Expands task groups into detailed tasks by invoking Claude once per group.

.DESCRIPTION
Phase 2b orchestrator. Reads task-groups.json, topologically sorts groups by
dependencies, then expands each group sequentially by invoking Claude with
the 03b-expand-task-group.md template. After all groups are expanded, generates
a roadmap-overview.md summary.

.PARAMETER BotRoot
Path to the .bot directory.

.PARAMETER Model
Claude model name to use (e.g., claude-sonnet-4-5-20250929).

.PARAMETER ProcessId
Process registry ID for activity logging.
#>

param(
    [Parameter(Mandatory)]
    [string]$BotRoot,

    [Parameter(Mandatory)]
    [string]$Model,

    [string]$ProcessId
)

# --- Setup ---
Import-Module "$BotRoot\systems\runtime\ClaudeCLI\ClaudeCLI.psm1" -Force
Import-Module "$BotRoot\systems\runtime\modules\DotBotTheme.psm1" -Force
$t = Get-DotBotTheme

. "$BotRoot\systems\runtime\modules\ui-rendering.ps1"

$productDir = Join-Path $BotRoot "workspace\product"
$todoDir = Join-Path $BotRoot "workspace\tasks\todo"
$templatePath = Join-Path $BotRoot "prompts\workflows\03b-expand-task-group.md"
$groupsPath = Join-Path $productDir "task-groups.json"

# Set process ID for activity logging
if ($ProcessId) {
    $env:DOTBOT_PROCESS_ID = $ProcessId
}

# --- Helpers ---

function Write-GroupActivity {
    param([string]$Message)
    try { Write-ActivityLog -Type "text" -Message $Message } catch {}
    Write-Status $Message -Type Info
}

function Get-TopologicalOrder {
    param([array]$Groups)

    $sorted = [System.Collections.ArrayList]::new()
    $remaining = [System.Collections.ArrayList]::new()
    foreach ($g in $Groups) { [void]$remaining.Add($g) }
    $resolvedIds = @{}

    $maxIterations = $Groups.Count + 1
    $iteration = 0

    while ($remaining.Count -gt 0) {
        $iteration++
        if ($iteration -gt $maxIterations) {
            throw "Circular dependency detected among groups: $(($remaining | ForEach-Object { $_.id }) -join ', ')"
        }

        $ready = @($remaining | Where-Object {
            $allMet = $true
            if ($_.depends_on) {
                foreach ($dep in $_.depends_on) {
                    if (-not $resolvedIds.ContainsKey($dep)) { $allMet = $false; break }
                }
            }
            $allMet
        })

        if ($ready.Count -eq 0) {
            throw "Circular dependency detected among groups: $(($remaining | ForEach-Object { $_.id }) -join ', ')"
        }

        # Sort ready items by order field for deterministic output
        $ready = $ready | Sort-Object { $_.order }

        foreach ($g in $ready) {
            [void]$sorted.Add($g)
            $resolvedIds[$g.id] = $true
            $remaining.Remove($g) | Out-Null
        }
    }

    return $sorted.ToArray()
}

# --- Main ---

# 1. Read task-groups.json
if (-not (Test-Path $groupsPath)) {
    throw "task-groups.json not found at: $groupsPath"
}

$manifest = Get-Content $groupsPath -Raw | ConvertFrom-Json
$groups = @($manifest.groups)

Write-Header "Task Group Expansion"
Write-GroupActivity "Expanding $($groups.Count) task groups into detailed tasks"

# 2. Read template
if (-not (Test-Path $templatePath)) {
    throw "Template not found: $templatePath"
}
$template = Get-Content $templatePath -Raw

# 3. Topological sort
$sortedGroups = Get-TopologicalOrder -Groups $groups
Write-GroupActivity "Expansion order: $(($sortedGroups | ForEach-Object { $_.name }) -join ' -> ')"

# 4. Expand each group
$groupTaskMap = @{}  # group_id -> array of {id, name}
$totalTasksCreated = 0

foreach ($group in $sortedGroups) {
    Write-Header "Group: $($group.name)"
    Write-GroupActivity "Expanding group: $($group.name) (order $($group.order))"

    # Build dependency task list from prerequisite groups
    $depTasks = @()
    if ($group.depends_on) {
        foreach ($depGroupId in $group.depends_on) {
            if ($groupTaskMap.ContainsKey($depGroupId)) {
                $depTasks += $groupTaskMap[$depGroupId]
            }
        }
    }

    $depTasksJson = if ($depTasks.Count -gt 0) {
        "Tasks from prerequisite groups:`n``````json`n$($depTasks | ConvertTo-Json -Depth 5)`n```````n`nYou may reference these task IDs in the ``dependencies`` array where technically justified."
    } else {
        "No prerequisite tasks. This is a root group with no cross-group dependencies."
    }

    # Build scope list
    $scopeList = if ($group.scope) {
        ($group.scope | ForEach-Object { "- $_" }) -join "`n"
    } else {
        "- (No specific scope items defined)"
    }

    # Build acceptance criteria list
    $acList = if ($group.acceptance_criteria) {
        ($group.acceptance_criteria | ForEach-Object { "- $_" }) -join "`n"
    } else {
        "- (No specific acceptance criteria defined)"
    }

    # Extract priority range
    $priorityMin = if ($group.priority_range -and $group.priority_range.Count -ge 2) { $group.priority_range[0] } else { 1 }
    $priorityMax = if ($group.priority_range -and $group.priority_range.Count -ge 2) { $group.priority_range[1] } else { 100 }

    # Substitute template variables
    $prompt = $template
    $prompt = $prompt -replace '\{\{GROUP_ID\}\}', $group.id
    $prompt = $prompt -replace '\{\{GROUP_NAME\}\}', $group.name
    $prompt = $prompt -replace '\{\{GROUP_DESCRIPTION\}\}', $group.description
    $prompt = $prompt -replace '\{\{GROUP_SCOPE\}\}', $scopeList
    $prompt = $prompt -replace '\{\{GROUP_ACCEPTANCE_CRITERIA\}\}', $acList
    $prompt = $prompt -replace '\{\{PRIORITY_MIN\}\}', $priorityMin
    $prompt = $prompt -replace '\{\{PRIORITY_MAX\}\}', $priorityMax
    $prompt = $prompt -replace '\{\{CATEGORY_HINT\}\}', $group.category_hint
    $prompt = $prompt -replace '\{\{DEPENDENCY_TASKS\}\}', $depTasksJson

    # Snapshot todo directory before expansion
    $beforeFiles = @()
    if (Test-Path $todoDir) {
        $beforeFiles = @(Get-ChildItem -Path $todoDir -Filter "*.json" | ForEach-Object { $_.FullName })
    }

    # Invoke Claude to expand this group
    $sessionId = [System.Guid]::NewGuid().ToString()
    try {
        Invoke-ClaudeStream -Prompt $prompt -Model $Model -SessionId $sessionId -PersistSession:$false
    } catch {
        Write-GroupActivity "Error expanding group $($group.name): $($_.Exception.Message)"
        Write-Status "Failed to expand group: $($group.name)" -Type Error
        continue
    }

    # Discover newly created tasks
    $afterFiles = @()
    if (Test-Path $todoDir) {
        $afterFiles = @(Get-ChildItem -Path $todoDir -Filter "*.json" | ForEach-Object { $_.FullName })
    }
    $newFiles = @($afterFiles | Where-Object { $_ -notin $beforeFiles })

    $newTasks = @()
    foreach ($f in $newFiles) {
        try {
            $taskData = Get-Content $f -Raw | ConvertFrom-Json
            $newTasks += @{ id = $taskData.id; name = $taskData.name }
        } catch {}
    }

    $groupTaskMap[$group.id] = $newTasks
    $totalTasksCreated += $newTasks.Count

    Write-GroupActivity "Group '$($group.name)' expanded: $($newTasks.Count) tasks created"

    # Brief pause between groups to avoid rate limits
    if ($group -ne $sortedGroups[-1]) {
        Start-Sleep -Seconds 2
    }
}

# 5. Generate roadmap-overview.md
Write-GroupActivity "Generating roadmap overview..."

$overviewLines = [System.Collections.ArrayList]::new()
[void]$overviewLines.Add("# Task Roadmap Overview")
[void]$overviewLines.Add("")
[void]$overviewLines.Add("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
[void]$overviewLines.Add("Total Tasks: $totalTasksCreated")
[void]$overviewLines.Add("Task Groups: $($sortedGroups.Count)")
[void]$overviewLines.Add("")

# Executive summary from mission.md
$missionPath = Join-Path $productDir "mission.md"
if (Test-Path $missionPath) {
    $missionContent = Get-Content $missionPath -Raw
    # Extract first paragraph after the title
    if ($missionContent -match '(?m)^#[^#].*\n+(.+)') {
        [void]$overviewLines.Add("## Executive Summary")
        [void]$overviewLines.Add("")
        [void]$overviewLines.Add($matches[1].Trim())
        [void]$overviewLines.Add("")
    }
}

[void]$overviewLines.Add("## Implementation Groups")
[void]$overviewLines.Add("")

foreach ($group in $sortedGroups) {
    $taskCount = if ($groupTaskMap.ContainsKey($group.id)) { $groupTaskMap[$group.id].Count } else { 0 }
    $depStr = if ($group.depends_on -and $group.depends_on.Count -gt 0) {
        " (depends on: $(($group.depends_on | ForEach-Object { $_ }) -join ', '))"
    } else { "" }

    [void]$overviewLines.Add("### $($group.order). $($group.name)")
    [void]$overviewLines.Add("")
    [void]$overviewLines.Add("$($group.description)")
    [void]$overviewLines.Add("")
    [void]$overviewLines.Add("- **Tasks:** $taskCount")
    [void]$overviewLines.Add("- **Priority range:** $($group.priority_range[0])-$($group.priority_range[1])")
    [void]$overviewLines.Add("- **Category:** $($group.category_hint)$depStr")
    [void]$overviewLines.Add("")

    if ($groupTaskMap.ContainsKey($group.id)) {
        foreach ($task in $groupTaskMap[$group.id]) {
            [void]$overviewLines.Add("  - $($task.name)")
        }
        [void]$overviewLines.Add("")
    }
}

[void]$overviewLines.Add("## Next Steps")
[void]$overviewLines.Add("")
[void]$overviewLines.Add("1. Review task list and adjust priorities if needed")
[void]$overviewLines.Add("2. Begin implementation with ``task_get_next``")
[void]$overviewLines.Add("3. Run analysis loop to prepare tasks for execution")
[void]$overviewLines.Add("")

$overviewPath = Join-Path $productDir "roadmap-overview.md"
$overviewLines -join "`n" | Set-Content -Path $overviewPath -Encoding UTF8
Write-GroupActivity "Roadmap overview saved to: $overviewPath"

# 6. Rename task-groups.json -> task-groups.done.json
$donePath = Join-Path $productDir "task-groups.done.json"
Move-Item -Path $groupsPath -Destination $donePath -Force
Write-GroupActivity "Renamed task-groups.json -> task-groups.done.json"

# Final summary
Write-Header "Expansion Complete"
Write-GroupActivity "Task group expansion complete: $totalTasksCreated tasks created across $($sortedGroups.Count) groups"
