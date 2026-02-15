<#
.SYNOPSIS
Settings, theme, and configuration API module

.DESCRIPTION
Provides theme management, UI settings, analysis config, and verification config CRUD.
Extracted from server.ps1 for modularity.
#>

$script:Config = @{
    ControlDir = $null
    BotRoot = $null
    StaticRoot = $null
}

function Initialize-SettingsAPI {
    param(
        [Parameter(Mandatory)] [string]$ControlDir,
        [Parameter(Mandatory)] [string]$BotRoot,
        [Parameter(Mandatory)] [string]$StaticRoot
    )
    $script:Config.ControlDir = $ControlDir
    $script:Config.BotRoot = $BotRoot
    $script:Config.StaticRoot = $StaticRoot
}

function Get-Theme {
    $themePath = Join-Path $script:Config.StaticRoot "theme-config.json"
    $settingsFile = Join-Path $script:Config.ControlDir "ui-settings.json"

    if (-not (Test-Path $themePath)) {
        return @{ _statusCode = 404; success = $false; error = "Theme config not found" }
    }

    try {
        # Load presets from theme-config.json
        $themeConfig = Get-Content $themePath -Raw | ConvertFrom-Json

        # Get active theme from ui-settings.json (default to "amber")
        $activeTheme = "amber"
        if (Test-Path $settingsFile) {
            try {
                $settings = Get-Content $settingsFile -Raw | ConvertFrom-Json
                if ($settings.theme) {
                    $activeTheme = $settings.theme
                }
            } catch { }
        }

        # Validate active theme exists
        if (-not $themeConfig.presets.($activeTheme)) {
            $activeTheme = "amber"
        }

        # Build response with computed mappings
        $preset = $themeConfig.presets.($activeTheme)
        $mappings = @{}
        foreach ($key in $preset.PSObject.Properties.Name) {
            if ($key -ne "name") {
                $rgb = $preset.$key
                $mappings[$key] = @{ r = $rgb[0]; g = $rgb[1]; b = $rgb[2] }
            }
        }

        return @{
            name = $preset.name
            mappings = $mappings
            presets = $themeConfig.presets
        }
    } catch {
        return @{ _statusCode = 500; success = $false; error = "Failed to load theme: $($_.Exception.Message)" }
    }
}

function Set-Theme {
    param(
        [Parameter(Mandatory)] $Body
    )
    $themePath = Join-Path $script:Config.StaticRoot "theme-config.json"
    $settingsFile = Join-Path $script:Config.ControlDir "ui-settings.json"

    if (-not (Test-Path $themePath)) {
        return @{ _statusCode = 404; success = $false; error = "Theme config not found" }
    }

    # Load presets
    $themeConfig = Get-Content $themePath -Raw | ConvertFrom-Json

    # Validate preset exists
    if (-not $Body.preset -or -not $themeConfig.presets.($Body.preset)) {
        return @{ _statusCode = 400; success = $false; error = "Invalid preset: $($Body.preset)" }
    }

    # Load or create settings as hashtable
    $settings = @{
        showDebug = $false
        showVerbose = $false
        theme = "amber"
    }
    if (Test-Path $settingsFile) {
        try {
            $existingSettings = Get-Content $settingsFile -Raw | ConvertFrom-Json
            foreach ($prop in $existingSettings.PSObject.Properties) {
                $settings[$prop.Name] = $prop.Value
            }
        } catch { }
    }

    # Update theme preference
    $settings.theme = $Body.preset

    # Save settings
    $settings | ConvertTo-Json -Depth 5 | Set-Content $settingsFile -Force

    # Build response with computed mappings
    $preset = $themeConfig.presets.($Body.preset)
    $mappings = @{}
    foreach ($key in $preset.PSObject.Properties.Name) {
        if ($key -ne "name") {
            $rgb = $preset.$key
            $mappings[$key] = @{ r = $rgb[0]; g = $rgb[1]; b = $rgb[2] }
        }
    }

    return @{
        name = $preset.name
        mappings = $mappings
        presets = $themeConfig.presets
    }
}

function Get-Settings {
    $settingsFile = Join-Path $script:Config.ControlDir "ui-settings.json"
    $defaultSettings = @{
        showDebug = $false
        showVerbose = $false
        analysisModel = "Opus"
        executionModel = "Opus"
    }

    if (Test-Path $settingsFile) {
        try {
            return Get-Content $settingsFile -Raw | ConvertFrom-Json
        } catch {
            return $defaultSettings
        }
    } else {
        return $defaultSettings
    }
}

