<#
.SYNOPSIS
Control signal, whisper, and activity log API module

.DESCRIPTION
Provides control signal management (start/stop/pause/resume/reset),
operator whisper channel, and activity log tail streaming.
Extracted from server.ps1 for modularity.
#>

$script:Config = @{
    ControlDir = $null
    ProcessesDir = $null
    BotRoot = $null
}

function Initialize-ControlAPI {
    param(
        [Parameter(Mandatory)] [string]$ControlDir,
        [Parameter(Mandatory)] [string]$ProcessesDir,
        [Parameter(Mandatory)] [string]$BotRoot
    )
    $script:Config.ControlDir = $ControlDir
    $script:Config.ProcessesDir = $ProcessesDir
    $script:Config.BotRoot = $BotRoot
}

function Set-ControlSignal {
    param(
        [string]$Action,
        [string]$Mode = "execution"  # "execution", "analysis", or "both"
    )

    $controlDir = $script:Config.ControlDir
    $processesDir = $script:Config.ProcessesDir
    $botRoot = $script:Config.BotRoot
    $validActions = @("start", "stop", "pause", "resume", "reset")
    $validModes = @("execution", "analysis", "both")

    if ($Action -notin $validActions) {
        return @{ success = $false; message = "Invalid action: $Action" }
    }

    if ($Mode -and $Mode -notin $validModes) {
        $Mode = "execution"  # Default to execution if invalid
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

            # Remove all stop signals to cancel a pending stop
            $stopSignal = Join-Path $controlDir "stop.signal"
            $stopAnalysisSignal = Join-Path $controlDir "stop-analysis.signal"
            $stopExecutionSignal = Join-Path $controlDir "stop-execution.signal"
            if (Test-Path $stopSignal) { Remove-Item $stopSignal -Force }
            if (Test-Path $stopAnalysisSignal) { Remove-Item $stopAnalysisSignal -Force }
            if (Test-Path $stopExecutionSignal) { Remove-Item $stopExecutionSignal -Force }
        }
        "stop" {
            # Remove pause signal if exists
            $pauseSignal = Join-Path $controlDir "pause.signal"
            if (Test-Path $pauseSignal) { Remove-Item $pauseSignal -Force }

            # Create loop-specific stop signals for legacy loops
            $signalContent = @{
                action = $Action
                timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            } | ConvertTo-Json

            $stopAnalysisSignal = Join-Path $controlDir "stop-analysis.signal"
            $signalContent | Set-Content -Path $stopAnalysisSignal -Force

            $stopExecutionSignal = Join-Path $controlDir "stop-execution.signal"
            $signalContent | Set-Content -Path $stopExecutionSignal -Force

            # Also create stop files for all running processes in registry
            if (Test-Path $processesDir) {
                $procFiles = Get-ChildItem -Path $processesDir -Filter "*.json" -File -ErrorAction SilentlyContinue
                foreach ($pf in $procFiles) {
                    try {
                        $proc = Get-Content $pf.FullName -Raw | ConvertFrom-Json
                        if ($proc.status -eq 'running') {
                            $stopFile = Join-Path $processesDir "$($proc.id).stop"
                            "stop" | Set-Content -Path $stopFile -Force
                        }
                    } catch {}
                }
            }
        }
        "start" {
            # Start action - launch process(es) via unified launcher
            $launcherPath = Join-Path $botRoot "systems\runtime\launch-process.ps1"

            if (-not (Test-Path $launcherPath)) {
                return @{ success = $false; message = "Launcher script not found" }
            }

            # Check settings for debug mode and model selection
            $settingsFile = Join-Path $controlDir "ui-settings.json"
            $showDebug = $false
            $showVerbose = $false
            $analysisModel = "Opus"
            $executionModel = "Opus"
            if (Test-Path $settingsFile) {
                try {
                    $uiSettings = Get-Content $settingsFile -Raw | ConvertFrom-Json
                    $showDebug = [bool]$uiSettings.showDebug
                    $showVerbose = [bool]$uiSettings.showVerbose
                    if ($uiSettings.analysisModel) { $analysisModel = $uiSettings.analysisModel }
                    if ($uiSettings.executionModel) { $executionModel = $uiSettings.executionModel }
                } catch {}
            }

            $launched = @()

            # Launch analysis process if mode is "analysis" or "both"
            if ($Mode -in @("analysis", "both")) {
                $args = @("-NoExit", "-File", "`"$launcherPath`"", "-Type", "analysis", "-Continue", "-Model", $analysisModel)
                if ($showDebug) { $args += "-ShowDebug" }
                if ($showVerbose) { $args += "-ShowVerbose" }
                Start-Process pwsh -ArgumentList $args -WindowStyle Normal
                $launched += "analysis"
                Write-Status "Launched analysis process with model: $analysisModel" -Type Success
            }

            # Launch execution process if mode is "execution" or "both"
            if ($Mode -in @("execution", "both")) {
                $args = @("-NoExit", "-File", "`"$launcherPath`"", "-Type", "execution", "-Continue", "-Model", $executionModel)
                if ($showDebug) { $args += "-ShowDebug" }
                if ($showVerbose) { $args += "-ShowVerbose" }
                Start-Process pwsh -ArgumentList $args -WindowStyle Normal
                $launched += "execution"
                Write-Status "Launched execution process with model: $executionModel" -Type Success
            }

            if ($launched.Count -eq 0) {
                return @{ success = $false; message = "No processes launched" }
            }

            return @{
                success = $true
                action = $Action
                mode = $Mode
                launched = $launched
                message = "Launched: $($launched -join ', ')"
            }
        }
        "reset" {
            # Clear all control signals
            $signalFiles = @("running.signal", "stop.signal", "stop-analysis.signal", "stop-execution.signal", "pause.signal", "resume.signal", "analysing.signal")
            foreach ($signal in $signalFiles) {
                $signalPath = Join-Path $controlDir $signal
                if (Test-Path $signalPath) { Remove-Item $signalPath -Force }
            }

            # Clear session lock
            $lockFile = Join-Path $botRoot "workspace\sessions\runs\session.lock"
            if (Test-Path $lockFile) { Remove-Item $lockFile -Force }

            # Update session state to stopped
            $stateFile = Join-Path $botRoot "workspace\sessions\runs\session-state.json"
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

function Send-Whisper {
    param(
        [string]$InstanceType,
        [string]$Message,
        [string]$Priority = "normal"
    )
    $controlDir = $script:Config.ControlDir

    # Get signal file for this instance type
    $signalFile = if ($InstanceType -eq "analysis") {
        Join-Path $controlDir "analysing.signal"
    } else {
        Join-Path $controlDir "running.signal"
    }

    if (-not (Test-Path $signalFile)) {
        return @{ success = $false; error = "No $InstanceType instance running" }
    }

    $signal = Get-Content $signalFile -Raw | ConvertFrom-Json

    # Append whisper with instance targeting
    $whisperFile = Join-Path $controlDir "whisper.jsonl"
    $whisper = @{
        instance_id = $signal.session_id
        instance_type = $InstanceType
        instruction = $Message
        priority = $Priority
        timestamp = (Get-Date).ToUniversalTime().ToString("o")
    } | ConvertTo-Json -Compress

    Add-Content -Path $whisperFile -Value $whisper -Encoding utf8NoBOM
    Write-Status "Whisper sent to $InstanceType instance" -Type Success

    return @{
        success = $true
        session_id = $signal.session_id
        instance_type = $InstanceType
        instance_id = $signal.instance_id
    }
}

function Get-ActivityTail {
    param(
        [long]$Position = 0,
        [int]$TailLines = 0
    )
    $botRoot = $script:Config.BotRoot
    $logPath = Join-Path $botRoot ".control\activity.jsonl"

    if (-not (Test-Path $logPath)) {
        return @{ events = @(); position = 0 }
    }

    try {
        # If tail is requested (initial load), read last N lines
        if ($TailLines -gt 0 -and $Position -eq 0) {
            $stream = [System.IO.FileStream]::new(
                $logPath,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read,
                [System.IO.FileShare]::ReadWrite
            )
            $reader = [System.IO.StreamReader]::new($stream)
            $allText = $reader.ReadToEnd()
            $newPosition = $stream.Position
            $reader.Close()
            $stream.Close()
            $allLines = ($allText -split "`n") | Where-Object { $_.Trim() } | Select-Object -Last $TailLines
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

            return @{
                events = $events
                position = $newPosition
            }
        } else {
            # Normal streaming from position
            $stream = [System.IO.FileStream]::new(
                $logPath,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read,
                [System.IO.FileShare]::ReadWrite
            )
            $stream.Seek($Position, 'Begin') | Out-Null
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

            return @{
                events = $events
                position = $newPosition
            }
        }
    } catch {
        return @{
            events = @()
            position = 0
            error = "Failed to read activity log: $_"
        }
    }
}

Export-ModuleMember -Function @(
    'Initialize-ControlAPI',
    'Set-ControlSignal',
    'Send-Whisper',
    'Get-ActivityTail'
)
