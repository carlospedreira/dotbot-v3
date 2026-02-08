function Invoke-SteeringHeartbeat {
    <#
    .SYNOPSIS
    Post status and check for whispers from the operator.

    .DESCRIPTION
    Bidirectional communication channel for autonomous sessions.
    - Updates signal file (running.signal or analysing.signal) with current status
    - Returns any new whispers addressed to this session/instance
    - Tracks whisper index to only return new whispers
    #>
    param(
        [hashtable]$Arguments
    )

    $sessionId = $Arguments['session_id']
    $instanceType = $Arguments['instance_type']  # "analysis" or "execution"
    $status = $Arguments['status']
    $nextAction = $Arguments['next_action']

    if (-not $sessionId) {
        return @{
            success = $false
            error = "session_id is required"
        }
    }

    if (-not $instanceType) {
        return @{
            success = $false
            error = "instance_type is required"
        }
    }

    if (-not $status) {
        return @{
            success = $false
            error = "status is required"
        }
    }

    $controlDir = Join-Path $PSScriptRoot "..\..\..\..\..\.control"
    $controlDir = [System.IO.Path]::GetFullPath($controlDir)

    # Ensure control directory exists
    if (-not (Test-Path $controlDir)) {
        New-Item -ItemType Directory -Path $controlDir -Force | Out-Null
    }

    # Determine signal file based on instance type
    $signalFile = if ($instanceType -eq "analysis") {
        Join-Path $controlDir "analysing.signal"
    } else {
        Join-Path $controlDir "running.signal"
    }

    $whisperFile = Join-Path $controlDir "whisper.jsonl"

    # Read existing signal to preserve instance_id and get whisper index
    $instanceId = "$instanceType-$([guid]::NewGuid().ToString().Substring(0,6))"
    $lastWhisperIndex = 0
    $startedAt = (Get-Date).ToUniversalTime().ToString("o")

    if (Test-Path $signalFile) {
        try {
            $existing = Get-Content $signalFile -Raw -ErrorAction Stop | ConvertFrom-Json
            if ($existing.instance_id) { $instanceId = $existing.instance_id }
            if ($existing.started_at) { $startedAt = $existing.started_at }
            if ($null -ne $existing.last_whisper_index) { $lastWhisperIndex = $existing.last_whisper_index }
        } catch {
            # Signal file corrupted or unreadable, start fresh
        }
    }

    # Read whispers for this instance
    $whispers = @()
    $currentIndex = 0

    if (Test-Path $whisperFile) {
        try {
            $lines = Get-Content -Path $whisperFile -Encoding utf8 -ErrorAction Stop
            foreach ($line in $lines) {
                if ($line.Trim()) {
                    $currentIndex++
                    if ($currentIndex -gt $lastWhisperIndex) {
                        try {
                            $w = $line | ConvertFrom-Json -ErrorAction Stop
                            # Match: same session AND (no instance_type OR matching instance_type)
                            $sessionMatch = ($w.instance_id -eq $sessionId) -or ($w.session_id -eq $sessionId)
                            $instanceMatch = (-not $w.instance_type) -or ($w.instance_type -eq $instanceType)
                            if ($sessionMatch -and $instanceMatch) {
                                $whispers += @{
                                    instruction = $w.instruction
                                    priority = $w.priority
                                    timestamp = $w.timestamp
                                }
                            }
                        } catch {
                            # Skip malformed whisper lines
                        }
                    }
                }
            }
        } catch {
            # Whisper file doesn't exist or is empty - that's fine
        }
    }

    # Update signal file with heartbeat info (atomic write)
    $signalObj = @{
        session_id = $sessionId
        instance_id = $instanceId
        pid = $PID
        started_at = $startedAt
        last_heartbeat = (Get-Date).ToUniversalTime().ToString("o")
        last_whisper_index = $currentIndex
        status = $status
        next_action = if ($nextAction) { $nextAction } else { $null }
    }

    try {
        $tempFile = "$signalFile.tmp"
        $signalObj | ConvertTo-Json -Depth 10 | Set-Content -Path $tempFile -Encoding utf8NoBOM -NoNewline
        Move-Item -Path $tempFile -Destination $signalFile -Force
    } catch {
        return @{
            success = $false
            error = "Failed to write signal file: $_"
        }
    }

    return @{
        success = $true
        instance_id = $instanceId
        whispers = $whispers
        whisper_count = $whispers.Count
    }
}
