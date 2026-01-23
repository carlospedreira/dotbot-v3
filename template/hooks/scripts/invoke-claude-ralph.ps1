function Invoke-ClaudeRalph {
    <#
    .SYNOPSIS
    Wrapper for invoking Claude CLI for autonomous task execution
    
    .PARAMETER Prompt
    The prompt text to send to Claude
    
    .PARAMETER CompletionPromise
    The completion promise embedded in the prompt
    
    .PARAMETER MaxIterations
    Maximum number of iterations for the outer loop (default: 20)
    
    .PARAMETER SessionName
    Optional session name for logging and tracking
    
    .PARAMETER TimeoutMinutes
    Timeout in minutes for entire session (default: 60)
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,
        
        [Parameter(Mandatory = $true)]
        [string]$CompletionPromise,
        
        [Parameter(Mandatory = $false)]
        [int]$MaxIterations = 20,
        
        [Parameter(Mandatory = $false)]
        [string]$SessionName = "autonomous-session",
        
        [Parameter(Mandatory = $false)]
        [int]$TimeoutMinutes = 60
    )
    
    # Get Claude model from environment or use default
    $claudeModel = $env:CLAUDE_MODEL
    if (-not $claudeModel) {
        $claudeModel = "claude-opus-4-5-20251101"
    }
    
    Write-Host "Starting Claude autonomous session: $SessionName" -ForegroundColor Cyan
    Write-Host "  Model: $claudeModel" -ForegroundColor Gray
    Write-Host "  Max iterations: $MaxIterations" -ForegroundColor Gray
    Write-Host "  Timeout: $TimeoutMinutes minutes" -ForegroundColor Gray
    
    # Append completion promise to prompt
    $fullPrompt = @"
$Prompt

## Completion Goal

$CompletionPromise

Work on this task autonomously. When complete, ensure you call task_mark_done via MCP and output "TASK_COMPLETE".
"@
    
    # No session management needed - each iteration is independent
    
    # Track total output
    $allStdout = New-Object System.Text.StringBuilder
    $allStderr = New-Object System.Text.StringBuilder
    
    # Session start time
    $sessionStart = Get-Date
    $iteration = 0
    $exitCode = 0
    $timedOut = $false
    
    try {
        # Iteration loop - Claude runs, we check completion, optionally continue
        while ($iteration -lt $MaxIterations) {
            $iteration++
            
            # Check if we've exceeded timeout
            $elapsed = ((Get-Date) - $sessionStart).TotalMinutes
            if ($elapsed -ge $TimeoutMinutes) {
                Write-Host "Session timeout reached ($TimeoutMinutes minutes)" -ForegroundColor Yellow
                $timedOut = $true
                break
            }
            
            Write-Host "  Iteration $iteration of $MaxIterations..." -ForegroundColor Gray
            
            # Build arguments for this iteration
            $claudeArgs = @(
                "--model"
                $claudeModel
                "--dangerously-skip-permissions"
                "--plugin-dir"
                "__no_plugins__"
                "--no-session-persistence"
                "--output-format"
                "stream-json"
                "--print"
            )
            
            # Run Claude by piping prompt via stdin
            $rawOutput = ""
            $stderrStr = ""
            
            try {
                # Pipe prompt to claude and capture output
                $rawOutput = $fullPrompt | & claude @claudeArgs 2>&1
                $exitCode = $LASTEXITCODE
            } catch {
                $exitCode = -1
                $stderrStr = $_.Exception.Message
                Write-Host "  Error executing Claude: $stderrStr" -ForegroundColor Red
            }
            
            # Display output
            if ($rawOutput) {
                Write-Host $rawOutput
            }
            
            # Append to all stdout
            [void]$allStdout.AppendLine($rawOutput)
            
            # Append to stderr if there was an error
            if ($stderrStr) {
                [void]$allStderr.AppendLine($stderrStr)
            }
            
            # Check for task completion by querying task status via MCP
            # Since we don't capture stdout, we check the actual task state
            try {
                # Extract task ID from session name (format: task-{guid}-attempt-{n})
                if ($SessionName -match 'task-([0-9a-f-]+)') {
                    $taskId = $matches[1]
                    
                    # Check if task was moved to done directory
                    $doneFile = Join-Path $PSScriptRoot "..\..\state\tasks\done\$taskId.json"
                    if (Test-Path $doneFile) {
                        Write-Host "  Task marked as done" -ForegroundColor Green
                        break
                    }
                }
            } catch {
                # If we can't check status, continue to next iteration
            }
            
            # Check for errors
            if ($exitCode -ne 0) {
                Write-Host "  Claude exited with error code $exitCode" -ForegroundColor Red
                if ($stderrStr) {
                    Write-Host "  Error details: $stderrStr" -ForegroundColor Red
                }
                break
            }
            
            # Small delay between iterations
            if ($iteration -lt $MaxIterations) {
                Start-Sleep -Seconds 2
            }
        }
        
        # Build result
        $result = @{
            success = ($exitCode -eq 0 -and -not $timedOut)
            exit_code = $exitCode
            stdout = $allStdout.ToString()
            stderr = $allStderr.ToString()
            timed_out = $timedOut
            session_name = $SessionName
            iterations = $iteration
        }
        
        # Classify failure if not successful
        if (-not $result.success) {
            $result.failure_type = Get-FailureType -ExitCode $exitCode -Stderr $result.stderr -TimedOut $timedOut
        }
        
        return $result
        
    } catch {
        return @{
            success = $false
            exit_code = -1
            stdout = $allStdout.ToString()
            stderr = $_.Exception.Message
            timed_out = $false
            session_name = $SessionName
            iterations = $iteration
            failure_type = "Crash"
            error = $_.Exception.Message
        }
    }
}

function Get-FailureType {
    param(
        [int]$ExitCode,
        [string]$Stderr,
        [bool]$TimedOut
    )
    
    if ($TimedOut) {
        return "Timeout"
    }
    
    # Check for auth/rate limit errors (from AutoCoder auth.py patterns)
    $authPatterns = @(
        "rate limit",
        "too many requests",
        "quota exceeded",
        "authentication failed",
        "invalid api key",
        "not authenticated"
    )
    
    foreach ($pattern in $authPatterns) {
        if ($Stderr -match $pattern) {
            return "AuthLimit"
        }
    }
    
    # Check for verification failures
    if ($Stderr -match "verification failed" -or $Stderr -match "test.*failed") {
        return "VerificationFailed"
    }
    
    # Check for code errors
    if ($Stderr -match "syntax error" -or $Stderr -match "compilation failed") {
        return "CodeError"
    }
    
    # Default to crash
    return "Crash"
}
