# DOTBOT Control Panel - PowerShell Theme
# Oscilloscope aesthetic with Axiome amber accents
# Reads colors from theme-config.json for consistency with UI

# Helper function to load theme configuration
function Get-ThemeFromConfig {
    # Read from UI theme config (synced with web UI), fallback to defaults
    $uiThemePath = Join-Path $PSScriptRoot "..\..\ui\static\theme-config.json"
    $defaultThemePath = Join-Path $PSScriptRoot "..\..\..\defaults\theme.default.json"

    $configPath = if (Test-Path $uiThemePath) { $uiThemePath } else { $defaultThemePath }
    if (-not (Test-Path $configPath)) { return $null }

    try {
        $config = Get-Content $configPath -Raw | ConvertFrom-Json
        return $config.mappings
    } catch {
        return $null
    }
}

# Try to load from config, fall back to hardcoded values
$configMappings = Get-ThemeFromConfig

if ($configMappings) {
    # Build theme from config file
    $script:Theme = @{
        # Primary semantic colors from config
        Primary     = $PSStyle.Foreground.FromRgb($configMappings.primary.r, $configMappings.primary.g, $configMappings.primary.b)
        PrimaryDim  = $PSStyle.Foreground.FromRgb($configMappings.'primary-dim'.r, $configMappings.'primary-dim'.g, $configMappings.'primary-dim'.b)
        Secondary   = $PSStyle.Foreground.FromRgb($configMappings.secondary.r, $configMappings.secondary.g, $configMappings.secondary.b)
        Tertiary    = $PSStyle.Foreground.FromRgb($configMappings.tertiary.r, $configMappings.tertiary.g, $configMappings.tertiary.b)
        Success     = $PSStyle.Foreground.FromRgb($configMappings.success.r, $configMappings.success.g, $configMappings.success.b)
        SuccessDim  = $PSStyle.Foreground.FromRgb($configMappings.'success-dim'.r, $configMappings.'success-dim'.g, $configMappings.'success-dim'.b)
        Error       = $PSStyle.Foreground.FromRgb($configMappings.error.r, $configMappings.error.g, $configMappings.error.b)
        Warning     = $PSStyle.Foreground.FromRgb($configMappings.warning.r, $configMappings.warning.g, $configMappings.warning.b)
        Info        = $PSStyle.Foreground.FromRgb($configMappings.info.r, $configMappings.info.g, $configMappings.info.b)
        Muted       = $PSStyle.Foreground.FromRgb($configMappings.muted.r, $configMappings.muted.g, $configMappings.muted.b)
        Bezel       = $PSStyle.Foreground.FromRgb($configMappings.bezel.r, $configMappings.bezel.g, $configMappings.bezel.b)

        Reset       = $PSStyle.Reset
    }

    # Legacy aliases for backward compatibility
    $script:Theme.Amber     = $script:Theme.Primary
    $script:Theme.AmberDim  = $script:Theme.PrimaryDim
    $script:Theme.Green     = $script:Theme.Success
    $script:Theme.GreenDim  = $script:Theme.SuccessDim
    $script:Theme.Cyan      = $script:Theme.Secondary
    $script:Theme.Red       = $script:Theme.Error
    $script:Theme.Blue      = $script:Theme.Info
    $script:Theme.Purple    = $script:Theme.Tertiary
    $script:Theme.Label     = $script:Theme.Muted
} else {
    # Fallback to hardcoded values if config not found
    $script:Theme = @{
        # Primary phosphor colors (hardcoded fallback)
        Amber       = $PSStyle.Foreground.FromRgb(232, 160, 48)   # #e8a030
        AmberDim    = $PSStyle.Foreground.FromRgb(184, 120, 32)   # #b87820
        Green       = $PSStyle.Foreground.FromRgb(0, 255, 136)    # #00ff88
        GreenDim    = $PSStyle.Foreground.FromRgb(0, 170, 92)     # #00aa5c
        Cyan        = $PSStyle.Foreground.FromRgb(95, 179, 179)   # #5fb3b3
        Red         = $PSStyle.Foreground.FromRgb(209, 105, 105)  # #d16969
        Blue        = $PSStyle.Foreground.FromRgb(68, 136, 255)   # #4488ff
        Purple      = $PSStyle.Foreground.FromRgb(170, 136, 255)  # #aa88ff

        # UI chrome colors
        Label       = $PSStyle.Foreground.FromRgb(136, 136, 153)  # #888899
        Bezel       = $PSStyle.Foreground.FromRgb(58, 59, 72)     # #3a3b48

        Reset       = $PSStyle.Reset
    }

    # Semantic aliases matching CSS usage
    $script:Theme.Primary   = $script:Theme.Amber
    $script:Theme.PrimaryDim = $script:Theme.AmberDim
    $script:Theme.Secondary = $script:Theme.Cyan
    $script:Theme.Tertiary  = $script:Theme.Purple
    $script:Theme.Success   = $script:Theme.Green
    $script:Theme.SuccessDim = $script:Theme.GreenDim
    $script:Theme.Error     = $script:Theme.Red
    $script:Theme.Warning   = $script:Theme.Amber
    $script:Theme.Info      = $script:Theme.Cyan
    $script:Theme.Muted     = $script:Theme.Label
}

