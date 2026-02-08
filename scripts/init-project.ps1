#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Initialize .bot in the current project

.DESCRIPTION
    Copies the default .bot structure to the current project directory.
    Optionally installs a profile for tech-specific features.

.PARAMETER Profile
    Profile to install (e.g., 'dotnet'). Can be specified multiple times.

.PARAMETER Force
    Overwrite existing .bot directory.

.PARAMETER DryRun
    Preview changes without applying.

.EXAMPLE
    init-project.ps1
    Installs base default only.

.EXAMPLE
    init-project.ps1 -Profile dotnet
    Installs base default + dotnet profile.
#>

[CmdletBinding()]
param(
    [string[]]$Profile,
    [switch]$Force,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$DotbotBase = Join-Path $HOME "dotbot"
$DefaultDir = Join-Path $DotbotBase "profiles\default"
$ProjectDir = Get-Location
$BotDir = Join-Path $ProjectDir ".bot"

# Import platform functions
Import-Module (Join-Path $DotbotBase "scripts\Platform-Functions.psm1") -Force

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Blue
Write-Host ""
Write-Host "    D O T B O T   v3" -ForegroundColor Blue
Write-Host "    Project Initialization" -ForegroundColor Yellow
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Blue
Write-Host ""

# Check if default exists
if (-not (Test-Path $DefaultDir)) {
    Write-DotbotError "Default directory not found: $DefaultDir"
    Write-Host "  Run 'dotbot update' to repair installation" -ForegroundColor Yellow
    exit 1
}

# Check if .bot already exists
if ((Test-Path $BotDir) -and -not $Force) {
    Write-DotbotWarning ".bot directory already exists"
    Write-Host "  Use -Force to overwrite" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

Write-Status "Initializing .bot in: $ProjectDir"

if ($DryRun) {
    Write-Host "  Would copy default from: $DefaultDir" -ForegroundColor Yellow
    Write-Host "  Would copy to: $BotDir" -ForegroundColor Yellow
    Write-Host ""
    exit 0
}

# Remove existing .bot if Force
if ((Test-Path $BotDir) -and $Force) {
    Write-Status "Removing existing .bot directory"
    Remove-Item -Path $BotDir -Recurse -Force
}

# Copy default to .bot
Write-Status "Copying default files"
Copy-Item -Path $DefaultDir -Destination $BotDir -Recurse -Force

# Create empty workspace directories
$workspaceDirs = @(
    "workspace\tasks\todo",
    "workspace\tasks\in-progress",
    "workspace\tasks\done",
    "workspace\tasks\skipped",
    "workspace\tasks\cancelled",
    "workspace\sessions",
    "workspace\sessions\runs",
    "workspace\sessions\history",
    "workspace\plans",
    "workspace\product",
    "workspace\feedback\pending",
    "workspace\feedback\applied",
    "workspace\feedback\archived"
)

foreach ($dir in $workspaceDirs) {
    $fullPath = Join-Path $BotDir $dir
    if (-not (Test-Path $fullPath)) {
        New-Item -ItemType Directory -Path $fullPath -Force | Out-Null
    }
    # Add .gitkeep to empty directories
    $gitkeep = Join-Path $fullPath ".gitkeep"
    if (-not (Test-Path $gitkeep)) {
        New-Item -ItemType File -Path $gitkeep -Force | Out-Null
    }
}

Write-Success "Created .bot directory structure"

# Install profiles if specified
$ProfilesDir = Join-Path $DotbotBase "profiles"
if ($Profile -and $Profile.Count -gt 0) {
    foreach ($profileName in $Profile) {
        $profileDir = Join-Path $ProfilesDir $profileName
        
        if (-not (Test-Path $profileDir)) {
            Write-DotbotWarning "Profile not found: $profileName"
            Write-Host "  Available profiles:" -ForegroundColor Yellow
            Get-ChildItem -Path $ProfilesDir -Directory | ForEach-Object { Write-Host "    - $($_.Name)" }
            continue
        }
        
        Write-Status "Installing profile: $profileName"
        
        # Copy profile files (overlay on top of default)
        Get-ChildItem -Path $profileDir -Recurse -File | ForEach-Object {
            $relativePath = $_.FullName.Substring($profileDir.Length + 1)
            $destPath = Join-Path $BotDir $relativePath
            $destDir = Split-Path $destPath -Parent
            
            # Handle config.json merging for hooks/verify
            if ($relativePath -eq "hooks\verify\config.json") {
                $baseConfigPath = Join-Path $BotDir "hooks\verify\config.json"
                if (Test-Path $baseConfigPath) {
                    # Merge scripts arrays
                    $baseConfig = Get-Content $baseConfigPath -Raw | ConvertFrom-Json
                    $profileConfig = Get-Content $_.FullName -Raw | ConvertFrom-Json
                    
                    # Add profile scripts to base scripts
                    $mergedScripts = @($baseConfig.scripts) + @($profileConfig.scripts)
                    $baseConfig.scripts = $mergedScripts
                    
                    $baseConfig | ConvertTo-Json -Depth 10 | Set-Content $baseConfigPath
                    Write-Host "    Merged: $relativePath" -ForegroundColor Gray
                    return
                }
            }
            
            # Create directory if needed
            if (-not (Test-Path $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }
            
            # Copy file
            Copy-Item -Path $_.FullName -Destination $destPath -Force
            Write-Host "    Copied: $relativePath" -ForegroundColor Gray
        }
        
        Write-Success "Installed profile: $profileName"
    }
}

# Run .bot/init.ps1 to set up .claude integration
$initScript = Join-Path $BotDir "init.ps1"
if (Test-Path $initScript) {
    Write-Status "Setting up Claude Code integration"
    & $initScript
}

# Show completion message
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Blue
Write-Host ""
Write-Host "  ✓ Project Initialized!" -ForegroundColor Green
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Blue
Write-Host ""
Write-Host "  WHAT'S INSTALLED" -ForegroundColor Blue
Write-Host "  ────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""
Write-Host "    .bot/systems/mcp/    " -NoNewline -ForegroundColor Yellow
Write-Host "MCP server for task management" -ForegroundColor White
Write-Host "    .bot/systems/ui/     " -NoNewline -ForegroundColor Yellow
Write-Host "Web UI server (port 8686)" -ForegroundColor White
Write-Host "    .bot/systems/runtime/" -NoNewline -ForegroundColor Yellow
Write-Host "Autonomous loop for Claude CLI" -ForegroundColor White
Write-Host "    .bot/prompts/        " -NoNewline -ForegroundColor Yellow
Write-Host "Agents, skills, workflows" -ForegroundColor White
if ($Profile -and $Profile.Count -gt 0) {
    Write-Host ""
    Write-Host "  PROFILES INSTALLED" -ForegroundColor Blue
    Write-Host "  ────────────────────────────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    foreach ($p in $Profile) {
        Write-Host "    $p" -ForegroundColor Cyan
    }
}
Write-Host ""
Write-Host "  NEXT STEPS" -ForegroundColor Blue
Write-Host "  ────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""
Write-Host "    1. Start the UI:     " -NoNewline -ForegroundColor Yellow
Write-Host ".bot\go.ps1" -ForegroundColor White
Write-Host "    2. View docs:        " -NoNewline -ForegroundColor Yellow
Write-Host ".bot\README.md" -ForegroundColor White
Write-Host ""
