# View-Logs.ps1
# View logs from the deployed Lintilla instance

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("dev", "prod")]
    [string]$Environment = "dev",
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("docker", "app", "both")]
    [string]$Type = "both",
    
    [Parameter(Mandatory=$false)]
    [int]$Lines = 50,
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("Debug", "Information", "Warning", "Error", "Fatal")]
    [string[]]$LogLevel,
    
    [switch]$Follow
)

. "$PSScriptRoot/Common.ps1"

# Helper function to filter JSON log lines by level
function Filter-LogLevel {
    param(
        [string]$Line,
        [string[]]$Levels
    )
    
    if (-not $Levels -or $Levels.Count -eq 0) {
        return $true
    }
    
    # Serilog omits @l for Information level
    if ($Line -match '"@l":"([^"]+)"') {
        $level = $matches[1]
        return $level -in $Levels
    }
    elseif ($Levels -contains "Information") {
        # No @l field means Information level
        return $Line -match '"@t":'
    }
    
    return $false
}

# Build grep pattern for remote filtering
function Get-LogLevelGrepPattern {
    param([string[]]$Levels)
    
    if (-not $Levels -or $Levels.Count -eq 0) {
        return $null
    }
    
    $patterns = @()
    foreach ($level in $Levels) {
        if ($level -eq "Information") {
            # Information has no @l field, so we can't easily grep for it alone
            # We'll handle this case specially
            continue
        }
        $patterns += '"@l":"' + $level + '"'
    }
    
    if ($patterns.Count -eq 0) {
        return $null
    }
    
    return $patterns -join '\|'
}

$repoRoot = Invoke-InProjectRoot

Write-Host ""
Write-Host "Lintilla Logs ($Environment)" -ForegroundColor White
Write-Host "========================" -ForegroundColor White
Write-Host ""

# Handle environment-specific setup
if ($Environment -eq "prod") {
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
        Write-Host ""
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
    }
    catch {
        Write-Status "SSH connection test failed: $_" -Type Error
        exit 1
    }
}
else {
    # Dev environment - use local paths
    Write-Status "Viewing local development logs" -Type Info
    Write-Host ""
}

# View Docker logs
if ($Type -in @("docker", "both")) {
    Write-Host "Docker Container Logs (stdout/stderr)" -ForegroundColor Cyan
    Write-Host "======================================" -ForegroundColor Cyan
    Write-Host ""
    
    if ($Environment -eq "prod") {
        $grepPattern = Get-LogLevelGrepPattern -Levels $LogLevel
        $levelInfo = if ($LogLevel) { " (filtering: $($LogLevel -join ', '))" } else { "" }
        
        if ($Follow) {
            Write-Status "Following Docker logs$levelInfo (Ctrl+C to stop)..." -Type Info
            Write-Host ""
            if ($grepPattern) {
                ssh "andre@$serverIp" "docker logs -f --tail $Lines lintilla 2>&1 | grep --line-buffered '$grepPattern'"
            }
            else {
                ssh "andre@$serverIp" "docker logs -f --tail $Lines lintilla"
            }
        }
        else {
            if ($grepPattern) {
                ssh "andre@$serverIp" "docker logs --tail 1000 lintilla 2>&1 | grep '$grepPattern' | tail -n $Lines"
            }
            else {
                ssh "andre@$serverIp" "docker logs --tail $Lines lintilla"
            }
            
            if ($LASTEXITCODE -ne 0) {
                Write-Status "Failed to retrieve Docker logs" -Type Error
                exit 1
            }
        }
    }
    else {
        # Dev environment - check for local dev process
        $pidFile = Join-Path $repoRoot ".bot\.dev-pids.json"
        if (Test-Path $pidFile) {
            Write-Status "Dev process running - viewing console output" -Type Info
            Write-Host ""
            Write-Status "Docker logs not available in dev mode (process runs in separate window)" -Type Warning
            Write-Status "Check the API window or use -Type app to view file logs" -Type Info
        }
        else {
            Write-Status "Dev environment not running" -Type Warning
            Write-Status "Start it with dev_start MCP tool or Start-Dev.ps1" -Type Info
        }
    }
    
    if ($Type -eq "both") {
        Write-Host ""
        Write-Host ""
    }
}