function Get-DotBotTheme {
    <#
    .SYNOPSIS
    Returns the DOTBOT theme hashtable for direct use
    #>
    return $script:Theme
}

function Write-Phosphor {
    <#
    .SYNOPSIS
    Write colored output using DOTBOT phosphor colors
    
    .PARAMETER Message
    The message to display
    
    .PARAMETER Color
    Color name: Amber, AmberDim, Green, GreenDim, Cyan, Red, Blue, Purple, Label
    
    .PARAMETER NoNewline
    Don't add newline at end
    #>
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Message,
        
        [Parameter(Position = 1)]
        [ValidateSet('Amber', 'AmberDim', 'Green', 'GreenDim', 'Cyan', 'Red', 'Blue', 'Purple', 'Label', 'Bezel')]
        [string]$Color = 'Amber',
        
        [switch]$NoNewline
    )
    
    $c = $script:Theme[$Color]
    $r = $script:Theme.Reset
    
    if ($NoNewline) {
        Write-Host "${c}${Message}${r}" -NoNewline
    } else {
        Write-Host "${c}${Message}${r}"
    }
}

function Write-Status {
    <#
    .SYNOPSIS
    Write a status message with icon prefix (oscilloscope style)
    
    .PARAMETER Message
    The message to display
    
    .PARAMETER Type
    Status type: Info, Success, Error, Warn, Process, Complete
    #>
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Message,
        
        [Parameter(Position = 1)]
        [ValidateSet('Info', 'Success', 'Error', 'Warn', 'Process', 'Complete')]
        [string]$Type = 'Info'
    )
    
    $icons = @{
        Info     = '›'
        Success  = '✓'
        Error    = '✗'
        Warn     = '⚠'
        Process  = '◆'
        Complete = '●'
    }
    
    $colors = @{
        Info     = $script:Theme.Cyan
        Success  = $script:Theme.Green
        Error    = $script:Theme.Red
        Warn     = $script:Theme.Amber
        Process  = $script:Theme.Amber
        Complete = $script:Theme.Green
    }
    
    $icon = $icons[$Type]
    $iconColor = $colors[$Type]
    $textColor = $script:Theme.Amber
    $r = $script:Theme.Reset
    
    Write-Host "${iconColor}${icon}${r} ${textColor}${Message}${r}"
}

function Write-Label {
    <#
    .SYNOPSIS
    Write a label: value pair (like sidebar items)
    #>
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Label,
        
        [Parameter(Mandatory, Position = 1)]
        [string]$Value,
        
        [ValidateSet('Amber', 'Green', 'Cyan', 'Red', 'Blue', 'Purple')]
        [string]$ValueColor = 'Amber'
    )
    
    $labelC = $script:Theme.Label
    $valueC = $script:Theme[$ValueColor]
    $r = $script:Theme.Reset
    
    Write-Host "${labelC}${Label}: ${r}${valueC}${Value}${r}"
}

function Write-Header {
    <#
    .SYNOPSIS
    Write a section header (uppercase, letter-spaced like CSS)
    #>
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Text
    )
    
    $c = $script:Theme.AmberDim
    $r = $script:Theme.Reset
    $formatted = ($Text.ToUpper().ToCharArray() -join ' ')
    
    Write-Host ""
    Write-Host "${c}── ${formatted} ──${r}"
    Write-Host ""
}

