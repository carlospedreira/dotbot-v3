# Query-Db.ps1
# Query the Lintilla SQLite database (read-only)

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("dev", "prod")]
    [string]$Environment = "dev",
    
    [Parameter(Mandatory=$false)]
    [string]$Query,
    
    [Parameter(Mandatory=$false)]
    [string]$Table,
    
    [Parameter(Mandatory=$false)]
    [int]$Limit = 20
)

. "$PSScriptRoot/Common.ps1"

# Mutation keywords to block (read-only mode)
$mutationKeywords = @(
    'INSERT', 'UPDATE', 'DELETE', 'DROP', 'ALTER', 'CREATE', 'TRUNCATE',
    'REPLACE', 'ATTACH', 'DETACH', 'VACUUM', 'REINDEX'
)

function Test-ReadOnlyQuery {
    param([string]$Sql)
    
    $upperSql = $Sql.ToUpper()
    foreach ($keyword in $mutationKeywords) {
        if ($upperSql -match "\b$keyword\b") {
            return $false
        }
    }
    return $true
}

function Get-CompactSchema {
    param(
        [string]$DbPath,
        [string]$Sqlite3Cmd = "sqlite3",
        [switch]$Remote,
        [string]$SshTarget
    )
    
    # Query to get all tables and their columns in compact format
    $schemaQuery = @"
SELECT m.name || '(' || GROUP_CONCAT(p.name, ', ') || ')'
FROM sqlite_master m
JOIN pragma_table_info(m.name) p
WHERE m.type = 'table' AND m.name NOT LIKE 'sqlite_%'
GROUP BY m.name
ORDER BY m.name;
"@
    
    if ($Remote) {
        $result = ssh $SshTarget "$Sqlite3Cmd `"$DbPath`" `"$schemaQuery`"" 2>$null
    }
    else {
        $result = & $Sqlite3Cmd $DbPath $schemaQuery 2>$null
    }
    
    return $result
}

function Test-SchemaError {
    param([string]$ErrorOutput)
    
    # Match common SQLite schema errors
    return $ErrorOutput -match "no such table|no such column|no column named|table .* has no column"
}

$repoRoot = Invoke-InProjectRoot

Write-Host ""
Write-Host "Lintilla Database Query ($Environment)" -ForegroundColor White
Write-Host "================================" -ForegroundColor White
Write-Host ""

# Build query from parameters
if (-not $Query -and -not $Table) {
    # Default: show tables
    $Query = ".tables"
}
elseif ($Table -and -not $Query) {
    $Query = "SELECT * FROM $Table LIMIT $Limit;"
}

# Validate read-only (skip for sqlite commands starting with .)
if (-not $Query.StartsWith(".") -and -not (Test-ReadOnlyQuery -Sql $Query)) {
    Write-Status "Mutation queries are not allowed (read-only mode)" -Type Error
    Write-Status "Blocked keywords: $($mutationKeywords -join ', ')" -Type Info
    exit 1
}

Write-Status "Query: $Query" -Type Info
Write-Host ""

if ($Environment -eq "prod") {
    # Load environment variables to get deployment server IP
    $envFile = Join-Path $repoRoot ".env.local"
    if (-not (Test-Path $envFile)) {
        Write-Status ".env.local file not found" -Type Error
        exit 1
    }

    try {
        $envVars = Load-EnvFile -Path $envFile
        $serverIp = $envVars["DEPLOYMENT_SERVER_IP"]
        
        if (-not $serverIp) {
            Write-Status "DEPLOYMENT_SERVER_IP not found in .env.local" -Type Error
            exit 1
        }
        
        Write-Status "Connecting to: $serverIp" -Type Info
    }
    catch {
        Write-Status "Failed to load .env.local: $_" -Type Error
        exit 1
    }
    
    # Execute query on remote server
    $dbPath = "/data/lintilla.db"
    $sqlite3Path = '~/bin/sqlite3'
    
    # Build sqlite3 command with formatting
    $sqliteCmd = "$sqlite3Path -header -column `"$dbPath`" `"$Query`""
    
    Write-Host ""
    $result = ssh "andre@$serverIp" $sqliteCmd 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        $errorText = $result | Out-String
        Write-Status "Query failed: $errorText" -Type Error
        
        if (Test-SchemaError -ErrorOutput $errorText) {
            Write-Host ""
            Write-Status "Available schema:" -Type Info
            $schema = Get-CompactSchema -DbPath $dbPath -Sqlite3Cmd $sqlite3Path -Remote -SshTarget "andre@$serverIp"
            Write-Host $schema
        }
        exit 1
    }
    
    Write-Host $result
}
else {
    # Dev environment - use local database
    $dbPath = Join-Path $repoRoot "data\lintilla.db"
    
    if (-not (Test-Path $dbPath)) {
        Write-Status "Database not found: $dbPath" -Type Error
        Write-Status "Start the dev environment first" -Type Info
        exit 1
    }
    
    Write-Status "Database: $dbPath" -Type Info
    Write-Host ""
    
    # Check if sqlite3 is available locally
    $sqlite3 = Get-Command sqlite3 -ErrorAction SilentlyContinue
    if (-not $sqlite3) {
        Write-Status "sqlite3 not found in PATH" -Type Error
        Write-Status "Install SQLite CLI tools or use WSL" -Type Info
        exit 1
    }
    
    # Execute query locally
    $result = sqlite3 -header -column $dbPath $Query 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        $errorText = $result | Out-String
        Write-Status "Query failed: $errorText" -Type Error
        
        if (Test-SchemaError -ErrorOutput $errorText) {
            Write-Host ""
            Write-Status "Available schema:" -Type Info
            $schema = Get-CompactSchema -DbPath $dbPath
            Write-Host $schema
        }
        exit 1
    }
    
    Write-Host $result
}

Write-Host ""
Write-Status "Query complete" -Type Success
