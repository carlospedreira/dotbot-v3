# =============================================================================
# Platform-Functions.psm1
# Cross-platform helper functions for dotbot installation
# =============================================================================

# Initialize platform detection variables
$script:IsWindows = $false
$script:IsMacOS = $false
$script:IsLinux = $false

function Initialize-PlatformVariables {
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        $script:IsWindows = $IsWindows
        $script:IsMacOS = $IsMacOS
        $script:IsLinux = $IsLinux
    } else {
        # PowerShell 5.x is Windows-only
        $script:IsWindows = $true
        $script:IsMacOS = $false
        $script:IsLinux = $false
    }
}

function Get-PlatformName {
    Initialize-PlatformVariables
    if ($script:IsWindows) { return "Windows" }
    if ($script:IsMacOS) { return "macOS" }
    if ($script:IsLinux) { return "Linux" }
    return "Unknown"
}

function Add-ToPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Directory,
        [switch]$DryRun
    )
    
    Initialize-PlatformVariables
    
    if ($script:IsWindows) {
        Add-ToWindowsPath -Directory $Directory -DryRun:$DryRun
    } else {
        Add-ToUnixPath -Directory $Directory -DryRun:$DryRun
    }
}

function Add-ToWindowsPath {
    param(
        [string]$Directory,
        [switch]$DryRun
    )
    
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
    
    if ($currentPath -split ";" -contains $Directory) {
        Write-Host "  ✓ Already in PATH: $Directory" -ForegroundColor Green
        return
    }
    
    if ($DryRun) {
        Write-Host "  Would add to PATH: $Directory" -ForegroundColor Yellow
        return
    }
    
    $newPath = "$currentPath;$Directory"
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    
    # Also update current session
    $env:Path = "$env:Path;$Directory"
    
    Write-Host "  ✓ Added to PATH: $Directory" -ForegroundColor Green
    Write-Host "    Restart your terminal for changes to take effect" -ForegroundColor Yellow
}

function Add-ToUnixPath {
    param(
        [string]$Directory,
        [switch]$DryRun
    )
    
    # Determine shell profile file
    $profileFiles = @()
    
    if ($env:SHELL -like "*zsh*") {
        $profileFiles += Join-Path $HOME ".zshrc"
    }
    if ($env:SHELL -like "*bash*" -or $profileFiles.Count -eq 0) {
        $profileFiles += Join-Path $HOME ".bashrc"
        $profileFiles += Join-Path $HOME ".bash_profile"
    }
    $profileFiles += Join-Path $HOME ".profile"
    
    $exportLine = "export PATH=`"$Directory:`$PATH`""
    
    foreach ($profileFile in $profileFiles) {
        if (Test-Path $profileFile) {
            $content = Get-Content $profileFile -Raw -ErrorAction SilentlyContinue
            
            if ($content -and $content.Contains($Directory)) {
                Write-Host "  ✓ Already in $profileFile" -ForegroundColor Green
                continue
            }
            
            if ($DryRun) {
                Write-Host "  Would add to $profileFile" -ForegroundColor Yellow
                continue
            }
            
            Add-Content -Path $profileFile -Value "`n# dotbot`n$exportLine"
            Write-Host "  ✓ Added to $profileFile" -ForegroundColor Green
        }
    }
    
    Write-Host "    Run 'source ~/.bashrc' or restart your terminal" -ForegroundColor Yellow
}

function Set-ExecutablePermission {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )
    
    Initialize-PlatformVariables
    
    if (-not $script:IsWindows) {
        if (Test-Path $FilePath) {
            chmod +x $FilePath 2>$null
        }
    }
}

function Write-Status {
    param([string]$Message)
    Write-Host "  → $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "  ✓ $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "  ⚠ $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "  ✗ $Message" -ForegroundColor Red
}

Export-ModuleMember -Function @(
    'Initialize-PlatformVariables',
    'Get-PlatformName',
    'Add-ToPath',
    'Set-ExecutablePermission',
    'Write-Status',
    'Write-Success',
    'Write-Warning',
    'Write-Error'
)