function Write-Led {
    <#
    .SYNOPSIS
    Write an LED indicator status line
    #>
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Label,
        
        [Parameter(Position = 1)]
        [ValidateSet('On', 'Off', 'Warn', 'Error')]
        [string]$State = 'On',
        
        [ValidateSet('Green', 'Amber', 'Cyan', 'Red')]
        [string]$Color = 'Green'
    )
    
    $ledColors = @{
        On    = $script:Theme[$Color]
        Off   = $script:Theme.Bezel
        Warn  = $script:Theme.Amber
        Error = $script:Theme.Red
    }
    
    $ledChars = @{
        On    = '●'
        Off   = '○'
        Warn  = '●'
        Error = '●'
    }
    
    $led = $ledColors[$State]
    $char = $ledChars[$State]
    $label = $script:Theme.Label
    $r = $script:Theme.Reset
    
    Write-Host "${led}${char}${r} ${label}${Label}${r}"
}

function Write-Separator {
    <#
    .SYNOPSIS
    Write a subtle separator line
    #>
    param(
        [int]$Width = 40
    )
    
    $c = $script:Theme.Bezel
    $r = $script:Theme.Reset
    Write-Host "${c}$('─' * $Width)${r}"
}

function Write-Banner {
    <#
    .SYNOPSIS
    Write the DOTBOT banner/logo
    #>
    param(
        [string]$Title = "DOTBOT",
        [string]$Subtitle = "",
        [int]$Width = 40
    )
    
    $amber = $script:Theme.Amber
    $dim = $script:Theme.AmberDim
    $r = $script:Theme.Reset
    
    $innerWidth = $Width - 2  # Account for ║ on each side
    $contentWidth = $innerWidth - 4  # Account for "  " padding on each side
    
    Write-Host ""
    Write-Host "${amber}╔$('═' * $innerWidth)╗${r}"
    Write-Host "${amber}║${r}  ${amber}$(Get-PaddedText -Text $Title -Width $contentWidth)${r}  ${amber}║${r}"
    if ($Subtitle) {
        Write-Host "${amber}║${r}  ${dim}$(Get-PaddedText -Text $Subtitle -Width $contentWidth)${r}  ${amber}║${r}"
    }
    Write-Host "${amber}╚$('═' * $innerWidth)╝${r}"
    Write-Host ""
}

# ═══════════════════════════════════════════════════════════════════
# BOX DRAWING - ANSI-aware width handling
# ═══════════════════════════════════════════════════════════════════

# Box character sets
$script:BoxChars = @{
    Rounded = @{
        TL = '╭'; TR = '╮'; BL = '╰'; BR = '╯'
        H  = '─'; V  = '│'
        LT = '├'; RT = '┤'; TT = '┬'; BT = '┴'; X = '┼'
    }
    Square = @{
        TL = '┌'; TR = '┐'; BL = '└'; BR = '┘'
        H  = '─'; V  = '│'
        LT = '├'; RT = '┤'; TT = '┬'; BT = '┴'; X = '┼'
    }
    Double = @{
        TL = '╔'; TR = '╗'; BL = '╚'; BR = '╝'
        H  = '═'; V  = '║'
        LT = '╠'; RT = '╣'; TT = '╦'; BT = '╩'; X = '╬'
    }
    Heavy = @{
        TL = '┏'; TR = '┓'; BL = '┗'; BR = '┛'
        H  = '━'; V  = '┃'
        LT = '┣'; RT = '┫'; TT = '┳'; BT = '┻'; X = '╋'
    }
}

function Get-VisualWidth {
    <#
    .SYNOPSIS
    Get the visual width of a string, ignoring ANSI escape sequences
    #>
    param([string]$Text)
    ($Text -replace '\x1b\[[0-9;]*m', '').Length
}

