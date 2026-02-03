# Stop-Prod.ps1
# Stop the Lintilla production container on the VPS

param(
    [switch]$Quiet,
    [switch]$Force  # Force stop without graceful shutdown
)

. "$PSScriptRoot/Common.ps1"

$repoRoot = Invoke-InProjectRoot

if (-not $Quiet) {
    Write-Host ""
    Write-Host "Lintilla Production - Stop" -ForegroundColor White
    Write-Host "==========================" -ForegroundColor White
    Write-Host ""
}

# Load environment variables to get deployment server IP
$envFile = Join-Path $repoRoot ".env.local"
if (-not (Test-Path $envFile)) {
    Write-Status ".env.local file not found" -Type Error
    Write-Status "Cannot determine deployment server IP" -Type Error
    exit 1
}

try {
    $envVars = Load-EnvFile -Path $envFile
    $serverIp = $envVars["DEPLOYMENT_SERVER_IP"]

    if (-not $serverIp) {
        Write-Status "DEPLOYMENT_SERVER_IP not found in .env.local" -Type Error
        exit 1
    }

    if (-not $Quiet) {
        Write-Status "Connecting to deployment server: $serverIp" -Type Info
    }
}
catch {
    Write-Status "Failed to load .env.local: $_" -Type Error
    exit 1
}

# Check SSH connectivity
try {
    $null = ssh -o ConnectTimeout=5 -o BatchMode=yes "andre@$serverIp" "exit" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Status "Cannot connect to server via SSH" -Type Error
        Write-Status "Ensure SSH key is set up at ~/.ssh/id_ed25519" -Type Info
        exit 1
    }
    if (-not $Quiet) {
        Write-Status "SSH connection established" -Type Success
    }
}
catch {
    Write-Status "SSH connection test failed: $_" -Type Error
    exit 1
}

if (-not $Quiet) {
    Write-Host ""
}

# Check current container status
$containerStatus = ssh "andre@$serverIp" "docker ps --filter name=lintilla --format '{{.Status}}'" 2>&1

if (-not $containerStatus) {
    if (-not $Quiet) {
        Write-Status "Container is not running" -Type Neutral
    }

    return @{
        status = "not_running"
        server = $serverIp
    }
}

if (-not $Quiet) {
    Write-Status "Current status: $containerStatus" -Type Info
    Write-Host ""
}

# Stop the container
if ($Force) {
    if (-not $Quiet) {
        Write-Status "Force stopping container (kill)..." -Type Warning
    }
    ssh "andre@$serverIp" "docker kill lintilla"
} else {
    if (-not $Quiet) {
        Write-Status "Stopping container gracefully..." -Type Info
    }
    ssh "andre@$serverIp" "cd /opt/worker && docker compose down"
}

if ($LASTEXITCODE -ne 0) {
    Write-Status "Failed to stop container" -Type Error
    exit 1
}

# Verify it's stopped
$verifyStatus = ssh "andre@$serverIp" "docker ps --filter name=lintilla --format '{{.Status}}'" 2>&1

if ($verifyStatus) {
    Write-Status "Container may still be stopping..." -Type Warning
} else {
    if (-not $Quiet) {
        Write-Status "Container stopped successfully" -Type Success
    }
}

if (-not $Quiet) {
    Write-Host ""
    Write-Host "  Server:    $serverIp" -ForegroundColor Cyan
    Write-Host "  Container: lintilla" -ForegroundColor Cyan
    Write-Host "  Status:    Stopped" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Start:     Start-Prod.ps1" -ForegroundColor Gray
    Write-Host "  Restart:   Restart-Prod.ps1" -ForegroundColor Gray
    Write-Host ""
}

return @{
    status = "stopped"
    server = $serverIp
}
