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

    # Read workflow content
    $workflowPath = Join-Path $botRoot "prompts\workflows\01-plan-product.md"
    $workflowContent = if (Test-Path $workflowPath) {
        Get-Content -Path $workflowPath -Raw
    } else {
        "Create mission.md, tech-stack.md, and entity-model.md product documents."
    }

    # Build file references for the prompt
    $fileRefs = ""
    if ($savedFiles.Count -gt 0) {
        $fileRefs = "`n`nBriefing files have been saved to the briefing/ directory. Read and use these for context:`n"
        foreach ($sf in $savedFiles) {
            $fileRefs += "- $sf`n"
        }
    }

    # Compose system prompt
    $systemPrompt = @"
You are a product planning assistant for the dotbot autonomous development system.

Your task is to create the foundational product documents for a new project based on the user's description.

Follow this workflow for guidance on document structure:
$workflowContent

User's project description:
$UserPrompt
$fileRefs

Instructions:
1. Read any briefing files listed above and any existing project files (README.md, etc.) for additional context
2. Create these product documents directly by writing files to .bot/workspace/product/:
   - mission.md - What the product is, core principles, goals. MUST start with a section titled "Executive Summary" as the first heading.
   - tech-stack.md - Technologies, versions, infrastructure decisions
   - entity-model.md - Data model, entities, relationships. Include a Mermaid.js erDiagram block showing entities and their relationships visually.
3. Do NOT create tasks, ask questions, or use task management tools. Just create the documents directly.
4. Write comprehensive, well-structured markdown documents based on what you know from the user's description and any attached files.
5. Make reasonable inferences where details are missing - the user can refine later.

IMPORTANT: The mission.md file MUST begin with an "Executive Summary" section (## Executive Summary) as the very first content after the title. This is required for the UI to detect that product planning is complete.
"@

    # Build roadmap prompt for phase 2 (chained after doc creation)
    $roadmapPrompt = @"
You are a roadmap planning assistant for dotbot.

Instructions:
1. Read the workflow file at .bot/prompts/workflows/03-plan-roadmap.md — this is your primary guide
2. Read .bot/prompts/workflows/04-new-tasks.md for task schema reference
3. Read ALL product docs in .bot/workspace/product/ (mission.md, tech-stack.md, entity-model.md, and any others present)
4. Follow the workflow to generate a comprehensive task roadmap
5. Create tasks via the task_create_bulk MCP tool (the dotbot MCP server provides this)
6. Generate roadmap-overview.md and save it to .bot/workspace/product/roadmap-overview.md
7. Do NOT ask interactive questions — work autonomously
8. Do NOT create change requests — this is initial roadmap generation
"@

    # Run Claude CLI in background — Phase 1: create docs, Phase 2: plan roadmap
    $claudeCliModule = Join-Path $botRoot "systems\runtime\ClaudeCLI\ClaudeCLI.psm1"

    $scriptBlock = {
        param($claudeModule, $kickstartPrompt, $roadmapPrompt, $botRoot)
        $diagLog = Join-Path $botRoot ".control\kickstart-diag.log"

        # Direct activity log writer (bypasses Write-ActivityLog's $PSScriptRoot issue in Start-Job)
        function Write-Activity($type, $msg) {
            $logPath = Join-Path $botRoot ".control\activity.jsonl"
            $event = @{
                timestamp = (Get-Date).ToUniversalTime().ToString("o")
                type      = $type
                message   = $msg
                task_id   = $null
                phase     = $null
            } | ConvertTo-Json -Compress
            $maxRetries = 3
            for ($r = 0; $r -lt $maxRetries; $r++) {
                try {
                    $fs = [System.IO.FileStream]::new(
                        $logPath,
                        [System.IO.FileMode]::Append,
                        [System.IO.FileAccess]::Write,
                        [System.IO.FileShare]::ReadWrite
                    )
                    $sw = [System.IO.StreamWriter]::new($fs, [System.Text.Encoding]::UTF8)
                    $sw.WriteLine($event)
                    $sw.Close()
                    $fs.Close()
                    break
                } catch {
                    if ($r -lt ($maxRetries - 1)) {
                        Start-Sleep -Milliseconds (50 * ($r + 1))
                    }
                }
            }
        }

        try {
            Set-Location (Split-Path -Parent $botRoot)
            Import-Module $claudeModule -Force

            # Phase 1: Create product documents
            Write-Activity "init" "kickstart — creating product documents..."
            "$(Get-Date -Format o) [PHASE1] Creating product docs..." | Add-Content -Path $diagLog
            Invoke-ClaudeStream -Prompt $kickstartPrompt -Model Sonnet
            "$(Get-Date -Format o) [PHASE1] Complete" | Add-Content -Path $diagLog

            # Phase 2: If docs were created, plan roadmap
            $productDir = Join-Path $botRoot "workspace\product"
            $hasDocs = (Test-Path (Join-Path $productDir "mission.md")) -and
                       (Test-Path (Join-Path $productDir "tech-stack.md")) -and
                       (Test-Path (Join-Path $productDir "entity-model.md"))

            if ($hasDocs) {
                Write-Activity "text" "Product documents created. Starting roadmap planning..."
                Write-Activity "init" "roadmap — reading workflows and generating tasks..."
                "$(Get-Date -Format o) [PHASE2] Docs exist. Starting roadmap planning..." | Add-Content -Path $diagLog
                Invoke-ClaudeStream -Prompt $roadmapPrompt -Model Sonnet
                Write-Activity "text" "Roadmap complete! Tasks created."
                "$(Get-Date -Format o) [PHASE2] Complete" | Add-Content -Path $diagLog
            } else {
                Write-Activity "text" "Product docs not found — roadmap skipped."
                "$(Get-Date -Format o) [PHASE2] Skipped — product docs not found after phase 1" | Add-Content -Path $diagLog
            }
        } catch {
            Write-Activity "error" "Kickstart error: $($_.Exception.Message)"
            "$(Get-Date -Format o) [ERROR] $($_.Exception.Message)`n$($_.ScriptStackTrace)" | Add-Content -Path $diagLog
        }
    }

    # Launch as tracked process (keep Start-Job for two-phase chaining)
    Start-Job -ScriptBlock $scriptBlock -ArgumentList $claudeCliModule, $systemPrompt, $roadmapPrompt, $botRoot | Out-Null
    Write-Status "Product kickstart initiated via Claude CLI (with roadmap chaining)" -Type Info

    return @{
        success = $true
        message = "Kickstart initiated. Claude will create product documents, then plan the roadmap."
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