function Get-PaddedText {
    <#
    .SYNOPSIS
    Pad text to a visual width, accounting for ANSI codes
    #>
    param(
        [string]$Text,
        [int]$Width,
        [string]$PadChar = ' ',
        [ValidateSet('Left', 'Right', 'Center')]
        [string]$Align = 'Left'
    )
    
    $visual = Get-VisualWidth $Text
    $totalPad = [Math]::Max(0, $Width - $visual)
    
    switch ($Align) {
        'Left'   { return $Text + ($PadChar * $totalPad) }
        'Right'  { return ($PadChar * $totalPad) + $Text }
        'Center' {
            $left = [Math]::Floor($totalPad / 2)
            $right = $totalPad - $left
            return ($PadChar * $left) + $Text + ($PadChar * $right)
        }
    }
}

function Write-Card {
    <#
    .SYNOPSIS
    Draw a card with rounded (or other style) borders
    
    .PARAMETER Title
    Optional title in the top border
    
    .PARAMETER Lines
    Array of content lines (can include ANSI colors)
    
    .PARAMETER Width
    Total width of the card including borders
    
    .PARAMETER BorderStyle
    Border style: Rounded, Square, Double, Heavy
    
    .PARAMETER BorderColor
    Color for the border from theme
    
    .PARAMETER TitleColor
    Color for the title from theme
    
    .PARAMETER Padding
    Internal horizontal padding (default 1)
    #>
    param(
        [string]$Title = "",
        [string[]]$Lines = @(),
        [int]$Width = 40,
        [ValidateSet('Rounded', 'Square', 'Double', 'Heavy')]
        [string]$BorderStyle = 'Rounded',
        [string]$BorderColor = 'AmberDim',
        [string]$TitleColor = 'Amber',
        [int]$Padding = 1
    )
    
    $t = $script:Theme
    $bc = $t[$BorderColor]
    $tc = $t[$TitleColor]
    $r = $t.Reset
    $box = $script:BoxChars[$BorderStyle]
    
    $innerWidth = $Width - 2  # account for │ on each side
    $contentWidth = $innerWidth - ($Padding * 2)
    $pad = ' ' * $Padding
    
    # Top border
    if ($Title) {
        $titleText = " $Title "
        $titleVis = Get-VisualWidth $titleText
        $remaining = [Math]::Max(0, $innerWidth - $titleVis - 1)  # -1 for left dash
        $top = "${bc}$($box.TL)$($box.H)${r}${tc}${titleText}${r}${bc}$($box.H * $remaining)$($box.TR)${r}"
    } else {
        $top = "${bc}$($box.TL)$($box.H * $innerWidth)$($box.TR)${r}"
    }
    Write-Host $top
    
    # Content lines
    foreach ($line in $Lines) {
        $padded = Get-PaddedText -Text $line -Width $contentWidth
        Write-Host "${bc}$($box.V)${r}${pad}${padded}${pad}${bc}$($box.V)${r}"
    }
    
    # Bottom border
    Write-Host "${bc}$($box.BL)$($box.H * $innerWidth)$($box.BR)${r}"
}

