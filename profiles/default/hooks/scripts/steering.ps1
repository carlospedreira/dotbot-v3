#!/usr/bin/env pwsh
<#
.SYNOPSIS
Operator helper script for the steering channel.

.DESCRIPTION
Send whispers to running DOTBOT sessions and monitor their status.

.EXAMPLE
.\steering.ps1 whisper -SessionId "2026-02-05T06-35-10Z" -Message "Focus on tests" -Priority normal

.EXAMPLE
.\steering.ps1 status

.EXAMPLE
.\steering.ps1 watch

.EXAMPLE
.\steering.ps1 abort -SessionId "2026-02-05T06-35-10Z"
#>

param(
    [Parameter(Position = 0)]
    [ValidateSet('whisper', 'status', 'watch', 'list', 'abort', 'history')]
    [string]$Command = 'status',

    [Parameter()]
    [string]$SessionId,

    [Parameter()]
    [Alias('m')]
    [string]$Message,

    [Parameter()]
    [ValidateSet('normal', 'urgent', 'abort')]
    [string]$Priority = 'normal'
)

# Import theme for consistent output
$themePath = Join-Path $PSScriptRoot "..\..\systems\runtime\modules\DotBotTheme.psm1"
if (Test-Path $themePath) {
    Import-Module $themePath -Force
    $t = Get-DotBotTheme
} else {
    # Fallback if theme not available
    $t = @{
        Primary = ''; Success = ''; Error = ''; Warning = ''; Muted = ''; Reset = ''
    }
}

$controlDir = Join-Path $PSScriptRoot "..\..\..\.control"
$controlDir = [System.IO.Path]::GetFullPath($controlDir)
$whisperFile = Join-Path $controlDir "whisper.jsonl"
$statusFile = Join-Path $controlDir "steering-status.json"
$runningSignal = Join-Path $controlDir "running.signal"

function Send-Whisper {
    param(
        [Parameter(Mandatory)]
        [string]$SessionId,
        [Parameter(Mandatory)]
        [string]$Message,
        [ValidateSet('normal', 'urgent', 'abort')]
        [string]$Priority = 'normal'
    )

    if (-not (Test-Path $controlDir)) {
        New-Item -ItemType Directory -Path $controlDir -Force | Out-Null
    }

    $whisper = @{
        instance_id = $SessionId
        instruction = $Message
        priority = $Priority
        timestamp = (Get-Date).ToUniversalTime().ToString("o")
    } | ConvertTo-Json -Compress

    Add-Content -Path $whisperFile -Value $whisper -Encoding utf8NoBOM

    Write-Host "$($t.Success)✓$($t.Reset) Whisper sent to $($t.Primary)$SessionId$($t.Reset)"
    Write-Host "  $($t.Muted)Priority:$($t.Reset) $Priority"
    Write-Host "  $($t.Muted)Message:$($t.Reset) $Message"
}

function Get-SteeringStatus {
    if (-not (Test-Path $statusFile)) {
        Write-Host "$($t.Warning)⚠$($t.Reset) No steering status file found"
        Write-Host "  $($t.Muted)Either no session is running or it hasn't posted status yet.$($t.Reset)"
        return
    }

    try {
        $status = Get-Content $statusFile -Raw | ConvertFrom-Json
        $updatedAt = [DateTime]::Parse($status.updated_at)
        $age = (Get-Date).ToUniversalTime() - $updatedAt
        $ageStr = if ($age.TotalMinutes -lt 1) { "$([int]$age.TotalSeconds)s ago" }
                  elseif ($age.TotalHours -lt 1) { "$([int]$age.TotalMinutes)m ago" }
                  else { "$([int]$age.TotalHours)h ago" }

        Write-Host ""
        Write-Host "$($t.Primary)╭─ Steering Status ─────────────────────╮$($t.Reset)"
        Write-Host "$($t.Primary)│$($t.Reset) $($t.Muted)Session:$($t.Reset)     $($status.session_id)"
        Write-Host "$($t.Primary)│$($t.Reset) $($t.Muted)Status:$($t.Reset)      $($status.status)"
        if ($status.next_action) {
            Write-Host "$($t.Primary)│$($t.Reset) $($t.Muted)Next:$($t.Reset)        $($status.next_action)"
        }
        Write-Host "$($t.Primary)│$($t.Reset) $($t.Muted)Updated:$($t.Reset)     $ageStr"
        Write-Host "$($t.Primary)│$($t.Reset) $($t.Muted)Whisper Idx:$($t.Reset) $($status.last_whisper_index)"
        Write-Host "$($t.Primary)╰────────────────────────────────────────╯$($t.Reset)"
        Write-Host ""
    } catch {
        Write-Host "$($t.Error)✗$($t.Reset) Failed to read status: $_"
    }
}

