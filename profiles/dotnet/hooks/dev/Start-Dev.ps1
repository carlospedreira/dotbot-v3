# Start-Dev.ps1
# Loads .env.local and starts the Lintilla development environment

param(
    [switch]$NoLayout
)

. "$PSScriptRoot/Common.ps1"
Import-Module "$PSScriptRoot/DevLayout.psm1" -Force -DisableNameChecking

$repoRoot = Invoke-InProjectRoot

Write-Host ""
Write-Host "Lintilla Development Environment" -ForegroundColor White
Write-Host "=================================" -ForegroundColor White
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

# API settings
$apiUrl = "http://localhost:5232"
$healthUrl = "$apiUrl/health"

# Open dev layout (which starts the API via dotnet watch)
$layoutResult = $null
$layoutConfigPath = Join-Path $PSScriptRoot "layout.json"
if (-not $NoLayout -and (Test-Path $layoutConfigPath)) {
    $layoutConfig = Get-Content $layoutConfigPath -Raw | ConvertFrom-Json
    if ($layoutConfig.enabled) {
        Write-Status "Opening dev layout..." -Type Info
        $layoutResult = Open-DevLayout `
            -Monitor $layoutConfig.monitor `
            -Layout $layoutConfig.layout `
            -Terminals $layoutConfig.terminals `
            -Urls $layoutConfig.urls `
            -SessionName $layoutConfig.sessionName
        
        if ($layoutResult.status -eq "running") {
            Write-Status "Layout opened: $($layoutResult.terminals) terminal(s), $($layoutResult.browsers) browser(s)" -Type Success
        }
    }
}

if ($NoLayout -or -not $layoutResult) {
    Write-Status "No layout - starting API directly..." -Type Info
    Write-Status "Serilog writes JSON logs to: logs/lintilla-*.log" -Type Info
    
    # Build the startup command that loads env vars and runs the API
    $commonScript = Join-Path $PSScriptRoot "Common.ps1"
    $startupCommand = @"
. '$commonScript'
`$envFile = '$envFile'
if (Test-Path `$envFile) {
    Load-EnvFile -Path `$envFile -Export | Out-Null
}
Set-Location '$repoRoot'
dotnet watch --project src/Lintilla.Api/Lintilla.Api.csproj
"@
    
    # Start API in a visible window
    $apiProcess = Start-Process -FilePath "pwsh" -ArgumentList @(
        "-NoExit",
        "-Command",
        $startupCommand
    ) -PassThru
    
    Write-Status "API window opened (PID: $($apiProcess.Id))" -Type Success
    
    # Save PID for cleanup
    $pidFile = Join-Path $repoRoot ".bot\.dev-pids.json"
    $pids = @{
        api_pid = $apiProcess.Id
        started_at = (Get-Date).ToString('o')
    }
    $pids | ConvertTo-Json | Set-Content $pidFile -Force
}

# Wait for health endpoint (up to 30 seconds)
Write-Host ""
Write-Status "Waiting for API to start..." -Type Info

$timeout = 30
$elapsed = 0
$healthCheckPassed = $false

# Get the API process PID (either from layout or direct start)
$apiPid = $null
if ($layoutResult) {
    # Layout started the API - read PID from session file
    $sessionFile = Join-Path $env:TEMP "devlayout-$($layoutConfig.sessionName).json"
    if (Test-Path $sessionFile) {
        $session = Get-Content $sessionFile -Raw | ConvertFrom-Json
        # The terminal running dotnet watch - we need to check if it's alive
        if ($session.terminals -and $session.terminals.Count -gt 0) {
            # We'll check the window handle instead
        }
    }
} else {
    $apiPid = $apiProcess.Id
}

# Helper function to check if API port is listening
function Test-ApiPortListening {
    param([int]$Port = 5232)
    $listener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    return $null -ne $listener
}

$portWasListening = $false

while ($elapsed -lt $timeout) {
    # Check if port 5232 is listening (most reliable indicator)
    $isListening = Test-ApiPortListening -Port 5232
    if ($isListening) {
        $portWasListening = $true
    } elseif ($portWasListening) {
        # Port was listening but stopped - app crashed after starting
        Write-Status "API stopped listening (app may have crashed)" -Type Error
        break
    }
    
    try {
        $response = Invoke-WebRequest -Uri $healthUrl -Method GET -TimeoutSec 2 -ErrorAction SilentlyContinue
        if ($response.StatusCode -eq 200) {
            $healthCheckPassed = $true
            break
        }
    }
    catch {
        # API not ready yet
    }
    Start-Sleep -Milliseconds 500
    $elapsed += 0.5
}

# Determine final status
$finalStatus = "running"
if ($healthCheckPassed) {
    Write-Status "API is healthy" -Type Success
    
    # Refresh browser windows now that API is ready
    if ($layoutResult -and $layoutConfig.sessionName) {
        $refreshResult = Send-BrowserRefresh -SessionName $layoutConfig.sessionName -Quiet
        if ($refreshResult.count -gt 0) {
            Write-Status "Refreshed $($refreshResult.count) browser window(s)" -Type Success
        }
    }
} else {
    # Health check failed - determine why
    $isListening = Test-ApiPortListening -Port 5232
    if ($portWasListening -and -not $isListening) {
        $finalStatus = "failed"
        Write-Status "API crashed after starting" -Type Error
        Write-Status "Check logs at: $logsDir\lintilla-*.log" -Type Info
    } elseif (-not $portWasListening) {
        $finalStatus = "failed"
        Write-Status "API never started listening on port 5232" -Type Error
        Write-Status "Check the terminal window for build/startup errors" -Type Info
    } else {
        # Port is listening but health check failed
        $finalStatus = "starting"
        Write-Status "API is listening but health check timed out" -Type Warning
        Write-Status "Check logs for errors: $logsDir\lintilla-*.log" -Type Info
    }
}

Write-Host ""
Write-Host "  API:     $apiUrl" -ForegroundColor Cyan
Write-Host "  Health:  $healthUrl" -ForegroundColor Gray
Write-Host "  Logs:    $logsDir\lintilla-*.log" -ForegroundColor Gray
Write-Host ""
Write-Host "  Use 'dev_stop' MCP tool or run Stop-Dev.ps1 to stop" -ForegroundColor Gray
Write-Host ""

# Return status for MCP tool consumption
$result = @{
    api_url = $apiUrl
    status = $finalStatus
}
if ($layoutResult) {
    $result.layout = $layoutResult
}
return $result
