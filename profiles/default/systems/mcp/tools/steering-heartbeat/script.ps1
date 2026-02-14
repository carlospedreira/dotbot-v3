function Invoke-SteeringHeartbeat {
    <#
    .SYNOPSIS
    Post status and check for whispers from the operator.

    .DESCRIPTION
    Bidirectional communication channel for autonomous sessions.
    - Updates process registry (or legacy signal file) with current status
    - Returns any new whispers addressed to this process/session
    - Tracks whisper index to only return new whispers

    Supports two modes:
    - Process mode (process_id provided): reads/writes processes/{id}.json and .whisper.jsonl
    - Legacy mode (instance_type provided): reads/writes running.signal or analysing.signal
    #>
    param(
        [hashtable]$Arguments
    )

    $sessionId = $Arguments['session_id']
    $instanceType = $Arguments['instance_type']  # "analysis" or "execution" (legacy)
    $processId = $Arguments['process_id']        # Process registry ID (new)
    $status = $Arguments['status']
    $nextAction = $Arguments['next_action']

    if (-not $sessionId) {
        return @{
            success = $false
            error = "session_id is required"
        }
    }

    if (-not $processId -and -not $instanceType) {
        return @{
            success = $false
            error = "Either process_id or instance_type is required"
        }
    }

    if (-not $status) {
        return @{
            success = $false
            error = "status is required"
        }
    }

    $controlDir = Join-Path $PSScriptRoot "..\..\..\..\.control"
    $controlDir = [System.IO.Path]::GetFullPath($controlDir)

    # Ensure control directory exists
    if (-not (Test-Path $controlDir)) {
        New-Item -ItemType Directory -Path $controlDir -Force | Out-Null
    }

    # --- Process Registry Mode ---
    if ($processId) {
        $processesDir = Join-Path $controlDir "processes"
        $processFile = Join-Path $processesDir "$processId.json"
        $whisperFile = Join-Path $processesDir "$processId.whisper.jsonl"

        if (-not (Test-Path $processFile)) {
            return @{
                success = $false
                error = "Process file not found: $processId"
            }
        }

        # Read existing process data
        $lastWhisperIndex = 0
        try {
            $processData = Get-Content $processFile -Raw -ErrorAction Stop | ConvertFrom-Json
            if ($null -ne $processData.last_whisper_index) {
                $lastWhisperIndex = $processData.last_whisper_index
            }
        } catch {
            return @{
                success = $false
                error = "Failed to read process file: $_"
            }
        }

        # Read whispers for this process
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
                                $whispers += @{
                                    instruction = $w.instruction
                                    priority = $w.priority
                                    timestamp = $w.timestamp
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

        # Update process file with heartbeat info (atomic write)
        $processData.last_heartbeat = (Get-Date).ToUniversalTime().ToString("o")
        $processData.last_whisper_index = $currentIndex
        $processData.heartbeat_status = $status
        $processData.heartbeat_next_action = if ($nextAction) { $nextAction } else { $null }

        try {
            $tempFile = "$processFile.tmp"
            $processData | ConvertTo-Json -Depth 10 | Set-Content -Path $tempFile -Encoding utf8NoBOM -NoNewline
            Move-Item -Path $tempFile -Destination $processFile -Force
        } catch {
            return @{
                success = $false
                error = "Failed to write process file: $_"
            }
        }

        # Also update legacy signal file for backward compat with Overview tab
        if ($instanceType) {
            $signalFile = if ($instanceType -eq "analysis") {
                Join-Path $controlDir "analysing.signal"
            } else {
                Join-Path $controlDir "running.signal"
            }

            try {
                $signalObj = @{
                    session_id = $sessionId
                    instance_id = $processId
                    pid = $PID
                    started_at = $processData.started_at
                    last_heartbeat = (Get-Date).ToUniversalTime().ToString("o")
                    last_whisper_index = $currentIndex
                    status = $status
                    next_action = if ($nextAction) { $nextAction } else { $null }
                }
                $tempSignal = "$signalFile.tmp"
                $signalObj | ConvertTo-Json -Depth 10 | Set-Content -Path $tempSignal -Encoding utf8NoBOM -NoNewline
                Move-Item -Path $tempSignal -Destination $signalFile -Force
            } catch {
                # Non-critical - process registry is the source of truth
            }
        }

        return @{
            success = $true
            process_id = $processId
            whispers = $whispers
            whisper_count = $whispers.Count
        }
    }

    # --- Legacy Signal File Mode ---
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
