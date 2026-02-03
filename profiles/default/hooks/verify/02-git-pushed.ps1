param(
    [string]$TaskId,
    [string]$Category
)

# Check for unpushed commits
$issues = @()
$details = @{}

try {
    $currentBranch = git rev-parse --abbrev-ref HEAD 2>$null
    $details['branch'] = $currentBranch
    
    $aheadCount = git rev-list --count "origin/$currentBranch..HEAD" 2>$null
    if ($LASTEXITCODE -eq 0 -and $aheadCount -gt 0) {
        $details['unpushed_commits'] = [int]$aheadCount
        $issues += @{
            issue = "$aheadCount unpushed commit(s) on '$currentBranch'"
            severity = "error"
            context = "Push changes: git push origin $currentBranch"
        }
    } else {
        $details['unpushed_commits'] = 0
    }
} catch {
    $issues += @{
        issue = "Failed to check push status: $($_.Exception.Message)"
        severity = "error"
    }
}

@{
    success = ($issues.Count -eq 0)
    script = "02-git-pushed.ps1"
    message = if ($issues.Count -eq 0) { "All commits pushed" } else { "Unpushed commits found" }
    details = $details
    failures = $issues
} | ConvertTo-Json -Depth 10
