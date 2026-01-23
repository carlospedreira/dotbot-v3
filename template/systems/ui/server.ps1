<#
.SYNOPSIS
Minimal PowerShell web server for .bot autonomous development monitoring

.DESCRIPTION
Serves a terminal-inspired web UI on localhost:8686 that monitors .bot folder state
and provides control signals via file-based communication.

.PARAMETER Port
Port to run the web server on (default: 8686)

.EXAMPLE
.\server.ps1
#>

param(
    [Parameter(Mandatory = $false)]
    [int]$Port = 8686
)

# Find .bot root (server is at .bot/systems/ui, so go up 2 levels)
$botRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$projectRoot = Split-Path -Parent $botRoot
$staticRoot = Join-Path $PSScriptRoot "static"
$controlDir = Join-Path $botRoot ".control"

# Import DotBotTheme
Import-Module (Join-Path $botRoot "systems\runtime\modules\DotBotTheme.psm1") -Force
$t = Get-DotBotTheme

# Import MCP session tools
. "$botRoot\systems\mcp\tools\session-get-state\script.ps1"
. "$botRoot\systems\mcp\tools\session-get-stats\script.ps1"

# Import FileWatcher module for event-driven state updates
Import-Module (Join-Path $PSScriptRoot "modules\FileWatcher.psm1") -Force

# Initialize file watchers for real-time change detection
Initialize-FileWatchers -BotRoot $botRoot

# Request counter for single-line logging
$script:requestCount = 0

# Clear screen
Clear-Host

# Display banner
Write-Card -Title "Dotbot Control Panel" -Width 70 -BorderStyle Rounded -BorderColor Label -TitleColor Label -Lines @(
    "$($t.Amber)Real-time monitoring and control for autonomous development$($t.Reset)"
)

Write-Card -Title "Configuration" -Width 70 -BorderStyle Rounded -BorderColor Label -TitleColor Label -Lines @(
    "$($t.Label)Port:$($t.Reset) $($t.Amber)$Port$($t.Reset)"
    "$($t.Label)URL:$($t.Reset) $($t.Cyan)http://localhost:$Port/$($t.Reset)"
    "$($t.Label).bot root:$($t.Reset) $($t.Amber)$botRoot$($t.Reset)"
    "$($t.Label)Static files:$($t.Reset) $($t.Amber)$staticRoot$($t.Reset)"
)

# Ensure control directory exists
Write-Phosphor "› Initializing server..." -Color Cyan -NoNewline
if (-not (Test-Path $controlDir)) {
    New-Item -ItemType Directory -Path $controlDir -Force | Out-Null
}
Write-Phosphor " ✓" -Color Green

# Check static directory exists
Write-Phosphor "› Checking static files..." -Color Cyan -NoNewline
if (Test-Path $staticRoot) {
    Write-Phosphor " ✓" -Color Green
} else {
    Write-Phosphor " ⚠" -Color Amber
    Write-Status "Static directory not found: $staticRoot" -Type Warn
}

# HTTP listener
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
Write-Phosphor "› Starting listener..." -Color Cyan -NoNewline
try {
    $listener.Start()
    Write-Phosphor " ✓" -Color Green
    Write-Host "$($t.Green)●$($t.Reset) $($t.Label)Press Ctrl+C to stop$($t.Reset)"
    Write-Separator -Width 70
} catch {
    Write-Phosphor " ✗" -Color Red
    Write-Status "Error starting listener: $($_.Exception.Message)" -Type Error
    exit 1
}

