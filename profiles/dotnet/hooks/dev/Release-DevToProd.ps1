# Release-DevToProd.ps1
# Loads .env.local and starts the Lintilla API in Release mode for local prod testing

param()

. "$PSScriptRoot/Common.ps1"

$repoRoot = Invoke-InProjectRoot

Write-Host ""
Write-Host "Lintilla - Local Release Mode" -ForegroundColor White
Write-Host "==============================" -ForegroundColor White
Write-Host ""

# Load environment variables
$envFile = Join-Path $repoRoot ".env.local"
if (Test-Path $envFile) {
    Write-Status "Loading .env.local file" -Type Info
    try {
        $envVars = Load-EnvFile -Path $envFile -Export
        Write-Status "Loaded $($envVars.Count) environment variables" -Type Success
    }
    catch {
        Write-Status "Failed to load .env.local: $_" -Type Error
        exit 1
    }
}
else {
    Write-Status ".env.local file not found" -Type Warning
    Write-Status "Copy .env.example to .env.local and configure your settings" -Type Info
}

Write-Host ""

# Stop any existing processes first (makes this idempotent)
& "$PSScriptRoot\Stop-Dev.ps1" -Quiet

# Verify API project exists
$apiProjectPath = Join-Path $repoRoot "src\Lintilla.Api\Lintilla.Api.csproj"
if (-not (Test-Path $apiProjectPath)) {
    Write-Status "API project not found at: $apiProjectPath" -Type Error
    exit 1
}

# Ensure logs directory exists
$logsDir = Join-Path $repoRoot "logs"
if (-not (Test-Path $logsDir)) {
    New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
}

# Ensure data directory exists (for SQLite)
$dataDir = Join-Path $repoRoot "data"
if (-not (Test-Path $dataDir)) {
    New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
}

Write-Status "Starting Lintilla API in Release mode..." -Type Info
Write-Status "Serilog writes JSON logs to: logs/lintilla-*.log" -Type Info

# Build the startup command that loads env vars and runs the API in Release mode
$commonScript = Join-Path $PSScriptRoot "Common.ps1"
$startupCommand = @"
. '$commonScript'
`$envFile = '$envFile'
if (Test-Path `$envFile) {
    Load-EnvFile -Path `$envFile -Export | Out-Null
}
Set-Location '$repoRoot'
dotnet run --project src/Lintilla.Api/Lintilla.Api.csproj --configuration Release
"@

# Start API in a visible window with colored output
# Note: Serilog file sink handles persistent logging - no need to tee console
$apiProcess = Start-Process -FilePath "pwsh" -ArgumentList @(
    "-NoExit",
    "-Command",
    $startupCommand
) -PassThru

Write-Status "API window opened (PID: $($apiProcess.Id))" -Type Success

# Wait for health endpoint (up to 30 seconds)
$apiUrl = "http://localhost:5232"
$healthUrl = "$apiUrl/health"
$timeout = 30
$elapsed = 0

Write-Status "Waiting for API to start..." -Type Info

while ($elapsed -lt $timeout) {
    try {
        $response = Invoke-WebRequest -Uri $healthUrl -Method GET -TimeoutSec 2 -ErrorAction SilentlyContinue
        if ($response.StatusCode -eq 200) {
            break
        }
    }
    catch {
        # API not ready yet
    }
    
    # Check if process exited
    if ($apiProcess.HasExited) {
        Write-Status "API process ended unexpectedly - check the API window for errors" -Type Error
        exit 1
    }
    
    Start-Sleep -Milliseconds 500
    $elapsed += 0.5
}

if ($elapsed -ge $timeout) {
    Write-Status "Timed out waiting for API (may still be starting)" -Type Warning
} else {
    Write-Status "API is healthy" -Type Success
}

# Save PID to a file so Stop-Dev.ps1 can clean up
$pidFile = Join-Path $repoRoot ".bot\.dev-pids.json"
$pids = @{
    api_pid = $apiProcess.Id
    started_at = (Get-Date).ToString('o')
}
$pids | ConvertTo-Json | Set-Content $pidFile -Force

Write-Host ""
Write-Host "  API:     $apiUrl (Release mode)" -ForegroundColor Cyan
Write-Host "  Health:  $healthUrl" -ForegroundColor Gray
Write-Host "  Logs:    $logsDir\lintilla-*.log" -ForegroundColor Gray
Write-Host ""
Write-Host "  Use 'dev_stop' MCP tool or run Stop-Dev.ps1 to stop" -ForegroundColor Gray
Write-Host ""

# Return status for MCP tool consumption
return @{
    api_url = $apiUrl
    status = "running"
    pid = $apiProcess.Id
    configuration = "Release"
}