# View application file logs
if ($Type -in @("app", "both")) {
    $logLocation = if ($Environment -eq "prod") { "/data/logs" } else { "logs" }
    Write-Host "Application File Logs ($logLocation)" -ForegroundColor Cyan
    Write-Host "===================================" -ForegroundColor Cyan
    Write-Host ""
    
    if ($Environment -eq "prod") {
        # List available log files on prod
        Write-Status "Available log files:" -Type Info
        $logFiles = ssh "andre@$serverIp" "ls -lh /data/logs/*.log 2>/dev/null" 2>$null
        
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($logFiles)) {
            Write-Status "No log files found in /data/logs" -Type Warning
        }
        else {
            Write-Host $logFiles -ForegroundColor Gray
            Write-Host ""
            
            # Get the most recent log file
            $latestLog = ssh "andre@$serverIp" "ls -t /data/logs/*.log 2>/dev/null | head -1" 2>$null
            
            if ($latestLog) {
                $grepPattern = Get-LogLevelGrepPattern -Levels $LogLevel
                $levelInfo = if ($LogLevel) { " (filtering: $($LogLevel -join ', '))" } else { "" }
                Write-Status "Showing latest: $latestLog$levelInfo" -Type Info
                Write-Host ""
                
                if ($Follow) {
                    Write-Status "Following log file (Ctrl+C to stop)..." -Type Info
                    Write-Host ""
                    if ($grepPattern) {
                        ssh "andre@$serverIp" "tail -f -n $Lines `"$latestLog`" | grep --line-buffered '$grepPattern'"
                    }
                    else {
                        ssh "andre@$serverIp" "tail -f -n $Lines `"$latestLog`""
                    }
                }
                else {
                    if ($grepPattern) {
                        ssh "andre@$serverIp" "tail -n 1000 `"$latestLog`" | grep '$grepPattern' | tail -n $Lines"
                    }
                    else {
                        ssh "andre@$serverIp" "tail -n $Lines `"$latestLog`""
                    }
                }
            }
        }
    }
    else {
        # Dev environment - use local logs directory
        $logsDir = Join-Path $repoRoot "logs"
        
        if (-not (Test-Path $logsDir)) {
            Write-Status "Logs directory not found: $logsDir" -Type Warning
            Write-Status "Start the dev environment first" -Type Info
        }
        else {
            # List available log files
            Write-Status "Available log files:" -Type Info
            $logFilesList = Get-ChildItem -Path $logsDir -Filter "*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
            
            if ($logFilesList.Count -eq 0) {
                Write-Status "No log files found in $logsDir" -Type Warning
            }
            else {
                $logFilesList | ForEach-Object {
                    $size = if ($_.Length -gt 1MB) { "{0:N2} MB" -f ($_.Length / 1MB) } else { "{0:N2} KB" -f ($_.Length / 1KB) }
                    Write-Host "  $($_.Name) ($size) - $($_.LastWriteTime)" -ForegroundColor Gray
                }
                Write-Host ""
                
                # Get the most recent log file
                $latestLog = $logFilesList[0].FullName
                $levelInfo = if ($LogLevel) { " (filtering: $($LogLevel -join ', '))" } else { "" }
                Write-Status "Showing latest: $($logFilesList[0].Name)$levelInfo" -Type Info
                Write-Host ""
                
                if ($Follow) {
                    Write-Status "Following log file (Ctrl+C to stop)..." -Type Info
                    Write-Host ""
                    Get-Content -Path $latestLog -Tail $Lines -Wait | ForEach-Object {
                        if (Filter-LogLevel -Line $_ -Levels $LogLevel) {
                            Write-Host $_
                        }
                    }
                }
                else {
                    Get-Content -Path $latestLog -Tail ($Lines * 10) | ForEach-Object {
                        if (Filter-LogLevel -Line $_ -Levels $LogLevel) {
                            $_
                        }
                    } | Select-Object -Last $Lines | ForEach-Object { Write-Host $_ }
                }
            }
        }
    }
}

Write-Host ""
Write-Status "Log viewing complete" -Type Success
Write-Host ""

if ($Environment -eq "prod") {
    Write-Host "  Server:      $serverIp" -ForegroundColor Gray
    Write-Host "  Docker logs: ssh andre@$serverIp 'docker logs -f lintilla'" -ForegroundColor Gray
    Write-Host "  App logs:    ssh andre@$serverIp 'tail -f /data/logs/*.log'" -ForegroundColor Gray
}
else {
    Write-Host "  Environment: Local development" -ForegroundColor Gray
    Write-Host "  App logs:    $($repoRoot -replace '\\', '/')/logs/" -ForegroundColor Gray
}
Write-Host ""
