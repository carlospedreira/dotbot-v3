<#
.SYNOPSIS
Cleanup utilities for temporary Claude directories

.DESCRIPTION
Provides functions for cleaning up temporary directories created during Claude sessions
#>

function Clear-TemporaryClaudeDirectories {
    <#
    .SYNOPSIS
    Remove temporary Claude directories from the project root
    
    .PARAMETER ProjectRoot
    Path to the project root directory
    
    .OUTPUTS
    Integer count of directories removed
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )
    
    $tmpClaudeDirs = Get-ChildItem -Path $ProjectRoot -Filter "tmpclaude-*-cwd" -ErrorAction SilentlyContinue
    
    if ($tmpClaudeDirs) {
        $count = $tmpClaudeDirs.Count
        foreach ($dir in $tmpClaudeDirs) {
            Remove-Item -Path $dir.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
        return $count
    }
    
    return 0
}
