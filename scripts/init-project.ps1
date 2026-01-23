#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Initialize .bot in the current project

.DESCRIPTION
    Copies the template .bot structure to the current project directory
#>

[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$DotbotBase = Join-Path $HOME "dotbot"
$TemplateDir = Join-Path $DotbotBase "template"
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

# Check if template exists
if (-not (Test-Path $TemplateDir)) {
    Write-Error "Template directory not found: $TemplateDir"
    Write-Host "  Run 'dotbot update' to repair installation" -ForegroundColor Yellow
    exit 1
}

# Check if .bot already exists
if ((Test-Path $BotDir) -and -not $Force) {
    Write-Warning ".bot directory already exists"
    Write-Host "  Use -Force to overwrite" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

Write-Status "Initializing .bot in: $ProjectDir"

if ($DryRun) {
    Write-Host "  Would copy template from: $TemplateDir" -ForegroundColor Yellow
    Write-Host "  Would copy to: $BotDir" -ForegroundColor Yellow
    Write-Host ""
    exit 0
}

# Remove existing .bot if Force
if ((Test-Path $BotDir) -and $Force) {
    Write-Status "Removing existing .bot directory"
    Remove-Item -Path $BotDir -Recurse -Force
}

# Copy template to .bot
Write-Status "Copying template files"
Copy-Item -Path $TemplateDir -Destination $BotDir -Recurse -Force

# Create empty state directories (template has structure, but ensure they exist)
$stateDirs = @(
    "state\tasks\todo",
    "state\tasks\in-progress",
    "state\tasks\done",
    "state\tasks\skipped",
    "state\tasks\cancelled",
    "state\sessions",
    "state\sessions\runs",
    "state\sessions\history",
    "state\product",
    "state\feedback\pending",
    "state\feedback\applied",
    "state\feedback\archived"
)

foreach ($dir in $stateDirs) {
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
Write-Host ""
Write-Host "  NEXT STEPS" -ForegroundColor Blue
Write-Host "  ────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""
Write-Host "    1. Start the UI:     " -NoNewline -ForegroundColor Yellow
Write-Host ".bot\go.ps1" -ForegroundColor White
Write-Host "    2. View docs:        " -NoNewline -ForegroundColor Yellow
Write-Host ".bot\README.md" -ForegroundColor White
Write-Host ""