function Write-CardRow {
    <#
    .SYNOPSIS
    Draw multiple cards side by side
    
    .PARAMETER Cards
    Array of hashtables, each with: Title, Lines, Width (optional)
    
    .PARAMETER Gap
    Space between cards
    #>
    param(
        [hashtable[]]$Cards,
        [int]$Gap = 2,
        [ValidateSet('Rounded', 'Square', 'Double', 'Heavy')]
        [string]$BorderStyle = 'Rounded',
        [string]$BorderColor = 'AmberDim',
        [string]$TitleColor = 'Amber'
    )
    
    $t = $script:Theme
    $bc = $t[$BorderColor]
    $tc = $t[$TitleColor]
    $r = $t.Reset
    $box = $script:BoxChars[$BorderStyle]
    $gapStr = ' ' * $Gap
    
    # Normalize cards - ensure all have Width and Lines
    $normalizedCards = foreach ($card in $Cards) {
        @{
            Title = $card.Title ?? ""
            Lines = $card.Lines ?? @()
            Width = $card.Width ?? 30
        }
    }
    
    # Find max lines
    $maxLines = ($normalizedCards | ForEach-Object { $_.Lines.Count } | Measure-Object -Maximum).Maximum
    $maxLines = [Math]::Max($maxLines, 1)
    
    # Build each row
    # Top borders
    $topRow = ""
    foreach ($card in $normalizedCards) {
        $innerWidth = $card.Width - 2
        if ($card.Title) {
            $titleText = " $($card.Title) "
            $titleVis = Get-VisualWidth $titleText
            $remaining = [Math]::Max(0, $innerWidth - $titleVis - 1)
            $topRow += "${bc}$($box.TL)$($box.H)${r}${tc}${titleText}${r}${bc}$($box.H * $remaining)$($box.TR)${r}${gapStr}"
        } else {
            $topRow += "${bc}$($box.TL)$($box.H * $innerWidth)$($box.TR)${r}${gapStr}"
        }
    }
    Write-Host $topRow.TrimEnd()
    
    # Content rows
    for ($i = 0; $i -lt $maxLines; $i++) {
        $contentRow = ""
        foreach ($card in $normalizedCards) {
            $innerWidth = $card.Width - 2
            $line = if ($i -lt $card.Lines.Count) { " $($card.Lines[$i])" } else { "" }
            $padded = Get-PaddedText -Text $line -Width ($innerWidth - 1)
            $contentRow += "${bc}$($box.V)${r}${padded} ${bc}$($box.V)${r}${gapStr}"
        }
        Write-Host $contentRow.TrimEnd()
    }
    
    # Bottom borders
    $bottomRow = ""
    foreach ($card in $normalizedCards) {
        $innerWidth = $card.Width - 2
        $bottomRow += "${bc}$($box.BL)$($box.H * $innerWidth)$($box.BR)${r}${gapStr}"
    }
    Write-Host $bottomRow.TrimEnd()
}

function Write-Table {
    <#
    .SYNOPSIS
    Draw a table with headers and rows
    
    .PARAMETER Headers
    Array of column headers
    
    .PARAMETER Rows
    Array of arrays, each inner array is a row. Use comma prefix for single-row tables.
    
    .PARAMETER ColumnWidths
    Array of widths for each column (auto-calculated if not provided)
    
    .EXAMPLE
    Write-Table -Headers @("Name", "Status") -Rows @(
        ,@("Task 1", "Done")
        ,@("Task 2", "Pending")
    )
    #>
    param(
        [string[]]$Headers,
        [Parameter(Mandatory)]
        $Rows,
        [int[]]$ColumnWidths = @(),
        [ValidateSet('Rounded', 'Square', 'Double', 'Heavy')]
        [string]$BorderStyle = 'Rounded',
        [string]$BorderColor = 'AmberDim',
        [string]$HeaderColor = 'Amber'
    )
    
    $t = $script:Theme
    $bc = $t[$BorderColor]
    $hc = $t[$HeaderColor]
    $rs = $t.Reset
    $box = $script:BoxChars[$BorderStyle]
    
    # Normalize rows - ensure we have an array of arrays
    $normalizedRows = @()
    foreach ($row in $Rows) {
        # Force each row into array context
        $normalizedRows += ,@($row)
    }
    
    # Auto-calculate column widths if not provided
    if ($ColumnWidths.Count -eq 0) {
        $ColumnWidths = @()
        for ($i = 0; $i -lt $Headers.Count; $i++) {
            $maxWidth = Get-VisualWidth $Headers[$i]
            foreach ($row in $normalizedRows) {
                if ($i -lt $row.Count) {
                    $cellWidth = Get-VisualWidth "$($row[$i])"
                    if ($cellWidth -gt $maxWidth) { $maxWidth = $cellWidth }
                }
            }
            $ColumnWidths += ($maxWidth + 2)  # padding
        }
    }
    
    # Top border
    $top = "${bc}$($box.TL)"
    for ($i = 0; $i -lt $ColumnWidths.Count; $i++) {
        $top += "$($box.H * $ColumnWidths[$i])"
        if ($i -lt $ColumnWidths.Count - 1) { $top += "$($box.TT)" }
    }
    $top += "$($box.TR)${rs}"
    Write-Host $top
    
    # Header row
    $headerRow = "${bc}$($box.V)${rs}"
    for ($i = 0; $i -lt $Headers.Count; $i++) {
        $cell = Get-PaddedText -Text " $($Headers[$i])" -Width ($ColumnWidths[$i] - 1)
        $headerRow += "${hc}${cell}${rs} ${bc}$($box.V)${rs}"
    }
    Write-Host $headerRow
    
    # Header separator
    $sep = "${bc}$($box.LT)"
    for ($i = 0; $i -lt $ColumnWidths.Count; $i++) {
        $sep += "$($box.H * $ColumnWidths[$i])"
        if ($i -lt $ColumnWidths.Count - 1) { $sep += "$($box.X)" }
    }
    $sep += "$($box.RT)${rs}"
    Write-Host $sep
    
    # Data rows
    foreach ($row in $normalizedRows) {
        $dataRow = "${bc}$($box.V)${rs}"
        for ($i = 0; $i -lt $ColumnWidths.Count; $i++) {
            $cellContent = if ($i -lt $row.Count) { " $($row[$i])" } else { " " }
            $cell = Get-PaddedText -Text $cellContent -Width ($ColumnWidths[$i] - 1)
            $dataRow += "${cell} ${bc}$($box.V)${rs}"
        }
        Write-Host $dataRow
    }
    
    # Bottom border
    $bottom = "${bc}$($box.BL)"
    for ($i = 0; $i -lt $ColumnWidths.Count; $i++) {
        $bottom += "$($box.H * $ColumnWidths[$i])"
        if ($i -lt $ColumnWidths.Count - 1) { $bottom += "$($box.BT)" }
    }
    $bottom += "$($box.BR)${rs}"
    Write-Host $bottom
}

