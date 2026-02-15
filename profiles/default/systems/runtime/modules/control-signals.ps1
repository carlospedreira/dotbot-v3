<#
.SYNOPSIS
Control signal handling for autonomous loop management

.DESCRIPTION
Provides functions for checking and responding to control signals:
- stop.signal: Halt the autonomous loop
- pause.signal: Temporarily pause execution

Uses FileSystemWatcher for event-driven signal detection to reduce disk I/O.
#>

# Script-scoped signal state with watcher
$script:SignalState = @{
    StopPending = $false
    PausePending = $false
    ResumePending = $false
    Watcher = $null
    ControlDir = $null
    LastCheck = [DateTime]::MinValue
    Initialized = $false
}

function Initialize-ControlSignalWatcher {
    <#
    .SYNOPSIS
    Initialize FileSystemWatcher for control signals

    .PARAMETER ControlDir
    Path to the control directory containing signal files
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ControlDir
    )

    if ($script:SignalState.Initialized -and $script:SignalState.ControlDir -eq $ControlDir) {
        return
    }

    # Ensure control directory exists
    if (-not (Test-Path $ControlDir)) {
        New-Item -Path $ControlDir -ItemType Directory -Force | Out-Null
    }

    # Stop existing watcher if any
    if ($script:SignalState.Watcher) {
        try {
            $script:SignalState.Watcher.EnableRaisingEvents = $false
            $script:SignalState.Watcher.Dispose()
        } catch {}
    }

    try {
        $watcher = New-Object System.IO.FileSystemWatcher
        $watcher.Path = $ControlDir
        $watcher.Filter = "*.signal"
        $watcher.NotifyFilter = [System.IO.NotifyFilters]::FileName
        $watcher.InternalBufferSize = 32768
        $watcher.EnableRaisingEvents = $true

        $updateState = {
            $dir = $Event.SourceEventArgs.FullPath | Split-Path -Parent
            # Check for any stop signal (generic or loop-specific)
            $script:SignalState.StopPending = (Test-Path (Join-Path $dir "stop.signal")) -or
                                               (Test-Path (Join-Path $dir "stop-analysis.signal")) -or
                                               (Test-Path (Join-Path $dir "stop-execution.signal"))
            $script:SignalState.PausePending = Test-Path (Join-Path $dir "pause.signal")
            $script:SignalState.ResumePending = Test-Path (Join-Path $dir "resume.signal")
            $script:SignalState.LastCheck = [DateTime]::UtcNow
        }

        Register-ObjectEvent -InputObject $watcher -EventName Created -Action $updateState | Out-Null
        Register-ObjectEvent -InputObject $watcher -EventName Deleted -Action $updateState | Out-Null

        $script:SignalState.Watcher = $watcher
        $script:SignalState.ControlDir = $ControlDir
        $script:SignalState.Initialized = $true

        # Initialize current state - check for any stop signal (generic or loop-specific)
        $script:SignalState.StopPending = (Test-Path (Join-Path $ControlDir "stop.signal")) -or
                                           (Test-Path (Join-Path $ControlDir "stop-analysis.signal")) -or
                                           (Test-Path (Join-Path $ControlDir "stop-execution.signal"))
        $script:SignalState.PausePending = Test-Path (Join-Path $ControlDir "pause.signal")
        $script:SignalState.ResumePending = Test-Path (Join-Path $ControlDir "resume.signal")
        $script:SignalState.LastCheck = [DateTime]::UtcNow

    } catch {
        Write-Warning "[control-signals] Failed to create FileSystemWatcher: $_"
        $script:SignalState.Initialized = $false
    }
}

function Test-ControlSignals {
    <#
    .SYNOPSIS
    Check for control signals in the control directory

    .PARAMETER ControlDir
    Path to the control directory containing signal files

    .PARAMETER LoopType
    Optional loop type ('analysis' or 'execution') to check loop-specific stop signals.
    If specified, checks for stop-{LoopType}.signal instead of stop.signal.
    For backward compatibility, also checks generic stop.signal if no LoopType specified.

    .OUTPUTS
    String indicating signal type ('stop', 'pause', or $null)
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ControlDir,

        [Parameter(Mandatory = $false)]
        [ValidateSet('analysis', 'execution')]
        [string]$LoopType
    )

    # Always check disk directly - FileSystemWatcher events don't reliably
    # update script-scoped variables across runspaces

    # Check for stop signal - use loop-specific if LoopType provided
    if ($LoopType) {
        # Check loop-specific stop signal
        if (Test-Path (Join-Path $ControlDir "stop-$LoopType.signal")) { return 'stop' }
    } else {
        # Backward compatibility: check generic stop.signal
        if (Test-Path (Join-Path $ControlDir "stop.signal")) { return 'stop' }
    }

    if (Test-Path (Join-Path $ControlDir "pause.signal")) { return 'pause' }

    return $null
}

function Stop-ControlSignalWatcher {
    <#
    .SYNOPSIS
    Stop and dispose of the FileSystemWatcher
    #>
    if ($script:SignalState.Watcher) {
        try {
            $script:SignalState.Watcher.EnableRaisingEvents = $false
            $script:SignalState.Watcher.Dispose()
        } catch {}
        $script:SignalState.Watcher = $null
    }
    $script:SignalState.Initialized = $false
}

