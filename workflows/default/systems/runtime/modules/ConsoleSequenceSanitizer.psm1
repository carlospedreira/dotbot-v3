<#
.SYNOPSIS
Console/control sequence sanitization helpers.

.DESCRIPTION
Strips ANSI escape sequences and orphaned CSI fragments from status text so
terminal formatting artifacts do not leak into persisted process metadata or UI
rendering paths.
#>

$script:ConsoleSequencePattern = "(\x1B\[[0-9;?]*[ -/]*[@-~])|(\[[0-9;?]*[ -/]*[@-~])"

function Remove-ConsoleSequences {
    param(
        [AllowNull()]
        [object]$Text
    )

    if ($null -eq $Text) {
        return $null
    }

    $clean = [regex]::Replace([string]$Text, $script:ConsoleSequencePattern, "")
    return $clean.Trim()
}

function Normalize-ConsoleSequenceText {
    param(
        [AllowNull()]
        [object]$Text
    )

    $clean = Remove-ConsoleSequences $Text
    if ([string]::IsNullOrWhiteSpace($clean)) {
        return $null
    }

    return $clean
}

Export-ModuleMember -Function @('Remove-ConsoleSequences', 'Normalize-ConsoleSequenceText')
