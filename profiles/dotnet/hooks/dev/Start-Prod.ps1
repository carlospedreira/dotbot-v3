# Start-Prod.ps1
# Start the Lintilla production container on the VPS

param(
    [switch]$Pull  # Pull latest image before starting
)

. "$PSScriptRoot/Common.ps1"

$repoRoot = Invoke-InProjectRoot

Write-Host ""
Write-Host "Lintilla Production - Start" -ForegroundColor White
Write-Host "===========================" -ForegroundColor White
Write-Host ""

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

    Write-Status "Connecting to deployment server: $serverIp" -Type Info
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
    Write-Status "SSH connection established" -Type Success
}
catch {
    Write-Status "SSH connection test failed: $_" -Type Error
    exit 1
}

Write-Host ""

# Stop any existing container first (makes this idempotent)
& "$PSScriptRoot\Stop-Prod.ps1" -Quiet

# Pull latest image if requested
if ($Pull) {
    Write-Status "Pulling latest image..." -Type Info
    ssh "andre@$serverIp" "cd /opt/worker && docker compose pull"

    if ($LASTEXITCODE -ne 0) {
        Write-Status "Failed to pull image" -Type Error
        exit 1
    }
    Write-Status "Image pulled successfully" -Type Success
    Write-Host ""
}

# Start the container
Write-Status "Starting Lintilla container..." -Type Info
$startResult = ssh "andre@$serverIp" "cd /opt/worker && docker compose up -d"

if ($LASTEXITCODE -ne 0) {
    Write-Status "Failed to start container" -Type Error
    Write-Host $startResult -ForegroundColor Red
    exit 1
}

Write-Status "Container start command issued" -Type Success

# Wait for container to be running and healthy (up to 45 seconds)
Write-Host ""
Write-Status "Waiting for container to start..." -Type Info

$timeout = 45
$elapsed = 0
$healthyTimeout = 30  # Only wait 30s for healthy status

while ($elapsed -lt $timeout) {
    # Check if container is running
    $running = ssh "andre@$serverIp" "docker ps --filter name=lintilla --format '{{.Status}}'" 2>&1
    if (-not ($running -match "Up")) {
        Write-Status "Container failed to start" -Type Error
        Write-Host ""
        Write-Status "Recent logs:" -Type Info
        ssh "andre@$serverIp" "docker logs --tail 30 lintilla"
        exit 1
    }

    # Check health status (but don't wait forever)
    $health = ssh "andre@$serverIp" "docker inspect --format='{{.State.Health.Status}}' lintilla 2>/dev/null" 2>&1
    
    if ($health -eq "healthy") {
        Write-Status "Container is healthy" -Type Success
        break
    }
    
    # If we've waited long enough and it's at least running, that's acceptable
    if ($elapsed -ge $healthyTimeout -and $running -match "Up") {
        Write-Status "Container is running (health check: $health)" -Type Warning
        break
    }

    Start-Sleep -Seconds 3
    $elapsed += 3
}

if ($elapsed -ge $timeout) {
    Write-Status "Timeout waiting for container (may still be starting)" -Type Warning
}

# Get final status
$finalStatus = ssh "andre@$serverIp" "docker ps --filter name=lintilla --format 'table {{.Status}}\t{{.Ports}}'" 2>&1

Write-Host ""
Write-Host "  Server:    $serverIp" -ForegroundColor Cyan
Write-Host "  Container: lintilla" -ForegroundColor Cyan
Write-Host "  Status:    $finalStatus" -ForegroundColor Gray
Write-Host ""
Write-Host "  View logs: dev_logs environment=prod" -ForegroundColor Gray
Write-Host "  Stop:      Stop-Prod.ps1" -ForegroundColor Gray
Write-Host ""

return @{
    status = "started"
    server = $serverIp
}