function Watch-SteeringStatus {
    Write-Host "$($t.Primary)Watching steering status...$($t.Reset) (Ctrl+C to stop)"
    Write-Host ""

    $lastContent = ""
    while ($true) {
        if (Test-Path $statusFile) {
            $content = Get-Content $statusFile -Raw
            if ($content -ne $lastContent) {
                Clear-Host
                Write-Host "$($t.Muted)$(Get-Date -Format 'HH:mm:ss')$($t.Reset) Steering status updated"
                Get-SteeringStatus
                $lastContent = $content
            }
        }
        Start-Sleep -Milliseconds 500
    }
}

function Get-RunningSessions {
    Write-Host ""
    Write-Host "$($t.Primary)Running Sessions$($t.Reset)"
    Write-Host "$($t.Muted)────────────────────────────────────────$($t.Reset)"

    if (Test-Path $runningSignal) {
        try {
            $signal = Get-Content $runningSignal -Raw | ConvertFrom-Json
            Write-Host "$($t.Success)●$($t.Reset) $($signal.session_id)"
            Write-Host "  $($t.Muted)Type:$($t.Reset) $($signal.session_type)"
            Write-Host "  $($t.Muted)Started:$($t.Reset) $($signal.started_at)"
        } catch {
            Write-Host "$($t.Warning)⚠$($t.Reset) Could not parse running.signal"
        }
    } else {
        Write-Host "$($t.Muted)No running sessions detected$($t.Reset)"
    }
    Write-Host ""
}

function Send-Abort {
    param(
        [Parameter(Mandatory)]
        [string]$SessionId
    )

    Send-Whisper -SessionId $SessionId -Message "ABORT: Commit any work in progress and exit gracefully." -Priority "abort"
    Write-Host ""
    Write-Host "$($t.Warning)⚠$($t.Reset) Abort signal sent. Session should commit WIP and exit."
}

function Get-WhisperHistory {
    Write-Host ""
    Write-Host "$($t.Primary)Whisper History$($t.Reset)"
    Write-Host "$($t.Muted)────────────────────────────────────────$($t.Reset)"

    if (-not (Test-Path $whisperFile)) {
        Write-Host "$($t.Muted)No whispers recorded yet.$($t.Reset)"
        return
    }

    $lines = Get-Content $whisperFile -Encoding utf8
    $index = 0
    foreach ($line in $lines) {
        if ($line.Trim()) {
            $index++
            try {
                $whisper = $line | ConvertFrom-Json
                $ts = [DateTime]::Parse($whisper.timestamp).ToLocalTime().ToString("HH:mm:ss")
                $priorityColor = switch ($whisper.priority) {
                    'urgent' { $t.Warning }
                    'abort' { $t.Error }
                    default { $t.Muted }
                }
                Write-Host "$($t.Muted)[$index]$($t.Reset) $ts $priorityColor[$($whisper.priority)]$($t.Reset) → $($whisper.instance_id)"
                Write-Host "     $($whisper.instruction)"
            } catch {
                Write-Host "$($t.Muted)[$index]$($t.Reset) $($t.Error)(malformed)$($t.Reset)"
            }
        }
    }
    Write-Host ""
}

# Main command dispatch
switch ($Command) {
    'whisper' {
        if (-not $SessionId) {
            # Try to get session from running.signal
            if (Test-Path $runningSignal) {
                try {
                    $signal = Get-Content $runningSignal -Raw | ConvertFrom-Json
                    $SessionId = $signal.session_id
                    Write-Host "$($t.Muted)Using session from running.signal: $SessionId$($t.Reset)"
                } catch {
                    Write-Host "$($t.Error)✗$($t.Reset) -SessionId required (no running session detected)"
                    exit 1
                }
            } else {
                Write-Host "$($t.Error)✗$($t.Reset) -SessionId required (no running session detected)"
                exit 1
            }
        }
        if (-not $Message) {
            Write-Host "$($t.Error)✗$($t.Reset) -Message required"
            exit 1
        }
        Send-Whisper -SessionId $SessionId -Message $Message -Priority $Priority
    }
    'status' {
        Get-SteeringStatus
    }
    'watch' {
        Watch-SteeringStatus
    }
    'list' {
        Get-RunningSessions
    }
    'abort' {
        if (-not $SessionId) {
            # Try to get session from running.signal
            if (Test-Path $runningSignal) {
                try {
                    $signal = Get-Content $runningSignal -Raw | ConvertFrom-Json
                    $SessionId = $signal.session_id
                    Write-Host "$($t.Muted)Using session from running.signal: $SessionId$($t.Reset)"
                } catch {
                    Write-Host "$($t.Error)✗$($t.Reset) -SessionId required (no running session detected)"
                    exit 1
                }
            } else {
                Write-Host "$($t.Error)✗$($t.Reset) -SessionId required (no running session detected)"
                exit 1
            }
        }
        Send-Abort -SessionId $SessionId
    }
    'history' {
        Get-WhisperHistory
    }
}