# Helper: Get directory list for bot directories
function Get-BotDirectoryList {
    param([string]$Directory)

    $dirPath = Join-Path $botRoot "prompts\$Directory"
    $groups = [System.Collections.Generic.Dictionary[string, System.Collections.ArrayList]]::new()

    if (Test-Path $dirPath) {
        # Get all .md files recursively, excluding archived folders
        $mdFiles = @(Get-ChildItem -Path $dirPath -Filter "*.md" -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch '\\archived\\' })

        foreach ($file in $mdFiles) {
            if ($null -eq $file) { continue }

            # Calculate relative path from directory root
            $relativePath = $file.FullName.Replace("$dirPath\", "").Replace("\", "/")

            # Determine folder group
            $folder = "(root)"
            if ($relativePath -like '*/*') {
                $folder = Split-Path $relativePath -Parent
            }

            # Initialize group if needed
            if (-not $groups.ContainsKey($folder)) {
                $groups[$folder] = [System.Collections.ArrayList]::new()
            }

            # Add item to group
            [void]$groups[$folder].Add(@{
                name = $file.BaseName
                filename = $relativePath
                basename = $file.BaseName
            })
        }
    }

    # Convert to grouped structure
    $groupedItems = [System.Collections.ArrayList]::new()
    foreach ($key in @($groups.Keys)) {
        $itemsArray = @()
        $groupItems = $groups[$key]
        if ($null -ne $groupItems -and $groupItems.Count -gt 0) {
            # Convert to array of PSObjects for reliable sorting
            $sortable = @()
            foreach ($item in $groupItems) {
                $sortable += [PSCustomObject]@{
                    name = $item.name
                    filename = $item.filename
                    basename = $item.basename
                }
            }
            $itemsArray = @($sortable | Sort-Object -Property name)
        }
        [void]$groupedItems.Add([PSCustomObject]@{
            folder = if ($key -eq "(root)") { "" } else { $key.Replace('\', '/') }
            items = $itemsArray
        })
    }

    # Sort groups by folder name (empty string first for root)
    $sorted = @()
    if ($groupedItems.Count -gt 0) {
        $sorted = @($groupedItems | Sort-Object -Property folder)
    }

    return @{ groups = $sorted } | ConvertTo-Json -Depth 5 -Compress
}
# Helper: Get cache location
function Get-CacheLocation {
    $projectHash = [System.BitConverter]::ToString(
        [System.Security.Cryptography.MD5]::Create().ComputeHash(
            [System.Text.Encoding]::UTF8.GetBytes($projectRoot)
        )
    ).Replace("-", "").Substring(0, 8)
    
    $cachePath = Join-Path $env:TEMP ".bot-ui-cache" $projectHash
    if (-not (Test-Path $cachePath)) {
        New-Item -Path $cachePath -ItemType Directory -Force | Out-Null
    }
    return $cachePath
}

# Helper: Test cache validity
function Test-CacheValidity {
    $cacheFile = Join-Path (Get-CacheLocation) "references.json"
    
    if (-not (Test-Path $cacheFile)) {
        return $false
    }
    
    try {
        $cache = Get-Content $cacheFile -Raw | ConvertFrom-Json
        
        # Check if any files have been modified
        foreach ($fileEntry in $cache.file_mtimes.PSObject.Properties) {
            $filePath = Join-Path $botRoot $fileEntry.Name
            if (Test-Path -LiteralPath $filePath) {
                $currentMtime = (Get-Item -LiteralPath $filePath).LastWriteTimeUtc.ToString("yyyy-MM-ddTHH:mm:ssZ")
                if ($currentMtime -ne $fileEntry.Value) {
                    return $false
                }
            }
        }
        
        # Cache is valid if less than 24 hours old
        $cacheAge = (Get-Date) - [DateTime]::Parse($cache.generated_at)
        return $cacheAge.TotalHours -lt 24
    } catch {
        return $false
    }
}

# Helper: Clear reference cache
function Clear-ReferenceCache {
    $cacheFile = Join-Path (Get-CacheLocation) "references.json"
    if (Test-Path $cacheFile) {
        Remove-Item $cacheFile -Force
    }
}

# Helper: Get file with references (dynamic - finds directory by short type prefix)
function Get-FileWithReferences {
    param(
        [string]$Type,
        [string]$Filename
    )

    # Dynamically find directory that matches the short type
    $promptsDir = Join-Path $botRoot "prompts"
    $matchingDir = $null

    if (Test-Path $promptsDir) {
        $allDirs = Get-ChildItem -Path $promptsDir -Directory
        foreach ($dir in $allDirs) {
            $shortType = $dir.Name.Substring(0, [Math]::Min(3, $dir.Name.Length))
            if ($shortType -eq $Type) {
                $matchingDir = $dir.Name
                break
            }
        }
    }

    if (-not $matchingDir) {
        return @{
            success = $false
            error = "Invalid type: $Type"
        } | ConvertTo-Json -Compress
    }

    $targetDir = Join-Path $botRoot "prompts\$matchingDir"
    $filePath = Join-Path $targetDir $Filename
    
    if (-not (Test-Path -LiteralPath $filePath)) {
        return @{
            success = $false
            error = "File not found: $Filename"
        } | ConvertTo-Json -Compress
    }
    
    # Check cache first
    $cacheFile = Join-Path (Get-CacheLocation) "references.json"
    $cache = $null
    
    if (Test-CacheValidity) {
        try {
            $cache = Get-Content $cacheFile -Raw | ConvertFrom-Json
        } catch {
            # Cache invalid, will rebuild
        }
    }
    
    # Build cache if needed
    if (-not $cache) {
        $cache = Build-ReferenceCache
    }
    
    # Get file content
    $fileContent = Get-Content -LiteralPath $filePath -Raw
    $relativePath = "$matchingDir/$Filename"

    # Get references from cache
    $references = @()
    $referencedBy = @()

    Write-Phosphor "Looking up: $relativePath" -Color Bezel

    # Handle both hashtable (from Build-ReferenceCache) and PSCustomObject (from JSON)
    $hasKey = $false
    if ($cache.references -is [hashtable]) {
        $hasKey = $cache.references.ContainsKey($relativePath)
    } elseif ($null -ne $cache.references) {
        $hasKey = $null -ne $cache.references.PSObject.Properties[$relativePath]
    }

    Write-Phosphor "Cache has key? $hasKey" -Color Bezel

    if ($hasKey) {
        $fileRefs = $cache.references.$relativePath
        if ($null -ne $fileRefs) {
            $refCount = if ($fileRefs.references) { @($fileRefs.references).Count } else { 0 }
            $refByCount = if ($fileRefs.referenced_by) { @($fileRefs.referenced_by).Count } else { 0 }
            Write-Status "Found refs: $refCount, refBy: $refByCount" -Type Success
            if ($fileRefs.references) {
                $references = @($fileRefs.references)
            }
            if ($fileRefs.referenced_by) {
                $referencedBy = @($fileRefs.referenced_by)
            }
        }
    } else {
        Write-Status "Key not found in cache!" -Type Error
    }
    
    return @{
        success = $true
        name = $Filename
        content = $fileContent
        references = $references
        referencedBy = $referencedBy
        cacheAge = if ($cache.generated_at) { 
            [int]((Get-Date) - [DateTime]::Parse($cache.generated_at)).TotalMinutes 
        } else { 0 }
    } | ConvertTo-Json -Depth 5 -Compress
}

# Helper: Build reference cache
function Build-ReferenceCache {
    Write-Host ""
    Write-Status "Building reference cache..." -Type Process
    
    $cache = @{
        generated_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        project_root = $projectRoot
        file_mtimes = @{}
        references = @{}
    }
    
    # Dynamically discover directories under .bot/prompts/
    $promptsDir = Join-Path $botRoot "prompts"
    $dirs = @()
    if (Test-Path $promptsDir) {
        $dirs = @(Get-ChildItem -Path $promptsDir -Directory | ForEach-Object { $_.Name })
    }
    $allFiles = @{}
    
    # First pass: collect all files
    foreach ($dir in $dirs) {
        $dirPath = Join-Path $botRoot "prompts\$dir"
        if (Test-Path $dirPath) {
            $mdFiles = Get-ChildItem -Path $dirPath -Filter "*.md" -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -notmatch '\\archived\\' }
            
            foreach ($file in $mdFiles) {
                $relativePath = "$dir/" + $file.FullName.Replace("$dirPath\", "").Replace("\", "/")
                $allFiles[$relativePath] = $file.FullName
                $cache.file_mtimes[$relativePath] = $file.LastWriteTimeUtc.ToString("yyyy-MM-ddTHH:mm:ssZ")
            }
        }
    }
    
    # Second pass: parse references
    foreach ($entry in $allFiles.GetEnumerator()) {
        $relativePath = $entry.Key
        $fullPath = $entry.Value
        $content = Get-Content -Path $fullPath -Raw
        
        $references = @()
        
        # Parse markdown links: [text](path.md)
        $mdLinkPattern = '\[([^\]]+)\]\(([^\)]+\.md)\)'
        $regexMatches = [regex]::Matches($content, $mdLinkPattern)
        foreach ($m in $regexMatches) {
            if ($null -ne $m -and $null -ne $m.Groups -and $m.Groups.Count -gt 2) {
                $linkPath = $m.Groups[2].Value
                $references += Parse-Reference -LinkPath $linkPath -CurrentFile $relativePath -AllFiles $allFiles
            }
        }

        # Parse agent directives: @.bot/prompts/agents/name.md
        $agentPattern = '@\.bot/prompts/(\w+)/([^\s]+\.md)'
        $regexMatches = [regex]::Matches($content, $agentPattern)
        foreach ($m in $regexMatches) {
            if ($null -ne $m -and $null -ne $m.Groups -and $m.Groups.Count -gt 2) {
                $dir = $m.Groups[1].Value
                $refFullPath = $m.Groups[2].Value
                $filename = Split-Path $refFullPath -Leaf
                $references += @{
                    type = Get-TypeFromDir -Dir $dir
                    file = $refFullPath
                    name = [System.IO.Path]::GetFileNameWithoutExtension($filename)
                }
            }
        }

        # Parse path references: .bot/prompts/standards/global/file.md
        $pathPattern = '\.bot/prompts/(\w+)/([^\s]+\.md)'
        $regexMatches = [regex]::Matches($content, $pathPattern)
        foreach ($m in $regexMatches) {
            if ($null -ne $m -and $null -ne $m.Groups -and $m.Groups.Count -gt 2) {
                $dir = $m.Groups[1].Value
                $refFullPath = $m.Groups[2].Value  # e.g., "global/workflow-interaction.md" or "write-spec.md"
                $filename = Split-Path $refFullPath -Leaf  # Get just the filename
                $references += @{
                    type = Get-TypeFromDir -Dir $dir
                    file = $refFullPath  # Keep full path for matching
                    name = [System.IO.Path]::GetFileNameWithoutExtension($filename)
                }
            }
        }
        
        # Remove duplicates
        $uniqueRefs = @{}
        foreach ($ref in $references) {
            $key = "$($ref.type):$($ref.file)"
            $uniqueRefs[$key] = $ref
        }
        
        $cache.references[$relativePath] = @{
            references = @($uniqueRefs.Values)
            referenced_by = @()
        }
    }
    
    # Third pass: build reverse references
    $refKeys = @($cache.references.Keys)
    foreach ($sourcePath in $refKeys) {
        $entry = $cache.references[$sourcePath]
        if ($null -eq $entry) { continue }
        $refs = $entry.references
        if ($null -eq $refs) { continue }

        foreach ($ref in @($refs)) {
            if ($null -eq $ref) { continue }
            try {
                # Find the target file
                $targetPath = Find-TargetPath -Reference $ref -AllFiles $allFiles
                if ($targetPath -and $cache.references.ContainsKey($targetPath)) {
                    $sourceType = Get-TypeFromPath -Path $sourcePath -Directories $dirs
                    # Extract relative path within the type directory (e.g., "subfolder/file.md" from "commands/subfolder/file.md")
                    $sourceRelativePath = $sourcePath -replace '^[^/]+/', ''

                    # Ensure referenced_by is an array before adding
                    if ($null -eq $cache.references[$targetPath].referenced_by) {
                        $cache.references[$targetPath].referenced_by = @()
                    }
                    $cache.references[$targetPath].referenced_by += @{
                        type = $sourceType
                        file = $sourceRelativePath
                        name = [System.IO.Path]::GetFileNameWithoutExtension($sourceRelativePath)
                    }
                }
            } catch {
                Write-Status "Error processing reference for $($ref.file): $_" -Type Warn
            }
        }
    }
    
    # Save cache
    $cacheFile = Join-Path (Get-CacheLocation) "references.json"
    $cache | ConvertTo-Json -Depth 10 | Set-Content -Path $cacheFile -Force
    
    Write-Status "Reference cache built with $($cache.references.Count) files" -Type Success
    $cache.references.Keys | Where-Object { $_ -like "*write-spec*" } | ForEach-Object { Write-Phosphor "  Cached: $_" -Color Bezel }
    return $cache
}

# Helper: Parse reference (dynamic - extracts type from path)
function Parse-Reference {
    param(
        [string]$LinkPath,
        [string]$CurrentFile,
        [hashtable]$AllFiles
    )

    $filename = Split-Path $LinkPath -Leaf
    $name = [System.IO.Path]::GetFileNameWithoutExtension($filename)

    # Try to extract directory and relative path from the link
    $type = 'unk'  # default unknown
    $relativePath = $filename

    # Match patterns like .bot/prompts/TYPE/subpath/file.md or ../TYPE/subpath/file.md
    if ($LinkPath -match '(?:prompts/)?(\w+)/(.+\.md)$') {
        $dir = $matches[1]
        $type = Get-TypeFromDir -Dir $dir
        $relativePath = $matches[2]
    }
    # If no directory found, try to infer from current file's directory
    elseif ($CurrentFile -match '^([^/]+)/') {
        $type = Get-TypeFromDir -Dir $matches[1]
    }

    return @{
        type = $type
        file = $relativePath
        name = $name
    }
}

# Helper: Get type from directory (generates 3-letter short type)
function Get-TypeFromDir {
    param([string]$Dir)

    # Generate short type from first 3 characters
    return $Dir.Substring(0, [Math]::Min(3, $Dir.Length))
}

# Helper: Get type from path (extracts directory and generates short type)
function Get-TypeFromPath {
    param(
        [string]$Path,
        [string[]]$Directories = @()
    )

    # Extract the first directory component from the path
    if ($Path -match '^([^/]+)/') {
        $dir = $matches[1]
        return Get-TypeFromDir -Dir $dir
    }
    return 'unk'
}

# Helper: Find target path (dynamic - derives directory from short type)
function Find-TargetPath {
    param(
        [hashtable]$Reference,
        [hashtable]$AllFiles
    )

    $shortType = $Reference.type

    # Find matching directory by checking if its short type matches
    $matchingDir = $null
    foreach ($key in $AllFiles.Keys) {
        if ($key -match '^([^/]+)/') {
            $dir = $matches[1]
            if ($dir.Substring(0, [Math]::Min(3, $dir.Length)) -eq $shortType) {
                $matchingDir = $dir
                break
            }
        }
    }

    if ($matchingDir) {
        # Try direct path first
        $targetPath = "$matchingDir/$($Reference.file)"
        if ($AllFiles.ContainsKey($targetPath)) {
            return $targetPath
        }

        # Try with subdirectories
        foreach ($key in $AllFiles.Keys) {
            $escapedFile = [regex]::Escape($Reference.file)
            if ($key -match "^$matchingDir/.*$escapedFile$") {
                return $key
            }
        }
    }

    return $null
}

# Helper: Get current .bot state with caching
function Get-BotState {
    param(
        [DateTime]$IfModifiedSince = [DateTime]::MinValue
    )

    # Check if we have a valid cache and no changes since last build
    $cacheMaxAge = 2  # seconds
    $now = [DateTime]::UtcNow
    $cachedState = Get-CachedState
    $cacheTime = Get-StateCacheTime

    if ($cachedState -and
        ($now - $cacheTime).TotalSeconds -lt $cacheMaxAge -and
        -not (Test-StateChanged -Since $cacheTime)) {

        # Return 304-equivalent marker if client already has this state
        if ($IfModifiedSince -ge $cacheTime) {
            return @{ NotModified = $true; CacheTime = $cacheTime }
        }
        return $cachedState
    }

    # Build fresh state
    $tasksDir = Join-Path $botRoot "state\tasks"
    $sessionsDir = Join-Path $botRoot "state\sessions"
    $stateFile = Join-Path $botRoot ".project-state.json"

    # Count tasks
    $todoTasks = @(Get-ChildItem -Path (Join-Path $tasksDir "todo") -Filter "*.json" -ErrorAction SilentlyContinue)
    $inProgressTasks = @(Get-ChildItem -Path (Join-Path $tasksDir "in-progress") -Filter "*.json" -ErrorAction SilentlyContinue)
    $doneTasks = @(Get-ChildItem -Path (Join-Path $tasksDir "done") -Filter "*.json" -ErrorAction SilentlyContinue)
    $skippedTasks = @(Get-ChildItem -Path (Join-Path $tasksDir "skipped") -Filter "*.json" -ErrorAction SilentlyContinue)
    $cancelledTasks = @(Get-ChildItem -Path (Join-Path $tasksDir "cancelled") -Filter "*.json" -ErrorAction SilentlyContinue)
    
    # Get current task details
    $currentTask = $null
    if ($inProgressTasks.Count -gt 0) {
        $taskContent = Get-Content $inProgressTasks[0].FullName -Raw | ConvertFrom-Json
        $currentTask = @{
            id = $taskContent.id
            name = $taskContent.name
            description = $taskContent.description
            category = $taskContent.category
            priority = $taskContent.priority
            effort = $taskContent.effort
            status = $taskContent.status
            acceptance_criteria = $taskContent.acceptance_criteria
            steps = $taskContent.steps
            dependencies = $taskContent.dependencies
            applicable_agents = $taskContent.applicable_agents
            applicable_standards = $taskContent.applicable_standards
            created_at = $taskContent.created_at
            updated_at = $taskContent.updated_at
            started_at = $taskContent.started_at
        }
    }
    
    # Get recent completed tasks (last 100 for infinite scroll)
    $recentCompleted = @()
    if ($doneTasks.Count -gt 0) {
        $recentCompleted = $doneTasks |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 100 |
            ForEach-Object {
                $taskContent = Get-Content $_.FullName -Raw | ConvertFrom-Json
                @{
                    id = $taskContent.id
                    name = $taskContent.name
                    description = $taskContent.description
                    category = $taskContent.category
                    priority = $taskContent.priority
                    effort = $taskContent.effort
                    status = $taskContent.status
                    acceptance_criteria = $taskContent.acceptance_criteria
                    steps = $taskContent.steps
                    dependencies = $taskContent.dependencies
                    applicable_agents = $taskContent.applicable_agents
                    applicable_standards = $taskContent.applicable_standards
                    created_at = $taskContent.created_at
                    updated_at = $taskContent.updated_at
                    started_at = $taskContent.started_at
                    completed_at = $taskContent.completed_at
                    # Commit info (for completed tasks)
                    commit_sha = $taskContent.commit_sha
                    commit_subject = $taskContent.commit_subject
                    files_created = $taskContent.files_created
                    files_modified = $taskContent.files_modified
                    files_deleted = $taskContent.files_deleted
                    commits = $taskContent.commits
                    # Activity log
                    activity_log = $taskContent.activity_log
                }
            }
    }

    # Get upcoming tasks (up to 100 in priority order for infinite scroll)
    $upcomingTasks = @()
    $totalUpcoming = $todoTasks.Count
    if ($todoTasks.Count -gt 0) {
        $upcomingTasks = $todoTasks |
            ForEach-Object {
                $taskContent = Get-Content $_.FullName -Raw | ConvertFrom-Json
                [PSCustomObject]@{
                    id = $taskContent.id
                    name = $taskContent.name
                    description = $taskContent.description
                    category = $taskContent.category
                    priority = $taskContent.priority
                    effort = $taskContent.effort
                    status = $taskContent.status
                    acceptance_criteria = $taskContent.acceptance_criteria
                    steps = $taskContent.steps
                    dependencies = $taskContent.dependencies
                    applicable_agents = $taskContent.applicable_agents
                    applicable_standards = $taskContent.applicable_standards
                    created_at = $taskContent.created_at
                    updated_at = $taskContent.updated_at
                    priority_num = [int]$taskContent.priority
                }
            } |
            Sort-Object priority_num |
            Select-Object -First 100 |
            ForEach-Object {
                @{
                    id = $_.id
                    name = $_.name
                    description = $_.description
                    category = $_.category
                    priority = $_.priority
                    effort = $_.effort
                    status = $_.status
                    acceptance_criteria = $_.acceptance_criteria
                    steps = $_.steps
                    dependencies = $_.dependencies
                    applicable_agents = $_.applicable_agents
                    applicable_standards = $_.applicable_standards
                    created_at = $_.created_at
                    updated_at = $_.updated_at
                }
            }
    }
    
    # Get session info from MCP tools
    $sessionInfo = $null
    
    # Try to get session state
    $stateResult = Invoke-SessionGetState -Arguments @{}
    if ($stateResult.success) {
        # Get detailed stats
        $statsResult = Invoke-SessionGetStats -Arguments @{}
        
        if ($statsResult.success) {
            $sessionInfo = @{
                session_id = $statsResult.session_id
                session_type = $statsResult.session_type
                status = $statsResult.status
                started_at = $stateResult.state.start_time
                start_time_raw = $stateResult.state.start_time
                tasks_completed = $statsResult.tasks_completed
                tasks_failed = $statsResult.tasks_failed
                tasks_skipped = $statsResult.tasks_skipped
                total_processed = $statsResult.total_processed
                consecutive_failures = $stateResult.state.consecutive_failures
                runtime_hours = $statsResult.runtime_hours
                runtime_minutes = $statsResult.runtime_minutes
                completion_rate = $statsResult.completion_rate
                failure_rate = $statsResult.failure_rate
                skip_rate = $statsResult.skip_rate
                avg_minutes_per_task = $statsResult.avg_minutes_per_task
                auth_method = $statsResult.auth_method
                current_task_id = $statsResult.current_task_id
            }
        } else {
            # Fallback to just state if stats fail
            $sessionInfo = @{
                session_id = $stateResult.state.session_id
                session_type = $stateResult.state.session_type
                status = $stateResult.state.status
                started_at = $stateResult.state.start_time
                start_time_raw = $stateResult.state.start_time
                tasks_completed = $stateResult.state.tasks_completed
                tasks_failed = $stateResult.state.tasks_failed
                tasks_skipped = $stateResult.state.tasks_skipped
                consecutive_failures = $stateResult.state.consecutive_failures
                current_task_id = $stateResult.state.current_task_id
            }
        }
    }
    
    # Check control signals
    $isActuallyRunning = Test-Path (Join-Path $controlDir "running.signal")
    $controlSignals = @{
        pause = Test-Path (Join-Path $controlDir "pause.signal")
        stop = Test-Path (Join-Path $controlDir "stop.signal")
        resume = Test-Path (Join-Path $controlDir "resume.signal")
        running = $isActuallyRunning
    }
    
    # Override session status if running.signal doesn't match session state
    # This handles the case where the loop has stopped but session-state.json wasn't updated
    if ($sessionInfo -and -not $isActuallyRunning) {
        if ($sessionInfo.status -eq 'running') {
            $sessionInfo.status = 'stopped'
        }
    }
    
    $state = @{
        timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        tasks = @{
            todo = $todoTasks.Count
            in_progress = $inProgressTasks.Count
            done = $doneTasks.Count
            skipped = $skippedTasks.Count
            cancelled = $cancelledTasks.Count
            current = $currentTask
            upcoming = @($upcomingTasks)  # Ensure array even with single item
            upcoming_total = if ($todoTasks.Count) { $todoTasks.Count } else { 0 }
            recent_completed = @($recentCompleted)  # Ensure array even with single item
            completed_total = if ($doneTasks.Count) { $doneTasks.Count } else { 0 }
        }
        session = $sessionInfo
        control = $controlSignals
    }

    # Cache the result
    Set-CachedState -State $state

    return $state
}

# Helper: Set control signal
function Set-ControlSignal {
    param([string]$Action)

    # .control is at .bot/.control - server is at .bot/systems/ui
    $controlDir = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) ".control"
    $validActions = @("start", "stop", "pause", "resume", "reset")
    
    if ($Action -notin $validActions) {
        return @{ success = $false; message = "Invalid action: $Action" }
    }
    
    # Ensure control directory exists
    if (-not (Test-Path $controlDir)) {
        New-Item -Path $controlDir -ItemType Directory -Force | Out-Null
    }
    
    # Handle different actions
    switch ($Action) {
        "pause" {
            # Remove resume signal if exists, keep running signal
            $resumeSignal = Join-Path $controlDir "resume.signal"
            if (Test-Path $resumeSignal) { Remove-Item $resumeSignal -Force }
            
            # Create pause signal
            $signalFile = Join-Path $controlDir "pause.signal"
            @{
                action = $Action
                timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            } | ConvertTo-Json | Set-Content -Path $signalFile -Force
        }
        "resume" {
            # Remove pause signal to resume from pause
            $pauseSignal = Join-Path $controlDir "pause.signal"
            if (Test-Path $pauseSignal) { Remove-Item $pauseSignal -Force }
            
            # Also remove stop signal to cancel a pending stop
            $stopSignal = Join-Path $controlDir "stop.signal"
            if (Test-Path $stopSignal) { Remove-Item $stopSignal -Force }
        }
        "stop" {
            # Remove pause signal if exists, keep running signal (it will be removed by the loop)
            $pauseSignal = Join-Path $controlDir "pause.signal"
            if (Test-Path $pauseSignal) { Remove-Item $pauseSignal -Force }
            
            # Create stop signal
            $signalFile = Join-Path $controlDir "stop.signal"
            @{
                action = $Action
                timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            } | ConvertTo-Json | Set-Content -Path $signalFile -Force
        }
        "start" {
            # Start action - launch the autonomous loop in a new PowerShell window
            $scriptPath = Join-Path $botRoot "systems\runtime\run-loop.ps1"
            if (Test-Path $scriptPath) {
                # Check settings for debug mode
                $settingsFile = Join-Path $controlDir "ui-settings.json"
                $showDebug = $false
                $showVerbose = $false
                if (Test-Path $settingsFile) {
                    try {
                        $settings = Get-Content $settingsFile -Raw | ConvertFrom-Json
                        $showDebug = [bool]$settings.showDebug
                        $showVerbose = [bool]$settings.showVerbose
                    } catch {
                        # Ignore settings parse errors
                    }
                }

                # Build arguments
                $args = @("-NoExit", "-File", "`"$scriptPath`"")
                if ($showDebug) { $args += "-ShowDebug" }
                if ($showVerbose) { $args += "-ShowVerbose" }

                # Launch in a new PowerShell window
                Start-Process pwsh -ArgumentList $args -WindowStyle Normal
                Write-Status "Launched autonomous loop in new window (Debug: $showDebug, Verbose: $showVerbose)" -Type Success
            } else {
                Write-Status "Script not found at $scriptPath" -Type Warn
                return @{
                    success = $false
                    message = "Autonomous loop script not found"
                }
            }
        }
        "reset" {
            # Clear all control signals
            $signalFiles = @("running.signal", "stop.signal", "pause.signal", "resume.signal")
            foreach ($signal in $signalFiles) {
                $signalPath = Join-Path $controlDir $signal
                if (Test-Path $signalPath) { Remove-Item $signalPath -Force }
            }

            # Clear session lock
            $lockFile = Join-Path $botRoot "state\sessions\runs\session.lock"
            if (Test-Path $lockFile) { Remove-Item $lockFile -Force }

            # Update session state to stopped
            $stateFile = Join-Path $botRoot "state\sessions\runs\session-state.json"
            if (Test-Path $stateFile) {
                $state = Get-Content $stateFile -Raw | ConvertFrom-Json
                $state.status = "stopped"
                $state.current_task_id = $null
                $state | ConvertTo-Json -Depth 5 | Set-Content $stateFile
            }

            Write-Status "Reset complete - cleared all stale state" -Type Success
        }
    }
    
    return @{ 
        success = $true
        action = $Action
        message = "Signal sent: $Action"
    }
}

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response
        
        $timestamp = Get-Date -Format 'HH:mm:ss'
        $method = $request.HttpMethod
        $url = $request.Url.LocalPath
        
        # Request logging - polling endpoints use single-line overwrite, others get newlines
        $script:requestCount++
        $isPollingEndpoint = $url -in @('/api/state', '/api/activity/tail')
        $logLine = "$($t.Bezel)[$timestamp]$($t.Reset) $($t.Label)$method$($t.Reset) $($t.Cyan)$url$($t.Reset) $($t.Bezel)(#$script:requestCount)$($t.Reset)"
        
        if ($isPollingEndpoint) {
            $clearPad = ' ' * [Math]::Max(0, 70 - (Get-VisualWidth $logLine))
            Write-Host "`r$logLine$clearPad" -NoNewline
        } else {
            Write-Host ""
            Write-Host $logLine
        }
        
        # Route handler
        $statusCode = 200
        $contentType = "text/html; charset=utf-8"
        $content = ""
        
        try {
            Write-Verbose "Processing URL: $url"
            switch ($url) {
                "/" {
                    $indexPath = Join-Path $staticRoot "index.html"
                    if (Test-Path $indexPath) {
                        $content = Get-Content $indexPath -Raw
                    } else {
                        $statusCode = 404
                        $content = "index.html not found"
                    }
                    break
                }

                "/api/info" {
                    $contentType = "application/json; charset=utf-8"
                    $projectName = Split-Path -Leaf $projectRoot
                    
                    # Try to extract executive summary from product docs (in priority order)
                    $executiveSummary = $null
                    $productDir = Join-Path $botRoot "state\product"
                    if (Test-Path $productDir) {
                        # Priority order for scanning
                        $priorityFiles = @('overview.md', 'mission.md', 'roadmap.md', 'roadmap-overview.md')
                        $allFiles = @(Get-ChildItem -Path $productDir -Filter "*.md" -ErrorAction SilentlyContinue)
                        
                        # Build ordered list: priority files first, then rest
                        $orderedFiles = @()
                        foreach ($pf in $priorityFiles) {
                            $match = $allFiles | Where-Object { $_.Name -eq $pf }
                            if ($match) { $orderedFiles += $match }
                        }
                        # Add remaining files not in priority list
                        foreach ($f in $allFiles) {
                            if ($f.Name -notin $priorityFiles) { $orderedFiles += $f }
                        }
                        
                        foreach ($file in $orderedFiles) {
                            $docContent = Get-Content -Path $file.FullName -Raw
                            # Look for "## Executive Summary" or "# Executive Summary" section
                            if ($docContent -match '##? Executive Summary\s*\r?\n+\s*([^\r\n#]+)') {
                                $executiveSummary = $matches[1].Trim()
                                break
                            }
                        }
                    }
                    
                    $content = @{
                        project_name = $projectName
                        project_root = $projectRoot
                        full_path = $projectRoot
                        executive_summary = $executiveSummary
                    } | ConvertTo-Json -Compress
                    break
                }

                "/api/product/list" {
                    $contentType = "application/json; charset=utf-8"
                    $productDir = Join-Path $botRoot "state\product"
                    $docs = @()
                    if (Test-Path $productDir) {
                        $mdFiles = @(Get-ChildItem -Path $productDir -Filter "*.md" -ErrorAction SilentlyContinue)

                        # Define priority order for product files
                        $priorityOrder = [System.Collections.Generic.List[string]]@(
                            'mission',
                            'entity-model',
                            'tech-stack',
                            'roadmap',
                            'roadmap-overview'
                        )

                        # Separate files into priority and non-priority
                        $priorityFiles = [System.Collections.ArrayList]@()
                        $otherFiles = [System.Collections.ArrayList]@()

                        foreach ($file in $mdFiles) {
                            if ($null -eq $file) { continue }
                            $priorityIndex = $priorityOrder.IndexOf($file.BaseName)
                            if ($priorityIndex -ge 0) {
                                [void]$priorityFiles.Add([PSCustomObject]@{
                                    File = $file
                                    Priority = $priorityIndex
                                })
                            } else {
                                [void]$otherFiles.Add($file)
                            }
                        }

                        # Sort priority files by their priority index
                        if ($priorityFiles.Count -gt 0) {
                            $priorityFiles = @($priorityFiles | Sort-Object -Property Priority)
                        }

                        # Sort other files alphabetically
                        if ($otherFiles.Count -gt 0) {
                            $otherFiles = @($otherFiles | Sort-Object -Property BaseName)
                        }

                        # Build final docs array: priority first, then alphabetical
                        foreach ($pf in $priorityFiles) {
                            if ($null -eq $pf) { continue }
                            $docs += @{
                                name = $pf.File.BaseName
                                filename = $pf.File.Name
                            }
                        }
                        foreach ($file in $otherFiles) {
                            if ($null -eq $file) { continue }
                            $docs += @{
                                name = $file.BaseName
                                filename = $file.Name
                            }
                        }
                    }
                    $content = @{ docs = $docs } | ConvertTo-Json -Depth 5 -Compress
                    break
                }

                "/api/commands/list" {
                    $contentType = "application/json; charset=utf-8"
                    $content = Get-BotDirectoryList -Directory "commands"
                    break
                }

                "/api/workflows/list" {
                    $contentType = "application/json; charset=utf-8"
                    $content = Get-BotDirectoryList -Directory "workflows"
                    break
                }

                "/api/agents/list" {
                    $contentType = "application/json; charset=utf-8"
                    $content = Get-BotDirectoryList -Directory "agents"
                    break
                }

                "/api/standards/list" {
                    $contentType = "application/json; charset=utf-8"
                    $content = Get-BotDirectoryList -Directory "standards"
                    break
                }

                "/api/prompts/directories" {
                    $contentType = "application/json; charset=utf-8"
                    $promptsDir = Join-Path $botRoot "prompts"
                    $directories = @()

                    if (Test-Path $promptsDir) {
                        $directories = @(Get-ChildItem -Path $promptsDir -Directory | ForEach-Object {
                            $name = $_.Name
                            $shortType = $name.Substring(0, [Math]::Min(3, $name.Length))
                            $itemCount = @(Get-ChildItem -Path $_.FullName -Filter "*.md" -Recurse -ErrorAction SilentlyContinue |
                                Where-Object { $_.FullName -notmatch '\\archived\\' }).Count
                            @{
                                name = $name
                                displayName = (Get-Culture).TextInfo.ToTitleCase($name)
                                shortType = $shortType
                                itemCount = $itemCount
                            }
                        })
                    }

                    $content = @{ directories = $directories } | ConvertTo-Json -Depth 5 -Compress
                    break
                }

                # Generic handler for any prompts directory list (skills, agents, workflows, etc.)
                { $_ -match "^/api/(\w+)/list$" } {
                    $contentType = "application/json; charset=utf-8"
                    # Re-match to ensure $matches is properly populated in this scope
                    if ($url -match "^/api/(\w+)/list$") {
                        $dirName = $Matches[1]
                    } else {
                        $dirName = "unknown"
                    }
                    $dirPath = Join-Path $botRoot "prompts\$dirName"

                    if (Test-Path $dirPath) {
                        $content = Get-BotDirectoryList -Directory $dirName
                    } else {
                        $statusCode = 404
                        $content = @{
                            success = $false
                            error = "Directory not found: $dirName"
                        } | ConvertTo-Json -Compress
                    }
                    break
                }

                { $_ -like "/api/product/*" -and $_ -ne "/api/product/list" } {
                    $contentType = "application/json; charset=utf-8"
                    $docName = $url -replace "^/api/product/", ""
                    $productDir = Join-Path $botRoot "state\product"
                    $docPath = Join-Path $productDir "$docName.md"
                    
                    if (Test-Path $docPath) {
                        $docContent = Get-Content -Path $docPath -Raw
                        $content = @{
                            success = $true
                            name = $docName
                            content = $docContent
                        } | ConvertTo-Json -Depth 5 -Compress
                    } else {
                        $statusCode = 404
                        $content = @{
                            success = $false
                            error = "Document not found: $docName"
                        } | ConvertTo-Json -Compress
                    }
                    break
                }

                { $_ -like "/api/file/*" } {
                    $contentType = "application/json; charset=utf-8"
                    $pathParts = ($url -replace "^/api/file/", "") -split '/', 2
                    if ($pathParts.Count -eq 2) {
                        $type = $pathParts[0]
                        $filename = [System.Web.HttpUtility]::UrlDecode($pathParts[1])
                        $content = Get-FileWithReferences -Type $type -Filename $filename
                    } else {
                        $statusCode = 400
                        $content = @{
                            success = $false
                            error = "Invalid file path"
                        } | ConvertTo-Json -Compress
                    }
                    break
                }

                "/api/cache/clear" {
                    if ($method -eq "POST") {
                        $contentType = "application/json; charset=utf-8"
                        Clear-ReferenceCache
                        $content = @{
                            success = $true
                            message = "Cache cleared"
                        } | ConvertTo-Json -Compress
                    } else {
                        $statusCode = 405
                        $content = "Method not allowed"
                    }
                    break
                }

                "/api/theme" {
                    $contentType = "application/json; charset=utf-8"
                    $themePath = Join-Path $staticRoot "theme-config.json"
                    $defaultPath = Join-Path $staticRoot "theme-config.default.json"

                    # Copy default if config doesn't exist
                    if (-not (Test-Path $themePath) -and (Test-Path $defaultPath)) {
                        Copy-Item $defaultPath $themePath
                    }

                    if ($method -eq "GET") {
                        if (Test-Path $themePath) {
                            $content = Get-Content $themePath -Raw
                        } else {
                            $statusCode = 404
                            $content = @{
                                success = $false
                                error = "Theme config not found"
                            } | ConvertTo-Json -Compress
                        }
                    }
                    elseif ($method -eq "POST") {
                        try {
                            $reader = New-Object System.IO.StreamReader($request.InputStream)
                            $body = $reader.ReadToEnd() | ConvertFrom-Json
                            $reader.Close()

                            $config = Get-Content $themePath -Raw | ConvertFrom-Json

                            if ($body.preset -and $config.presets.($body.preset)) {
                                # Apply preset
                                $preset = $config.presets.($body.preset)
                                foreach ($key in $preset.PSObject.Properties.Name) {
                                    if ($key -eq "name") {
                                        $config.name = $preset.$key
                                    } else {
                                        $rgb = $preset.$key
                                        $config.mappings.$key = @{ r = $rgb[0]; g = $rgb[1]; b = $rgb[2] }
                                    }
                                }
                            }

                            $config | ConvertTo-Json -Depth 5 | Set-Content $themePath
                            $content = $config | ConvertTo-Json -Depth 5 -Compress
                        } catch {
                            $statusCode = 500
                            $content = @{
                                success = $false
                                error = "Failed to update theme: $($_.Exception.Message)"
                            } | ConvertTo-Json -Compress
                        }
                    }
                    else {
                        $statusCode = 405
                        $content = "Method not allowed"
                    }
                    break
                }

                "/api/settings" {
                    $contentType = "application/json; charset=utf-8"
                    $settingsFile = Join-Path $controlDir "ui-settings.json"

                    # Default settings
                    $defaultSettings = @{
                        showDebug = $false
                        showVerbose = $false
                    }

                    if ($method -eq "GET") {
                        if (Test-Path $settingsFile) {
                            try {
                                $settings = Get-Content $settingsFile -Raw | ConvertFrom-Json
                                $content = $settings | ConvertTo-Json -Compress
                            } catch {
                                $content = $defaultSettings | ConvertTo-Json -Compress
                            }
                        } else {
                            $content = $defaultSettings | ConvertTo-Json -Compress
                        }
                    }
                    elseif ($method -eq "POST") {
                        try {
                            $reader = New-Object System.IO.StreamReader($request.InputStream)
                            $body = $reader.ReadToEnd() | ConvertFrom-Json
                            $reader.Close()

                            # Load existing settings or use defaults
                            $settings = $defaultSettings
                            if (Test-Path $settingsFile) {
                                try {
                                    $settings = Get-Content $settingsFile -Raw | ConvertFrom-Json
                                } catch { }
                            }

                            # Update settings with provided values
                            if ($null -ne $body.showDebug) {
                                $settings.showDebug = [bool]$body.showDebug
                            }
                            if ($null -ne $body.showVerbose) {
                                $settings.showVerbose = [bool]$body.showVerbose
                            }

                            # Save settings
                            $settings | ConvertTo-Json | Set-Content $settingsFile -Force
                            $content = @{
                                success = $true
                                settings = $settings
                            } | ConvertTo-Json -Compress

                            Write-Status "Settings updated: Debug=$($settings.showDebug), Verbose=$($settings.showVerbose)" -Type Success
                        } catch {
                            $statusCode = 500
                            $content = @{
                                success = $false
                                error = "Failed to update settings: $($_.Exception.Message)"
                            } | ConvertTo-Json -Compress
                        }
                    }
                    else {
                        $statusCode = 405
                        $content = "Method not allowed"
                    }
                    break
                }

                "/api/state/poll" {
                    # Long-polling endpoint for reduced overhead
                    $contentType = "application/json; charset=utf-8"

                    # Parse timeout and last-seen timestamp
                    $timeout = if ($request.QueryString["timeout"]) {
                        [int]$request.QueryString["timeout"]
                    } else {
                        30000  # 30 seconds default
                    }

                    $lastSeen = if ($request.QueryString["since"]) {
                        try {
                            [DateTime]::Parse($request.QueryString["since"])
                        } catch {
                            [DateTime]::MinValue
                        }
                    } else {
                        [DateTime]::MinValue
                    }

                    # Wait for changes with timeout
                    $deadline = [DateTime]::UtcNow.AddMilliseconds($timeout)
                    $pollInterval = 100  # Check every 100ms

                    $state = $null
                    while ([DateTime]::UtcNow -lt $deadline) {
                        if (Test-StateChanged -Since $lastSeen) {
                            $state = Get-BotState
                            break
                        }
                        Start-Sleep -Milliseconds $pollInterval
                    }

                    # Timeout - return current state anyway
                    if (-not $state) {
                        $state = Get-BotState
                        $state.timeout = $true
                    }

                    $state.polled_at = [DateTime]::UtcNow.ToString("o")
                    $content = $state | ConvertTo-Json -Depth 10 -Compress
                    break
                }

                "/api/state" {
                    $contentType = "application/json; charset=utf-8"
                    $content = Get-BotState | ConvertTo-Json -Depth 10 -Compress
                    break
                }

                "/api/control" {
                    if ($method -eq "POST") {
                        $contentType = "application/json; charset=utf-8"
                        $reader = New-Object System.IO.StreamReader($request.InputStream)
                        $body = $reader.ReadToEnd()
                        $reader.Close()

                        $data = $body | ConvertFrom-Json
                        $result = Set-ControlSignal -Action $data.action
                        $content = $result | ConvertTo-Json -Compress
                    } else {
                        $statusCode = 405
                        $content = "Method not allowed"
                    }
                    break
                }

                "/api/activity/tail" {
                    $contentType = "application/json; charset=utf-8"
                    $position = if ($request.QueryString["position"]) { 
                        [long]$request.QueryString["position"] 
                    } else { 
                        0L 
                    }
                    $tailLines = if ($request.QueryString["tail"]) {
                        [int]$request.QueryString["tail"]
                    } else {
                        0
                    }
                    
                    $logPath = Join-Path $botRoot ".control\activity.jsonl"
                    
                    if (-not (Test-Path $logPath)) {
                        # Return empty if no log yet
                        $content = @{events = @(); position = 0} | ConvertTo-Json -Compress
                    } else {
                        try {
                            # If tail is requested (initial load), read last N lines
                            if ($tailLines -gt 0 -and $position -eq 0) {
                                $allLines = Get-Content -Path $logPath -Tail $tailLines -ErrorAction SilentlyContinue
                                $events = @()
                                foreach ($line in $allLines) {
                                    if ($line) {
                                        try {
                                            $events += ($line | ConvertFrom-Json)
                                        } catch {
                                            # Skip malformed lines
                                        }
                                    }
                                }
                                # Set position to end of file for subsequent polls
                                $fileInfo = Get-Item $logPath
                                $newPosition = $fileInfo.Length
                                
                                $content = @{
                                    events = $events
                                    position = $newPosition
                                } | ConvertTo-Json -Depth 10 -Compress
                            } else {
                                # Normal streaming from position
                                $stream = [System.IO.File]::OpenRead($logPath)
                                $stream.Seek($position, 'Begin') | Out-Null
                                $reader = [System.IO.StreamReader]::new($stream)
                                
                                $events = @()
                                while (-not $reader.EndOfStream) {
                                    $line = $reader.ReadLine()
                                    if ($line) {
                                        try {
                                            $events += ($line | ConvertFrom-Json)
                                        } catch {
                                            # Skip malformed lines
                                        }
                                    }
                                }
                                
                                $newPosition = $stream.Position
                                $reader.Close()
                                $stream.Close()
                                
                                $content = @{
                                    events = $events
                                    position = $newPosition
                                } | ConvertTo-Json -Depth 10 -Compress
                            }
                        } catch {
                            $content = @{
                                events = @()
                                position = 0
                                error = "Failed to read activity log: $_"
                            } | ConvertTo-Json -Compress
                        }
                    }
                    break
                }

                default {
                    # Serve static files
                    $filePath = Join-Path $staticRoot $url.TrimStart('/')
                    
                    if (Test-Path -LiteralPath $filePath -PathType Leaf) {
                        $extension = [System.IO.Path]::GetExtension($filePath)
                        $contentType = switch ($extension) {
                            ".html" { "text/html; charset=utf-8" }
                            ".css" { "text/css; charset=utf-8" }
                            ".js" { "application/javascript; charset=utf-8" }
                            ".json" { "application/json; charset=utf-8" }
                            default { "application/octet-stream" }
                        }
                        $content = Get-Content -LiteralPath $filePath -Raw
                    } else {
                        $statusCode = 404
                        $content = "Not found: $url"
                    }
                }
            }
        } catch {
            $statusCode = 500
            $content = "Server error: $($_.Exception.Message)"
            Write-Host ""
            Write-Status "[$timestamp] ERROR: $($_.Exception.Message)" -Type Error
            Write-Host "  Script: $($_.InvocationInfo.ScriptName)" -ForegroundColor Red
            Write-Host "  Line: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
            Write-Host "  Statement: $($_.InvocationInfo.Line.Trim())" -ForegroundColor Red
        }
        
        # Send response
        $response.StatusCode = $statusCode
        $response.ContentType = $contentType
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($content)
        $response.ContentLength64 = $buffer.Length
        $response.OutputStream.Write($buffer, 0, $buffer.Length)
        $response.Close()
    }
} finally {
    # Stop file watchers
    try {
        Stop-FileWatchers
    } catch {
        # Ignore watcher disposal errors
    }

    # Safely stop listener if it's still running
    if ($listener -and $listener.IsListening) {
        try {
            $listener.Stop()
            $listener.Close()
        } catch {
            # Ignore disposal errors
        }
    }
    Write-Status "Server stopped" -Type Warn
}
