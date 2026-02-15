<#
.SYNOPSIS
Aether (Hue bridge) discovery and configuration API module

.DESCRIPTION
Provides SSDP/mDNS bridge discovery and aether config CRUD.
Extracted from server.ps1 for modularity.
#>

$script:Config = @{
    ControlDir = $null
}

function Initialize-AetherAPI {
    param(
        [Parameter(Mandatory)] [string]$ControlDir
    )
    $script:Config.ControlDir = $ControlDir
}

function Find-Conduit {
    $controlDir = $script:Config.ControlDir

    # Method 0: Try last known IP from cached config (fastest)
    $configFile = Join-Path $controlDir "aether-config.json"
    if (Test-Path $configFile) {
        try {
            $cachedConfig = Get-Content $configFile -Raw | ConvertFrom-Json
            if ($cachedConfig.conduit) {
                $response = Invoke-RestMethod -Uri "http://$($cachedConfig.conduit)/api/config" -TimeoutSec 2 -ErrorAction Stop
                if ($response.bridgeid) {
                    return @{
                        IP = $cachedConfig.conduit
                        Id = $response.bridgeid
                    }
                }
            }
        } catch {
            # Cached IP no longer valid, continue with discovery
        }
    }

    # Method 1: Try Philips discovery endpoint (meethue.com)
    try {
        $discoveryResponse = Invoke-RestMethod -Uri "https://discovery.meethue.com/" -TimeoutSec 5 -ErrorAction Stop
        if ($discoveryResponse -and $discoveryResponse.Count -gt 0) {
            return @{
                IP = $discoveryResponse[0].internalipaddress
                Id = $discoveryResponse[0].id
            }
        }
    } catch {
        # Discovery endpoint failed, try SSDP
    }

    # Method 2: SSDP multicast discovery
    try {
        $ssdpMessage = @"
M-SEARCH * HTTP/1.1
HOST: 239.255.255.250:1900
MAN: "ssdp:discover"
MX: 3
ST: urn:schemas-upnp-org:device:basic:1

"@
        $udpClient = New-Object System.Net.Sockets.UdpClient
        $udpClient.Client.ReceiveTimeout = 3000
        $udpClient.Client.SetSocketOption([System.Net.Sockets.SocketOptionLevel]::Socket, [System.Net.Sockets.SocketOptionName]::ReuseAddress, $true)

        $groupEndpoint = New-Object System.Net.IPEndPoint ([System.Net.IPAddress]::Parse("239.255.255.250")), 1900
        $bytes = [System.Text.Encoding]::ASCII.GetBytes($ssdpMessage)
        $udpClient.Send($bytes, $bytes.Length, $groupEndpoint) | Out-Null

        $remoteEndpoint = New-Object System.Net.IPEndPoint ([System.Net.IPAddress]::Any), 0
        $responses = @()

        # Collect responses for up to 3 seconds
        $deadline = (Get-Date).AddSeconds(3)
        while ((Get-Date) -lt $deadline) {
            try {
                $receiveBytes = $udpClient.Receive([ref]$remoteEndpoint)
                $response = [System.Text.Encoding]::ASCII.GetString($receiveBytes)

                # Look for bridge identifier in response
                if ($response -match "IpBridge|hue-bridgeid") {
                    $ip = $remoteEndpoint.Address.ToString()

                    # Extract bridge ID from response if available
                    $bridgeId = ""
                    if ($response -match "hue-bridgeid:\s*([A-F0-9]+)") {
                        $bridgeId = $matches[1]
                    }

                    $udpClient.Close()
                    return @{
                        IP = $ip
                        Id = $bridgeId
                    }
                }
            } catch [System.Net.Sockets.SocketException] {
                # Timeout - no more responses
                break
            }
        }

        $udpClient.Close()
    } catch {
        # SSDP failed
    }

    return $null
}

function Get-AetherScanResult {
    $conduit = Find-Conduit
    if ($conduit) {
        return @{
            found = $true
            conduit = $conduit.IP
            id = $conduit.Id
        }
    } else {
        return @{
            found = $false
            conduit = $null
            id = $null
        }
    }
}

function Get-AetherConfig {
    $configFile = Join-Path $script:Config.ControlDir "aether-config.json"

    if (Test-Path $configFile) {
        try {
            return Get-Content $configFile -Raw | ConvertFrom-Json
        } catch {
            return @{ linked = $false }
        }
    } else {
        return @{ linked = $false }
    }
}

function Set-AetherConfig {
    param(
        [Parameter(Mandatory)] [string]$Body
    )
    $controlDir = $script:Config.ControlDir
    $configFile = Join-Path $controlDir "aether-config.json"

    $config = $Body | ConvertFrom-Json
    $config | ConvertTo-Json -Depth 5 | Set-Content $configFile -Force

    # Log bond result with details
    if ($config.linked) {
        $nodeCount = if ($config.nodes) { $config.nodes.Count } else { 0 }
        Write-Status "Aether bonded to $($config.conduit) with $nodeCount node(s)" -Type Success
    } else {
        Write-Status "Aether unlinked" -Type Warn
    }

    return @{
        success = $true
        config = $config
    }
}

Export-ModuleMember -Function @('Initialize-AetherAPI', 'Find-Conduit', 'Get-AetherScanResult', 'Get-AetherConfig', 'Set-AetherConfig')
