# Common.ps1
# Shared utilities for dev scripts

function Invoke-InProjectRoot {
    $root = git rev-parse --show-toplevel 2>$null
    if (-not $root) {
        throw "Not in a git repository"
    }
    Set-Location $root -ErrorAction Stop
    return $root
}

function Load-EnvFile {
    param(
        [string]$Path = ".env",
        [switch]$Export
    )
    
    if (-not (Test-Path $Path)) {
        throw ".env file not found at $Path"
    }
    
    $env = @{}
    Get-Content $Path | ForEach-Object {
        # Skip empty lines and comments
        if ($_ -match '^\s*([^#][^=]+)=(.*)$') {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()
            $env[$key] = $value
            
            if ($Export) {
                [Environment]::SetEnvironmentVariable($key, $value, "Process")
            }
        }
    }
    return $env
}

function Write-Status {
    param(
        [string]$Message,
        [ValidateSet("Success", "Info", "Warning", "Error", "Neutral")]
        [string]$Type = "Info"
    )
    
    $prefix = switch ($Type) {
        "Success" { "[OK]" }
        "Info"    { "[--]" }
        "Warning" { "[!!]" }
        "Error"   { "[XX]" }
        "Neutral" { "[  ]" }
    }
    
    $color = switch ($Type) {
        "Success" { "Green" }
        "Info"    { "Cyan" }
        "Warning" { "Yellow" }
        "Error"   { "Red" }
        "Neutral" { "Gray" }
    }
    
    Write-Host "$prefix $Message" -ForegroundColor $color
}
