# Stop-Dev.ps1
# Stops all Flux dev environment processes

param()

. "$PSScriptRoot/Common.ps1"

$repoRoot = Invoke-InProjectRoot

Write-Host ""
Write-Host "Stopping Flux Development Environment" -ForegroundColor White
Write-Host "======================================" -ForegroundColor White
Write-Host ""

# Read saved PIDs from Start-Dev.ps1
$pidFile = Join-Path $repoRoot ".bot\.dev-pids.json"
$savedPids = $null
if (Test-Path $pidFile) {
    try {
        $savedPids = Get-Content $pidFile -Raw | ConvertFrom-Json
        Write-Status "Found saved PIDs from Start-Dev.ps1" -Type Info
    } catch {
        Write-Status "Could not read PID file" -Type Warning
    }
}

# Stop only the processes we explicitly started (tracked in PID file)
$stoppedCount = 0

if ($savedPids) {
    # Stop Chrome window if we started it
    if ($savedPids.chrome_pid) {
        $chromeProcess = Get-Process -Id $savedPids.chrome_pid -ErrorAction SilentlyContinue
        if ($chromeProcess) {
            $chromeProcess | Stop-Process -Force -ErrorAction SilentlyContinue
            $stoppedCount++
            Write-Status "Closed Chrome window (PID: $($savedPids.chrome_pid))" -Type Success
        } else {
            Write-Status "Chrome window already closed" -Type Neutral
        }
    }
    
    # Stop Aspire PowerShell window and its entire process tree
    if ($savedPids.aspire_pid) {
        $aspireProcess = Get-Process -Id $savedPids.aspire_pid -ErrorAction SilentlyContinue
        if ($aspireProcess) {
            # Use taskkill with /T to kill the entire process tree (pwsh + dotnet + children)
            $result = & taskkill /T /F /PID $savedPids.aspire_pid 2>&1
            $stoppedCount++
            Write-Status "Stopped Aspire process tree (PID: $($savedPids.aspire_pid))" -Type Success
        } else {
            Write-Status "Aspire window already closed" -Type Neutral
        }
    }
    
    # Legacy: Stop dotnet processes if using old PID format
    if ($savedPids.dotnet_pids -and $savedPids.dotnet_pids.Count -gt 0) {
        foreach ($procId in $savedPids.dotnet_pids) {
            $proc = Get-Process -Id $procId -ErrorAction SilentlyContinue
            if ($proc) {
                $proc | Stop-Process -Force -ErrorAction SilentlyContinue
                $stoppedCount++
            }
        }
        Write-Status "Stopped dotnet processes ($($savedPids.dotnet_pids.Count) tracked)" -Type Success
    }
    
    # Legacy: Stop the background job if using old PID format
    if ($savedPids.job_id) {
        $job = Get-Job -Id $savedPids.job_id -ErrorAction SilentlyContinue
        if ($job) {
            Stop-Job -Job $job -ErrorAction SilentlyContinue
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
            Write-Status "Stopped background job (ID: $($savedPids.job_id))" -Type Success
        }
    }
} else {
    Write-Status "No PID file found - nothing to stop" -Type Warning
    Write-Status "If processes are still running, stop them manually" -Type Info
}

# Clean up PID file
if (Test-Path $pidFile) {
    Remove-Item $pidFile -Force
    Write-Status "Cleaned up PID file" -Type Neutral
}

# Note: Docker containers are not stopped - they run independently
# Use 'docker compose down' in the docker/ directory if needed

Write-Host ""
Write-Status "All Flux processes stopped" -Type Success
Write-Host ""

# Return status for MCP tool consumption
return @{
    status = "stopped"
}
