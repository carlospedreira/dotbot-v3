<#
.SYNOPSIS
Cleanup utilities for temporary Claude directories and sessions

.DESCRIPTION
Provides functions for cleaning up temporary directories and session data
created during Claude sessions
#>

function Clear-TemporaryClaudeDirectories {
    <#
    .SYNOPSIS
    Remove temporary Claude directories from the project root

    .PARAMETER ProjectRoot
    Path to the project root directory

    .OUTPUTS
    Integer count of directories removed
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    $tmpClaudeDirs = Get-ChildItem -Path $ProjectRoot -Filter "tmpclaude-*-cwd" -ErrorAction SilentlyContinue

    if ($tmpClaudeDirs) {
        $count = $tmpClaudeDirs.Count
        foreach ($dir in $tmpClaudeDirs) {
            Remove-Item -Path $dir.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
        return $count
    }

    return 0
}

function Get-ClaudeProjectDir {
    <#
    .SYNOPSIS
    Get the Claude projects directory for a given project root

    .PARAMETER ProjectRoot
    Path to the project root directory

    .OUTPUTS
    Path to the Claude projects directory, or $null if not found
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    # Claude stores sessions in ~/.claude/projects/{project-hash}/
    # Project hash is derived from project path with drive letter and slashes replaced
    $fullPath = [System.IO.Path]::GetFullPath($ProjectRoot)

    # Convert path to hash format: C:\Users\foo -> C--Users-foo
    $projectHash = $fullPath -replace ':', '-' -replace '\\', '-' -replace '/', '-'

    $claudeProjectDir = Join-Path $env:USERPROFILE ".claude\projects\$projectHash"

    if (Test-Path $claudeProjectDir) {
        return $claudeProjectDir
    }

    return $null
}

function Remove-ClaudeSession {
    <#
    .SYNOPSIS
    Remove a specific Claude session's data

    .PARAMETER SessionId
    The session ID (GUID) to remove

    .PARAMETER ProjectRoot
    Path to the project root directory

    .OUTPUTS
    $true if session was removed, $false otherwise
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$SessionId,

        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    if (-not $SessionId) { return $false }

    $claudeProjectDir = Get-ClaudeProjectDir -ProjectRoot $ProjectRoot

    if (-not $claudeProjectDir) { return $false }

    $removed = $false

    # Remove session folder (tool results)
    $sessionFolder = Join-Path $claudeProjectDir $SessionId
    if (Test-Path $sessionFolder) {
        Remove-Item $sessionFolder -Recurse -Force -ErrorAction SilentlyContinue
        $removed = $true
    }

    # Remove session .jsonl file
    $sessionFile = Join-Path $claudeProjectDir "$SessionId.jsonl"
    if (Test-Path $sessionFile) {
        Remove-Item $sessionFile -Force -ErrorAction SilentlyContinue
        $removed = $true
    }

    return $removed
}

function Clear-OldClaudeSessions {
    <#
    .SYNOPSIS
    Remove old Claude session data (older than specified days)

    .PARAMETER ProjectRoot
    Path to the project root directory

    .PARAMETER MaxAgeDays
    Maximum age in days before sessions are cleaned up (default: 7)

    .OUTPUTS
    Integer count of sessions removed
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,

        [Parameter(Mandatory = $false)]
        [int]$MaxAgeDays = 7
    )

    $claudeProjectDir = Get-ClaudeProjectDir -ProjectRoot $ProjectRoot

    if (-not $claudeProjectDir) { return 0 }

    $cutoff = (Get-Date).AddDays(-$MaxAgeDays)
    $removed = 0

    # Clean old .jsonl files (but not sessions-index.json)
    Get-ChildItem $claudeProjectDir -Filter "*.jsonl" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne "sessions-index.json" -and $_.LastWriteTime -lt $cutoff } |
        ForEach-Object {
            Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
            $removed++
        }

    # Clean old session folders (GUID pattern)
    Get-ChildItem $claudeProjectDir -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' -and $_.LastWriteTime -lt $cutoff } |
        ForEach-Object {
            Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
            $removed++
        }

    return $removed
}
