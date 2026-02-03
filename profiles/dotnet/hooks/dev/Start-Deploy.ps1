# Start-Deploy.ps1
# Triggers deployment after confirming git state is clean and pushed

param(
    [ValidateSet('major', 'minor', 'patch', '')]
    [string]$Bump = 'patch'
)

. "$PSScriptRoot/Common.ps1"

$repoRoot = Invoke-InProjectRoot

# Version management helper functions
function Get-VersionFile {
    $versionPath = Join-Path $repoRoot '.bot/workspace/version.json'
    if (Test-Path $versionPath) {
        return Get-Content $versionPath -Raw | ConvertFrom-Json
    }
    # Create default if doesn't exist
    $default = @{ version = '0.1.0'; lastDeployedAt = $null; deployCount = 0 }
    $default | ConvertTo-Json | Set-Content $versionPath
    return [PSCustomObject]$default
}

function Save-VersionFile {
    param([PSCustomObject]$VersionData)
    $versionPath = Join-Path $repoRoot '.bot/workspace/version.json'
    $VersionData | ConvertTo-Json | Set-Content $versionPath
}

function Get-NextVersion {
    param(
        [string]$CurrentVersion,
        [string]$BumpType
    )
    $parts = $CurrentVersion -split '\.'
    $major = [int]$parts[0]
    $minor = [int]$parts[1]
    $patch = [int]$parts[2]
    
    switch ($BumpType) {
        'major' { $major++; $minor = 0; $patch = 0 }
        'minor' { $minor++; $patch = 0 }
        'patch' { $patch++ }
    }
    
    return "$major.$minor.$patch"
}

Write-Host ""
Write-Host "Lintilla Deployment" -ForegroundColor White
Write-Host "===================" -ForegroundColor White
Write-Host ""

# Check for uncommitted changes
Write-Status "Checking git status..." -Type Info

$uncommitted = git status --porcelain 2>$null
if ($uncommitted) {
    Write-Status "Uncommitted changes detected:" -Type Error
    Write-Host ""
    $uncommitted | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
    Write-Host ""
    Write-Status "Please commit your changes before deploying" -Type Error
    exit 1
}

Write-Status "Working directory is clean" -Type Success

# Check if local is ahead of remote
Write-Status "Checking remote sync..." -Type Info

git fetch origin --quiet 2>$null
$localHead = git rev-parse HEAD 2>$null
$remoteHead = git rev-parse origin/master 2>$null

if ($localHead -ne $remoteHead) {
    $ahead = git rev-list --count origin/master..HEAD 2>$null
    $behind = git rev-list --count HEAD..origin/master 2>$null
    
    if ($ahead -gt 0) {
        Write-Status "Local is $ahead commit(s) ahead of origin/master" -Type Error
        Write-Status "Please push your changes before deploying" -Type Error
        exit 1
    }
    
    if ($behind -gt 0) {
        Write-Status "Local is $behind commit(s) behind origin/master" -Type Warning
        Write-Status "Consider pulling latest changes" -Type Info
    }
}

Write-Status "Local is in sync with origin/master" -Type Success

# Increment version
Write-Host ""
Write-Status "Managing version..." -Type Info

$versionData = Get-VersionFile
$currentVersion = $versionData.version
$newVersion = Get-NextVersion -CurrentVersion $currentVersion -BumpType $Bump

Write-Host "  Current: v$currentVersion" -ForegroundColor Gray
Write-Host "  New:     v$newVersion ($Bump bump)" -ForegroundColor Cyan

# Trigger deployment
Write-Host ""
Write-Status "Triggering deployment workflow..." -Type Info

try {
    $result = gh workflow run build-and-deploy --repo andresharpe/Lintilla 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Status "Failed to trigger workflow: $result" -Type Error
        exit 1
    }
    Write-Status "Workflow triggered successfully" -Type Success
}
catch {
    Write-Status "Failed to trigger workflow: $_" -Type Error
    exit 1
}

# Update version file after successful trigger
$versionData.version = $newVersion
$versionData.lastDeployedAt = (Get-Date -Format 'o')
$versionData.deployCount = $versionData.deployCount + 1
Save-VersionFile -VersionData $versionData

Write-Status "Version updated to v$newVersion" -Type Success

# Get the run URL
Start-Sleep -Seconds 2
$runInfo = gh run list --workflow="deploy.yml" --limit 1 --json databaseId,url 2>$null | ConvertFrom-Json

Write-Host ""
Write-Host "  Version:  v$newVersion" -ForegroundColor Cyan
Write-Host "  Workflow: build-and-deploy" -ForegroundColor Cyan
Write-Host "  Branch:   master" -ForegroundColor Gray
if ($runInfo -and $runInfo[0].url) {
    Write-Host "  Run:      $($runInfo[0].url)" -ForegroundColor Gray
}
Write-Host ""
Write-Host "  Use 'gh run watch' to monitor progress" -ForegroundColor Gray
Write-Host ""

return @{
    status = "triggered"
    version = $newVersion
    run_id = $runInfo[0].databaseId
}
