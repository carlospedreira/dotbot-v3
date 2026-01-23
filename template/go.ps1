#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Launch the .bot UI server and open the browser.

.DESCRIPTION
    This script starts the web-based task management UI and automatically opens
    it in your default browser. The UI server runs in the background.

.NOTES
    Press Ctrl+C to stop the server when done.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

# Get directories
$BotDir = $PSScriptRoot
$UIDir = Join-Path $BotDir "systems\ui"
$ServerScript = Join-Path $UIDir "server.ps1"

Write-Host "🚀 Starting .bot UI..." -ForegroundColor Cyan
Write-Host ""

# Check if server script exists
if (-not (Test-Path $ServerScript)) {
    Write-Host "❌ Error: UI server script not found at:" -ForegroundColor Red
    Write-Host "   $ServerScript" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please ensure the .bot/systems/ui/ directory exists and contains server.ps1" -ForegroundColor Yellow
    exit 1
}

# Start the UI server
Write-Host "🌐 Starting UI server..." -ForegroundColor Yellow
Write-Host "   Location: $UIDir" -ForegroundColor DarkGray
Write-Host ""

# Start the server in a new PowerShell window
Start-Process pwsh -ArgumentList "-NoExit", "-File", "`"$ServerScript`""

# Open browser after a short delay
Start-Sleep -Seconds 2
Start-Process "http://localhost:8686"

Write-Host "🌍 Browser opened at http://localhost:8686" -ForegroundColor Green
Write-Host "   Server is running in a separate window." -ForegroundColor DarkGray
Write-Host ""
