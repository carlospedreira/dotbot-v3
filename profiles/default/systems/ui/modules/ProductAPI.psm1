<#
.SYNOPSIS
Product document management API module

.DESCRIPTION
Provides product document listing, retrieval, kickstart (Claude-driven doc creation),
and roadmap planning functionality.
Extracted from server.ps1 for modularity.
#>

$script:Config = @{
    BotRoot = $null
    ControlDir = $null
}

function Initialize-ProductAPI {
    param(
        [Parameter(Mandatory)] [string]$BotRoot,
        [Parameter(Mandatory)] [string]$ControlDir
    )
    $script:Config.BotRoot = $BotRoot
    $script:Config.ControlDir = $ControlDir
}

function Get-ProductList {
    $botRoot = $script:Config.BotRoot
    $productDir = Join-Path $botRoot "workspace\product"
    $docs = @()

    if (Test-Path $productDir) {
        $mdFiles = @(Get-ChildItem -Path $productDir -Filter "*.md" -ErrorAction SilentlyContinue)

        # Define priority order for product files
        $priorityOrder = [System.Collections.Generic.List[string]]@(
            'mission',
            'entity-model',
            'tech-stack',
            'roadmap',
            'roadmap-overview'
        )

        # Separate files into priority and non-priority
        $priorityFiles = [System.Collections.ArrayList]@()
        $otherFiles = [System.Collections.ArrayList]@()

        foreach ($file in $mdFiles) {
            if ($null -eq $file) { continue }
            $priorityIndex = $priorityOrder.IndexOf($file.BaseName)
            if ($priorityIndex -ge 0) {
                [void]$priorityFiles.Add([PSCustomObject]@{
                    File = $file
                    Priority = $priorityIndex
                })
            } else {
                [void]$otherFiles.Add($file)
            }
        }

        # Sort priority files by their priority index
        if ($priorityFiles.Count -gt 0) {
            $priorityFiles = @($priorityFiles | Sort-Object -Property Priority)
        }

        # Sort other files alphabetically
        if ($otherFiles.Count -gt 0) {
            $otherFiles = @($otherFiles | Sort-Object -Property BaseName)
        }

        # Build final docs array: priority first, then alphabetical
        foreach ($pf in $priorityFiles) {
            if ($null -eq $pf) { continue }
            $docs += @{
                name = $pf.File.BaseName
                filename = $pf.File.Name
            }
        }
        foreach ($file in $otherFiles) {
            if ($null -eq $file) { continue }
            $docs += @{
                name = $file.BaseName
                filename = $file.Name
            }
        }
    }

    return @{ docs = $docs }
}

function Get-ProductDocument {
    param(
        [Parameter(Mandatory)] [string]$Name
    )
    $botRoot = $script:Config.BotRoot
    $productDir = Join-Path $botRoot "workspace\product"
    $docPath = Join-Path $productDir "$Name.md"

    if (Test-Path $docPath) {
        $docContent = Get-Content -Path $docPath -Raw
        return @{
            success = $true
            name = $Name
            content = $docContent
        }
    } else {
        return @{
            _statusCode = 404
            success = $false
            error = "Document not found: $Name"
        }
    }
}

function Start-ProductKickstart {
    param(
        [Parameter(Mandatory)] [string]$UserPrompt,
        [array]$Files = @()
    )
    $botRoot = $script:Config.BotRoot

    # Validate file constraints
    $maxFileSize = 2MB
    $maxFiles = 10
    $validFiles = @()

    if ($Files.Count -gt $maxFiles) {
        return @{
            _statusCode = 400
            success = $false
            error = "Maximum $maxFiles files allowed"
        }
    }

    $filesValid = $true
    foreach ($file in $Files) {
        if (-not $file -or -not $file.name -or -not $file.content) { continue }
        try {
            $decoded = [Convert]::FromBase64String($file.content)
            if ($decoded.Length -gt $maxFileSize) {
                return @{
                    _statusCode = 400
                    success = $false
                    error = "File '$($file.name)' exceeds 2MB limit"
                }
            }
            $validFiles += @{
                name = $file.name -replace '[^\w\-\.]', '_'
                bytes = $decoded
            }
        } catch {
            return @{
                _statusCode = 400
                success = $false
                error = "Invalid base64 content for file '$($file.name)'"
            }
        }
    }

    # Create briefing directory and save files
    $briefingDir = Join-Path $botRoot "workspace\product\briefing"
    if (-not (Test-Path $briefingDir)) {
        New-Item -Path $briefingDir -ItemType Directory -Force | Out-Null
    }

    $savedFiles = @()
    foreach ($vf in $validFiles) {
        $filePath = Join-Path $briefingDir $vf.name
        [System.IO.File]::WriteAllBytes($filePath, $vf.bytes)
        $savedFiles += $filePath
    }

    # Launch kickstart as a tracked process via launch-process.ps1
    $launcherPath = Join-Path $botRoot "systems\runtime\launch-process.ps1"
    $escapedPrompt = $UserPrompt -replace '"', '\"'
    $launchArgs = @(
        "-File", "`"$launcherPath`"",
        "-Type", "kickstart",
        "-Model", "Sonnet",
        "-Prompt", "`"$escapedPrompt`"",
        "-Description", "`"Kickstart: project setup`""
    )
    Start-Process pwsh -ArgumentList $launchArgs -WindowStyle Normal | Out-Null
    Write-Status "Product kickstart launched as tracked process" -Type Info

    return @{
        success = $true
        message = "Kickstart initiated. Product documents, task groups, and task expansion will run in a tracked process."
    }
}

function Start-RoadmapPlanning {
    $botRoot = $script:Config.BotRoot

    # Validate product docs exist
    $productDir = Join-Path $botRoot "workspace\product"
    $requiredDocs = @("mission.md", "tech-stack.md", "entity-model.md")
    $missingDocs = @()
    foreach ($doc in $requiredDocs) {
        $docPath = Join-Path $productDir $doc
        if (-not (Test-Path $docPath)) {
            $missingDocs += $doc
        }
    }

    if ($missingDocs.Count -gt 0) {
        return @{
            _statusCode = 400
            success = $false
            error = "Missing required product docs: $($missingDocs -join ', '). Run kickstart first."
        }
    }

    # Launch via process manager
    $launcherPath = Join-Path $botRoot "systems\runtime\launch-process.ps1"
    $launchArgs = @("-File", "`"$launcherPath`"", "-Type", "planning", "-Model", "Sonnet", "-Description", "`"Plan project roadmap`"")
    Start-Process pwsh -ArgumentList $launchArgs -WindowStyle Normal | Out-Null
    Write-Status "Roadmap planning launched as tracked process" -Type Info

    return @{
        success = $true
        message = "Roadmap planning initiated via process manager."
    }
}

Export-ModuleMember -Function @(
    'Initialize-ProductAPI',
    'Get-ProductList',
    'Get-ProductDocument',
    'Start-ProductKickstart',
    'Start-RoadmapPlanning'
)
