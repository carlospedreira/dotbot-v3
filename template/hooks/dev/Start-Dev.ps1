# Start-Dev.ps1
# Loads .env and starts (or restarts) the Aspire dev environment

param(
    [switch]$NoBrowser
)

. "$PSScriptRoot/Common.ps1"

$repoRoot = Invoke-InProjectRoot

Write-Host ""
Write-Host "Flux Development Environment" -ForegroundColor White
Write-Host "=============================" -ForegroundColor White
Write-Host ""

# Load environment variables
$envFile = Join-Path $repoRoot ".env"
if (Test-Path $envFile) {
    Write-Status "Loading .env file" -Type Info
    try {
        $envVars = Load-EnvFile -Path $envFile -Export
        Write-Status "Loaded $($envVars.Count) environment variables" -Type Success
    }
    catch {
        Write-Status "Failed to load .env: $_" -Type Error
        exit 1
    }
}
else {
    Write-Status ".env file not found - using defaults" -Type Warning
    Write-Status "Copy .env.example to .env and configure your settings" -Type Info
}

Write-Host ""

# Stop any existing processes first (makes this idempotent)
& "$PSScriptRoot\Stop-Dev.ps1" | Out-Null

Write-Host ""

# Start Aspire AppHost
$appHostPath = Join-Path $repoRoot "src\Flux.AppHost"

if (-not (Test-Path $appHostPath)) {
    Write-Status "AppHost not found at: $appHostPath" -Type Error
    exit 1
}

Write-Status "Starting Aspire AppHost..." -Type Info

# Ensure logs directory exists and clean up old log
$logsDir = Join-Path $repoRoot "logs"
if (-not (Test-Path $logsDir)) {
    New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
}
$aspireLogFile = Join-Path $logsDir "aspire-dev.log"
if (Test-Path $aspireLogFile) {
    Remove-Item $aspireLogFile -Force
}

# Start Aspire in a visible window, tee output to log file
$aspireProcess = Start-Process -FilePath "pwsh" -ArgumentList @(
    "-NoExit",
    "-Command",
    "Set-Location '$appHostPath'; dotnet run 2>&1 | Tee-Object -FilePath '$aspireLogFile'"
) -PassThru

Write-Status "Aspire window opened (PID: $($aspireProcess.Id))" -Type Success

# Wait for the login URL to appear in the log file (up to 60 seconds)
$dashboardUrl = $null
$timeout = 60
$elapsed = 0

Write-Status "Waiting for Aspire to start..." -Type Info

while ($elapsed -lt $timeout) {
    if (Test-Path $aspireLogFile) {
        $content = Get-Content $aspireLogFile -Raw -ErrorAction SilentlyContinue
        if ($content -match 'Login to the dashboard at (https://[^\s]+)') {
            $dashboardUrl = $matches[1]
            break
        }
    }
    
    # Check if process exited
    if ($aspireProcess.HasExited) {
        Write-Status "Aspire process ended unexpectedly" -Type Error
        if (Test-Path $aspireLogFile) {
            Write-Host (Get-Content $aspireLogFile -Raw)
        }
        exit 1
    }
    
    Start-Sleep -Milliseconds 500
    $elapsed += 0.5
}

if (-not $dashboardUrl) {
    Write-Status "Timed out waiting for dashboard URL (Aspire may still be starting)" -Type Warning
    $dashboardUrl = "https://localhost:7252"
}

Write-Host ""
Write-Status "Aspire AppHost started" -Type Success

# Open Chrome with the dashboard URL (unless -NoBrowser specified)
$chromeProcess = $null
if (-not $NoBrowser) {
    Write-Status "Opening dashboard in Chrome..." -Type Info
    
    # Try to find Chrome
    $chromePath = @(
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    
    if ($chromePath) {
        $chromeDataDir = Join-Path $repoRoot ".bot\.chrome-dev"
        $chromeProcess = Start-Process -FilePath $chromePath -ArgumentList @(
            "--user-data-dir=`"$chromeDataDir`"",
            "--ignore-certificate-errors",
            "--new-window",
            $dashboardUrl
        ) -PassThru
        Write-Status "Chrome opened (PID: $($chromeProcess.Id))" -Type Success
    } else {
        # Fallback to default browser
        Start-Process $dashboardUrl
        Write-Status "Opened in default browser" -Type Success
    }
}

# Save PIDs to a file so Stop-Dev.ps1 can clean up
$pidFile = Join-Path $repoRoot ".bot\.dev-pids.json"
$pids = @{
    aspire_pid = $aspireProcess.Id
    chrome_pid = if ($chromeProcess) { $chromeProcess.Id } else { $null }
    started_at = (Get-Date).ToString('o')
}
$pids | ConvertTo-Json | Set-Content $pidFile -Force

Write-Host ""
Write-Host "  Dashboard: $dashboardUrl" -ForegroundColor Cyan
Write-Host "  API:       https://localhost:7001 (via Aspire)" -ForegroundColor Gray
Write-Host ""
Write-Host "  Run '.bot\dev-scripts\Stop-Dev.ps1' to stop" -ForegroundColor Gray
Write-Host ""

# Return the URL for MCP tool consumption
return @{
    dashboard_url = $dashboardUrl
    status = "running"
    chrome_pid = if ($chromeProcess) { $chromeProcess.Id } else { $null }
}