function Set-Settings {
    param(
        [Parameter(Mandatory)] $Body
    )
    $settingsFile = Join-Path $script:Config.ControlDir "ui-settings.json"
    $defaultSettings = @{
        showDebug = $false
        showVerbose = $false
        analysisModel = "Opus"
        executionModel = "Opus"
    }

    # Load existing settings into defaults hashtable
    $settings = $defaultSettings.Clone()
    if (Test-Path $settingsFile) {
        try {
            $existingSettings = Get-Content $settingsFile -Raw | ConvertFrom-Json
            foreach ($prop in $existingSettings.PSObject.Properties) {
                $settings[$prop.Name] = $prop.Value
            }
        } catch { }
    }

    # Update settings with provided values
    if ($null -ne $Body.showDebug) {
        $settings.showDebug = [bool]$Body.showDebug
    }
    if ($null -ne $Body.showVerbose) {
        $settings.showVerbose = [bool]$Body.showVerbose
    }
    if ($null -ne $Body.analysisModel) {
        $settings.analysisModel = [string]$Body.analysisModel
    }
    if ($null -ne $Body.executionModel) {
        $settings.executionModel = [string]$Body.executionModel
    }

    # Save settings
    $settings | ConvertTo-Json | Set-Content $settingsFile -Force
    Write-Status "Settings updated: Debug=$($settings.showDebug), Verbose=$($settings.showVerbose)" -Type Success

    return @{
        success = $true
        settings = $settings
    }
}

function Get-AnalysisConfig {
    $settingsDefaultFile = Join-Path $script:Config.BotRoot "defaults\settings.default.json"

    try {
        $settingsData = Get-Content $settingsDefaultFile -Raw | ConvertFrom-Json
        $analysis = if ($settingsData.analysis) { $settingsData.analysis } else {
            @{ auto_approve_splits = $false; split_threshold_effort = "XL"; question_timeout_hours = $null; mode = "on-demand" }
        }
        return $analysis
    } catch {
        return @{ _statusCode = 500; error = "Failed to read analysis config: $($_.Exception.Message)" }
    }
}

function Set-AnalysisConfig {
    param(
        [Parameter(Mandatory)] $Body
    )
    $settingsDefaultFile = Join-Path $script:Config.BotRoot "defaults\settings.default.json"

    $settingsData = Get-Content $settingsDefaultFile -Raw | ConvertFrom-Json
    if (-not $settingsData.analysis) {
        $settingsData | Add-Member -NotePropertyName "analysis" -NotePropertyValue @{
            auto_approve_splits = $false
            split_threshold_effort = "XL"
            question_timeout_hours = $null
            mode = "on-demand"
        }
    }

    if ($null -ne $Body.auto_approve_splits) {
        $settingsData.analysis.auto_approve_splits = [bool]$Body.auto_approve_splits
    }
    if ($null -ne $Body.split_threshold_effort) {
        $settingsData.analysis.split_threshold_effort = [string]$Body.split_threshold_effort
    }
    if ($Body.PSObject.Properties.Name -contains 'question_timeout_hours') {
        if ($null -eq $Body.question_timeout_hours) {
            $settingsData.analysis.question_timeout_hours = $null
        } else {
            $settingsData.analysis.question_timeout_hours = [int]$Body.question_timeout_hours
        }
    }
    if ($null -ne $Body.mode) {
        $settingsData.analysis.mode = [string]$Body.mode
    }

    $settingsData | ConvertTo-Json -Depth 5 | Set-Content $settingsDefaultFile -Force
    Write-Status "Analysis config updated" -Type Success

    return @{
        success = $true
        analysis = $settingsData.analysis
    }
}

function Get-VerificationConfig {
    $verifyConfigFile = Join-Path $script:Config.BotRoot "hooks\verify\config.json"

    try {
        return Get-Content $verifyConfigFile -Raw | ConvertFrom-Json
    } catch {
        return @{ _statusCode = 500; error = "Failed to read verification config: $($_.Exception.Message)" }
    }
}

function Set-VerificationConfig {
    param(
        [Parameter(Mandatory)] $Body
    )
    $verifyConfigFile = Join-Path $script:Config.BotRoot "hooks\verify\config.json"

    $verifyData = Get-Content $verifyConfigFile -Raw | ConvertFrom-Json
    $scriptName = $Body.name

    # Find the script entry
    $scriptEntry = $verifyData.scripts | Where-Object { $_.name -eq $scriptName }
    if (-not $scriptEntry) {
        return @{ _statusCode = 404; success = $false; error = "Script not found: $scriptName" }
    }
    elseif ($scriptEntry.core -eq $true) {
        return @{ _statusCode = 400; success = $false; error = "Cannot modify core verification script: $scriptName" }
    }

    $scriptEntry.required = [bool]$Body.required
    $verifyData | ConvertTo-Json -Depth 5 | Set-Content $verifyConfigFile -Force
    Write-Status "Verification config updated: $scriptName required=$($scriptEntry.required)" -Type Success

    return @{
        success = $true
        scripts = $verifyData.scripts
    }
}

Export-ModuleMember -Function @(
    'Initialize-SettingsAPI',
    'Get-Theme',
    'Set-Theme',
    'Get-Settings',
    'Set-Settings',
    'Get-AnalysisConfig',
    'Set-AnalysisConfig',
    'Get-VerificationConfig',
    'Set-VerificationConfig'
)
