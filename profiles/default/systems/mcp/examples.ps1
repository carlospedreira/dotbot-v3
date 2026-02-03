#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Example usage of PowerShell MCP Date Server tools
.DESCRIPTION
    Demonstrates how to use various date/time manipulation tools
#>

# These are examples of JSON requests you would send to the MCP server
# When using with Claude Desktop, these tools are called automatically

# Example 1: Get current date/time in a specific format
$example1 = @{
    tool = 'get_current_datetime'
    arguments = @{
        format = 'dddd, MMMM dd, yyyy HH:mm:ss'
        utc = $true
    }
}

Write-Host "Example 1: Get current UTC time"
Write-Host ($example1 | ConvertTo-Json)
Write-Host ""

# Example 2: Calculate a deadline (30 days from now)
$example2 = @{
    tool = 'add_to_date'
    arguments = @{
        days = 30
        output_format = 'yyyy-MM-dd'
    }
}

Write-Host "Example 2: Calculate deadline (30 days from now)"
Write-Host ($example2 | ConvertTo-Json)
Write-Host ""

# Example 3: Calculate age in days
$example3 = @{
    tool = 'get_date_difference'
    arguments = @{
        start_date = '1990-01-01'
        end_date = '2026-01-01'
        unit = 'days'
    }
}

Write-Host "Example 3: Calculate days between dates"
Write-Host ($example3 | ConvertTo-Json)
Write-Host ""

# Example 4: Convert date formats
$example4 = @{
    tool = 'format_date'
    arguments = @{
        date = '12/25/2025'
        input_format = 'MM/dd/yyyy'
        output_format = 'yyyy-MM-dd'
    }
}

Write-Host "Example 4: Convert date format"
Write-Host ($example4 | ConvertTo-Json)
Write-Host ""

# Example 5: Parse Unix timestamp
$example5 = @{
    tool = 'parse_timestamp'
    arguments = @{
        timestamp = 1735689600
        format = 'yyyy-MM-dd HH:mm:ss'
    }
}

Write-Host "Example 5: Parse Unix timestamp"
Write-Host ($example5 | ConvertTo-Json)
Write-Host ""

# Example 6: Add complex time (2 years, 3 months, 15 days)
$example6 = @{
    tool = 'add_to_date'
    arguments = @{
        date = '2024-01-01'
        years = 2
        months = 3
        days = 15
        hours = 6
        output_format = 'yyyy-MM-dd HH:mm'
    }
}

Write-Host "Example 6: Add complex time units"
Write-Host ($example6 | ConvertTo-Json)
Write-Host ""

# Example 7: Calculate business days (weekdays)
# Note: This shows the difference in days - you'd need to calculate business days separately
$example7 = @{
    tool = 'get_date_difference'
    arguments = @{
        start_date = '2026-01-05'  # Monday
        end_date = '2026-01-16'    # Friday
        unit = 'days'
    }
}

Write-Host "Example 7: Calculate total days (for business day calculation)"
Write-Host ($example7 | ConvertTo-Json)
Write-Host ""

# Example 8: Format current date in multiple formats
Write-Host "Example 8: Common date format patterns:"
Write-Host ""

$formats = @(
    @{ name = 'ISO 8601'; pattern = 'o' }
    @{ name = 'Short Date'; pattern = 'yyyy-MM-dd' }
    @{ name = 'US Format'; pattern = 'MM/dd/yyyy' }
    @{ name = 'Long Date'; pattern = 'dddd, MMMM dd, yyyy' }
    @{ name = 'Time Only'; pattern = 'HH:mm:ss' }
    @{ name = 'Full DateTime'; pattern = 'yyyy-MM-dd HH:mm:ss' }
    @{ name = 'Custom'; pattern = 'MMM dd, yyyy @ hh:mm tt' }
)

foreach ($fmt in $formats) {
    $ex = @{
        tool = 'format_date'
        arguments = @{
            output_format = $fmt.pattern
        }
    }
    Write-Host "  $($fmt.name) ($($fmt.pattern)):"
    Write-Host "    $($ex | ConvertTo-Json -Compress)"
}

# Example 9: Check if today is a holiday using place name
$example9 = @{
    tool = 'get_public_holidays'
    arguments = @{
        location = 'Eiffel Tower'
    }
}

Write-Host "Example 9: Check if today is a holiday at Eiffel Tower (Paris)"
Write-Host ($example9 | ConvertTo-Json)
Write-Host ""

# Example 10: Check specific date using city name
$example10 = @{
    tool = 'get_public_holidays'
    arguments = @{
        location = 'New York'
        date = '2026-07-04'
    }
}

Write-Host "Example 10: Check if July 4th 2026 is a holiday in New York"
Write-Host ($example10 | ConvertTo-Json)
Write-Host ""

# Example 11: Check using coordinates
$example11 = @{
    tool = 'get_public_holidays'
    arguments = @{
        latitude = -26.275
        longitude = 28.004
    }
}

Write-Host "Example 11: Check today's holiday status using coordinates (Johannesburg)"
Write-Host ($example11 | ConvertTo-Json)
Write-Host ""

Write-Host "To test these examples with the MCP server:"
Write-Host "  1. Run the server: pwsh -File .bot/systems/mcp/dotbot-mcp.ps1"
Write-Host "  2. Send JSON-RPC requests with the tool name and arguments shown above"
Write-Host "  3. Or integrate with Claude Desktop using mcp-config.json configuration"
# Example 12: Get current time in Tokyo
$example12 = @{
    tool = 'get_current_time_at'
    arguments = @{
        location = 'Tokyo'
    }
}

Write-Host "Example 12: Get current time in Tokyo"
Write-Host ($example12 | ConvertTo-Json)
Write-Host ""

# Example 13: Get current time at a POI with custom format
$example13 = @{
    tool = 'get_current_time_at'
    arguments = @{
        location = 'Big Ben'
        format = 'dddd, MMMM dd, yyyy hh:mm tt'
    }
}

Write-Host "Example 13: Get current time at Big Ben (London) with custom format"
Write-Host ($example13 | ConvertTo-Json)
Write-Host ""

# Example 14: Get current time using coordinates
$example14 = @{
    tool = 'get_current_time_at'
    arguments = @{
        latitude = -33.8568
        longitude = 151.2153
    }
}

Write-Host "Example 14: Get current time using coordinates (Sydney Opera House)"
Write-Host ($example14 | ConvertTo-Json)
Write-Host ""
Write-Host "Note: Location tools (get_public_holidays, get_current_time_at) require a Google Maps API key in .env file"

