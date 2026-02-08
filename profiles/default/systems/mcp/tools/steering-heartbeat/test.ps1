# Test steering-heartbeat tool

. "$PSScriptRoot\script.ps1"

Write-Host "Testing steering-heartbeat..." -ForegroundColor Cyan

$controlDir = Join-Path $PSScriptRoot "..\..\..\..\..\.control"
$controlDir = [System.IO.Path]::GetFullPath($controlDir)
$whisperFile = Join-Path $controlDir "whisper.jsonl"
$statusFile = Join-Path $controlDir "steering-status.json"

# Backup existing files
$whisperBackup = $null
$statusBackup = $null
if (Test-Path $whisperFile) { $whisperBackup = Get-Content $whisperFile -Raw }
if (Test-Path $statusFile) { $statusBackup = Get-Content $statusFile -Raw }

try {
    # Clean slate for testing
    if (Test-Path $whisperFile) { Remove-Item $whisperFile -Force }
    if (Test-Path $statusFile) { Remove-Item $statusFile -Force }

    # Test 1: Basic heartbeat with no whispers
    Write-Host "`n1. Basic heartbeat (no whispers)"
    $result = Invoke-SteeringHeartbeat -Arguments @{
        session_id = "test-session-123"
        status = "Running unit tests"
        next_action = "Commit changes"
    }
    if ($result.success -and $result.whisper_count -eq 0) {
        Write-Host "   PASS: Heartbeat successful, no whispers" -ForegroundColor Green
    } else {
        Write-Host "   FAIL: $($result | ConvertTo-Json -Compress)" -ForegroundColor Red
    }

    # Test 2: Verify status file was written
    Write-Host "`n2. Verify status file"
    if (Test-Path $statusFile) {
        $statusContent = Get-Content $statusFile -Raw | ConvertFrom-Json
        if ($statusContent.session_id -eq "test-session-123" -and $statusContent.status -eq "Running unit tests") {
            Write-Host "   PASS: Status file contains correct data" -ForegroundColor Green
        } else {
            Write-Host "   FAIL: Status file has wrong content" -ForegroundColor Red
        }
    } else {
        Write-Host "   FAIL: Status file not created" -ForegroundColor Red
    }

    # Test 3: Add a whisper and verify it's returned
    Write-Host "`n3. Test whisper delivery"
    $whisper = @{
        instance_id = "test-session-123"
        instruction = "Focus on error handling"
        priority = "normal"
        timestamp = (Get-Date).ToUniversalTime().ToString("o")
    } | ConvertTo-Json -Compress
    Add-Content -Path $whisperFile -Value $whisper -Encoding utf8NoBOM

    $result = Invoke-SteeringHeartbeat -Arguments @{
        session_id = "test-session-123"
        status = "Still running tests"
    }
    if ($result.success -and $result.whisper_count -eq 1 -and $result.whispers[0].instruction -eq "Focus on error handling") {
        Write-Host "   PASS: Whisper delivered correctly" -ForegroundColor Green
    } else {
        Write-Host "   FAIL: Whisper not delivered - $($result | ConvertTo-Json -Compress)" -ForegroundColor Red
    }

    # Test 4: Verify whisper is NOT returned again (index tracking)
    Write-Host "`n4. Test whisper index tracking (no duplicate delivery)"
    $result = Invoke-SteeringHeartbeat -Arguments @{
        session_id = "test-session-123"
        status = "Continuing work"
    }
    if ($result.success -and $result.whisper_count -eq 0) {
        Write-Host "   PASS: No duplicate whisper delivery" -ForegroundColor Green
    } else {
        Write-Host "   FAIL: Got duplicate whispers - count: $($result.whisper_count)" -ForegroundColor Red
    }

    # Test 5: Add whisper for different session (should not be delivered)
    Write-Host "`n5. Test session isolation"
    $whisper2 = @{
        instance_id = "other-session-456"
        instruction = "This is for another session"
        priority = "normal"
        timestamp = (Get-Date).ToUniversalTime().ToString("o")
    } | ConvertTo-Json -Compress
    Add-Content -Path $whisperFile -Value $whisper2 -Encoding utf8NoBOM

    $result = Invoke-SteeringHeartbeat -Arguments @{
        session_id = "test-session-123"
        status = "Should not see other session whisper"
    }
    if ($result.success -and $result.whisper_count -eq 0) {
        Write-Host "   PASS: Session isolation works" -ForegroundColor Green
    } else {
        Write-Host "   FAIL: Got whispers from other session" -ForegroundColor Red
    }

    # Test 6: Required parameters validation
    Write-Host "`n6. Test required parameter validation"
    $result = Invoke-SteeringHeartbeat -Arguments @{
        status = "Missing session_id"
    }
    if (-not $result.success -and $result.error -match "session_id") {
        Write-Host "   PASS: session_id validation works" -ForegroundColor Green
    } else {
        Write-Host "   FAIL: session_id validation broken" -ForegroundColor Red
    }

    $result = Invoke-SteeringHeartbeat -Arguments @{
        session_id = "test"
    }
    if (-not $result.success -and $result.error -match "status") {
        Write-Host "   PASS: status validation works" -ForegroundColor Green
    } else {
        Write-Host "   FAIL: status validation broken" -ForegroundColor Red
    }

} finally {
    # Cleanup: restore backups
    if (Test-Path $whisperFile) { Remove-Item $whisperFile -Force }
    if (Test-Path $statusFile) { Remove-Item $statusFile -Force }
    if ($whisperBackup) { Set-Content -Path $whisperFile -Value $whisperBackup -NoNewline }
    if ($statusBackup) { Set-Content -Path $statusFile -Value $statusBackup -NoNewline }
}

Write-Host "`nTests complete." -ForegroundColor Cyan