function Write-ProgressCard {
    <#
    .SYNOPSIS
    Draw a progress bar inside a card
    #>
    param(
        [string]$Title = "Progress",
        [int]$Percent = 0,
        [int]$Width = 40,
        [string]$BarColor = 'Green',
        [string]$EmptyColor = 'Bezel',
        [ValidateSet('Rounded', 'Square', 'Double', 'Heavy')]
        [string]$BorderStyle = 'Rounded'
    )
    
    $t = $script:Theme
    $barC = $t[$BarColor]
    $emptyC = $t[$EmptyColor]
    $r = $t.Reset
    
    $innerWidth = $Width - 4  # borders + padding
    $filled = [Math]::Floor($innerWidth * ($Percent / 100))
    $empty = $innerWidth - $filled
    
    $bar = "${barC}$('█' * $filled)${r}${emptyC}$('░' * $empty)${r}"
    $percentText = "${Percent}%"
    
    Write-Card -Title $Title -Width $Width -BorderStyle $BorderStyle -Lines @(
        $bar
        (Get-PaddedText -Text $percentText -Width $innerWidth -Align Center)
    )
}

function Write-Panel {
    <#
    .SYNOPSIS
    Draw a simple panel with just a border (no title support, minimal overhead)
    #>
    param(
        [string[]]$Lines,
        [int]$Width = 0,
        [ValidateSet('Rounded', 'Square', 'Double', 'Heavy')]
        [string]$BorderStyle = 'Rounded',
        [string]$BorderColor = 'Bezel'
    )
    
    $t = $script:Theme
    $bc = $t[$BorderColor]
    $r = $t.Reset
    $box = $script:BoxChars[$BorderStyle]
    
    # Auto-width if not specified
    if ($Width -eq 0) {
        $Width = ($Lines | ForEach-Object { Get-VisualWidth $_ } | Measure-Object -Maximum).Maximum + 4
    }
    
    $innerWidth = $Width - 2
    
    Write-Host "${bc}$($box.TL)$($box.H * $innerWidth)$($box.TR)${r}"
    foreach ($line in $Lines) {
        $padded = Get-PaddedText -Text " $line" -Width ($innerWidth - 1)
        Write-Host "${bc}$($box.V)${r}${padded} ${bc}$($box.V)${r}"
    }
    Write-Host "${bc}$($box.BL)$($box.H * $innerWidth)$($box.BR)${r}"
}

# Export functions
Export-ModuleMember -Function @(
    'Get-DotBotTheme'
    'Write-Phosphor'
    'Write-Status'
    'Write-Label'
    'Write-Header'
    'Write-Led'
    'Write-Separator'
    'Write-Banner'
    'Get-VisualWidth'
    'Get-PaddedText'
    'Write-Card'
    'Write-CardRow'
    'Write-Table'
    'Write-ProgressCard'
    'Write-Panel'
)
