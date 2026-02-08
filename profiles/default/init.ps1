#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Initialize Claude Code integration by copying agents and skills to .claude/ directory.

.DESCRIPTION
    This script bridges the .bot/ system with Claude Code by copying agent and skill
    definitions from .bot/prompts/ to .claude/. It's idempotent and can be run 
    repeatedly without issues.

.NOTES
    This script should be run from the project root directory.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

# Get script and project directories
$BotDir = $PSScriptRoot
$ProjectRoot = Split-Path -Parent $BotDir
$ClaudeDir = Join-Path $ProjectRoot ".claude"

Write-Host "  Initializing Claude Code integration..." -ForegroundColor Cyan
Write-Host ""

# Create .claude directory if it doesn't exist
if (-not (Test-Path $ClaudeDir)) {
    Write-Host "  Creating .claude directory..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $ClaudeDir | Out-Null
}

# Copy agents
$SourceAgentsDir = Join-Path $BotDir "prompts\agents"
$DestAgentsDir = Join-Path $ClaudeDir "agents"

if (Test-Path $SourceAgentsDir) {
    Write-Host "  Copying agents..." -ForegroundColor Yellow
    
    if (Test-Path $DestAgentsDir) {
        Remove-Item -Path $DestAgentsDir -Recurse -Force
    }
    
    Copy-Item -Path $SourceAgentsDir -Destination $DestAgentsDir -Recurse
    
    # Count agent folders
    $AgentCount = (Get-ChildItem -Path $DestAgentsDir -Directory).Count
    Write-Host "  + Copied $AgentCount agent(s)" -ForegroundColor Green
}
else {
    Write-Host "  ! No agents directory found at $SourceAgentsDir" -ForegroundColor DarkYellow
}

# Copy skills
$SourceSkillsDir = Join-Path $BotDir "prompts\skills"
$DestSkillsDir = Join-Path $ClaudeDir "skills"

if (Test-Path $SourceSkillsDir) {
    Write-Host "  Copying skills..." -ForegroundColor Yellow
    
    if (Test-Path $DestSkillsDir) {
        Remove-Item -Path $DestSkillsDir -Recurse -Force
    }
    
    Copy-Item -Path $SourceSkillsDir -Destination $DestSkillsDir -Recurse
    
    # Count skill folders
    $SkillCount = (Get-ChildItem -Path $DestSkillsDir -Directory).Count
    Write-Host "  + Copied $SkillCount skill(s)" -ForegroundColor Green
}
else {
    Write-Host "  ! No skills directory found at $SourceSkillsDir" -ForegroundColor DarkYellow
}

Write-Host ""
Write-Host "  Initialization complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Claude Code agents and skills are now available in:" -ForegroundColor Cyan
Write-Host "  $ClaudeDir" -ForegroundColor White
Write-Host ""
Write-Host "You can now use Claude Code with the TDD-focused agent system." -ForegroundColor Cyan
Write-Host ""
