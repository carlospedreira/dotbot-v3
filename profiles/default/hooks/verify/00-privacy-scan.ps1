param(
    [string]$TaskId,
    [string]$Category
)

# Scan .bot/workspace for sensitive data before commit
$issues = @()
$details = @{
    files_scanned = 0
    violations = @()
}

# Patterns to detect
$patterns = @(
    # Local paths (Windows/macOS/Linux)
    @{ name = "windows_user_path"; pattern = '[A-Za-z]:[/\\]+Users[/\\]+\w+'; description = "Windows user path"; caseSensitive = $false }
    @{ name = "linux_home_path"; pattern = '/home/\w+'; description = "Linux home path"; caseSensitive = $true }
    @{ name = "macos_user_path"; pattern = '/Users/\w+'; description = "macOS user path"; caseSensitive = $true }
    
    # Secrets and credentials
    @{ name = "api_key_value"; pattern = '(?:api[_-]?key|apikey)\s*[=:]\s*["\u0027]?[A-Za-z0-9_\-]{20,}'; description = "API key value"; caseSensitive = $false }
    @{ name = "secret_value"; pattern = '(?:secret|password|passwd|pwd)\s*[=:]\s*["\u0027]?[^\s"]{8,}'; description = "Secret/password value"; caseSensitive = $false }
    @{ name = "bearer_token"; pattern = 'Bearer\s+[A-Za-z0-9_\-\.]+'; description = "Bearer token"; caseSensitive = $false }
    @{ name = "connection_string"; pattern = '(?:Server|Data Source|mongodb\+srv|postgresql|mysql)://[^\s"]+'; description = "Connection string"; caseSensitive = $false }
    
    # Cloud credentials
    @{ name = "aws_key"; pattern = 'AKIA[0-9A-Z]{16}'; description = "AWS access key"; caseSensitive = $true }
    @{ name = "azure_key"; pattern = '(?:AccountKey|SharedAccessSignature)\s*=\s*[A-Za-z0-9+/=]{40,}'; description = "Azure key"; caseSensitive = $false }
)

# Files/paths to exclude from scanning
$excludePatterns = @(
    '\.git[/\\]',
    'node_modules[/\\]',
    '\.vs[/\\]',
    'bin[/\\]',
    'obj[/\\]'
)

# Scan directories
$scanPaths = @(
    ".bot/workspace/tasks",
    ".bot/workspace/plans"
)

$repoRoot = git rev-parse --show-toplevel 2>$null
if (-not $repoRoot) {
    $repoRoot = Get-Location
}

foreach ($scanPath in $scanPaths) {
    $fullPath = Join-Path $repoRoot $scanPath
    if (-not (Test-Path $fullPath)) {
        continue
    }
    
    $files = Get-ChildItem -Path $fullPath -Recurse -File -Include "*.json", "*.md", "*.yaml", "*.yml" -ErrorAction SilentlyContinue
    
    foreach ($file in $files) {
        # Skip excluded paths
        $skip = $false
        foreach ($exclude in $excludePatterns) {
            if ($file.FullName -match $exclude) {
                $skip = $true
                break
            }
        }
        if ($skip) { continue }
        
        $details['files_scanned']++
        $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
        if (-not $content) { continue }
        
        $lineNumber = 0
        $lines = $content -split "`n"
        
        foreach ($line in $lines) {
            $lineNumber++
            
            foreach ($patternDef in $patterns) {
                # Check if pattern matches (case-sensitive or case-insensitive)
                $matches = if ($patternDef.caseSensitive) {
                    $line -cmatch $patternDef.pattern
                } else {
                    $line -match $patternDef.pattern
                }
                
                if ($matches) {
                    $relativePath = $file.FullName.Replace($repoRoot, "").TrimStart("/\")
                    $violation = @{
                        file = $relativePath
                        line = $lineNumber
                        pattern = $patternDef.name
                        description = $patternDef.description
                        snippet = if ($line.Length -gt 100) { $line.Substring(0, 100) + "..." } else { $line.Trim() }
                    }
                    $details['violations'] += $violation
                    
                    $issues += @{
                        issue = "$($patternDef.description) in $relativePath`:$lineNumber"
                        severity = "error"
                        context = "Remove or redact sensitive data before committing"
                    }
                }
            }
        }
    }
}

# Deduplicate issues (same file/line can match multiple patterns)
$uniqueIssues = $issues | Sort-Object { "$($_.issue)" } -Unique

@{
    success = ($uniqueIssues.Count -eq 0)
    script = "00-privacy-scan.ps1"
    message = if ($uniqueIssues.Count -eq 0) { "No sensitive data detected" } else { "$($uniqueIssues.Count) privacy violation(s) found" }
    details = $details
    failures = @($uniqueIssues)
} | ConvertTo-Json -Depth 10
