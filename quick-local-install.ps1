#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Refresh ~/dotbot from this repo checkout.

.DESCRIPTION
    Copies all repo files to ~/dotbot, skipping .git/ and .github/.
    Preserves install-only files (bin/, etc.) already in ~/dotbot.
#>

$ErrorActionPreference = "Stop"

$RepoDir   = $PSScriptRoot
$TargetDir = Join-Path $HOME "dotbot"

if (-not (Test-Path $TargetDir)) {
    Write-Host "Target not found: $TargetDir" -ForegroundColor Red
    Write-Host "Run install.ps1 first." -ForegroundColor Yellow
    exit 1
}

$exclude = @('.git', '.github')

$files = Get-ChildItem -Path $RepoDir -Recurse -File | Where-Object {
    $rel = $_.FullName.Substring($RepoDir.Length + 1)
    $topDir = ($rel -split '[\\/]')[0]
    $topDir -notin $exclude
}

$copied = 0
foreach ($file in $files) {
    $rel      = $file.FullName.Substring($RepoDir.Length + 1)
    $destPath = Join-Path $TargetDir $rel
    $destDir  = Split-Path $destPath -Parent

    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }
    Copy-Item -Path $file.FullName -Destination $destPath -Force
    $copied++
}

Write-Host "Copied $copied files to $TargetDir" -ForegroundColor Green
