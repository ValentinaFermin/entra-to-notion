<#
.SYNOPSIS
    Notion database sync module.

.DESCRIPTION
    Upserts service records into a Notion database.
    - Matches existing pages by "Service Name" (title property)
    - Updates existing records (PATCH) or creates new ones (POST)
    - Respects Notion API rate limits (3 req/sec)
    - Skips null values to avoid overwriting manual entries

    Setup:
      1. https://www.notion.so/my-integrations → create integration
      2. Create database with required schema (see docs/NotionSchema.md)
      3. Share database with integration (••• → Connections)
#>

function Test-NotionConnection {
    param([PSCustomObject]$Config)

    <#
    .DESCRIPTION
        Validates Notion token and database access.
        Returns $true if connection is successful.
    #>

    if (-not $Config.NotionToken -or -not $Config.NotionDatabaseId) {
        Write-Log "Notion not configured — set NOTION_TOKEN and NOTION_DATABASE_ID" -Level WARN
        return $false
    }

    Write-Log "Testing Notion connection..."

    try {
        $headers = @{
            "Authorization"  = "Bearer $($Config.NotionToken)"
            "Notion-Version" = $Config.NotionApiVersion
        }

        $db = Invoke-RestMethod `
            -Uri "https://api.notion.com/v1/databases/$($Config.NotionDatabaseId)" `
            -Headers $headers

        Write-Log "Connected to Notion database: $($db.title[0].plain_text)" -Level SUCCESS
        return $true
    }
    catch {
        Write-Log "Notion connection failed: $_" -Level ERROR
        Write-Log "Check: 1) Token is valid  2) Database is shared with integration" -Level WARN
        return $false
    }
}

function Find-NotionPage {
    param(
        [PSCustomObject]$Config,
        [string]$ServiceName
    )

    $headers = @{
        "Authorization"  = "Bearer $($Config.NotionToken)"
        "Notion-Version" = $Config.NotionApiVersion
        "Content-Type"   = "application/json"
    }

    $body = @{
        filter = @{
            property = "Service Name"
            title    = @{ equals = $ServiceName }
        }
    } | ConvertTo-Json -Depth 5

    try {
        $response = Invoke-RestMethod `
            -Uri "https://api.notion.com/v1/databases/$($Config.NotionDatabaseId)/query" `
            -Method Post `
            -Headers $headers `
            -Body $body

        if ($response.results.Count -gt 0) {
            return $response.results[0].id
        }
    }
    catch {
        Write-Log "  Search failed for '$ServiceName': $_" -Level WARN
    }

    return $null
}

function ConvertTo-NotionProperties {
    param([PSCustomObject]$Service)

    <#
    .DESCRIPTION
        Maps a service record to Notion property format.
        Only includes non-null values to preserve manual entries.

        Expected Notion database schema:
          Service Name       → title
          Category           → select
          Status             → select
          Cost               → number
          Cost Unit          → select
          Billing Cycle      → select
          Renewal Date       → date
          Assigned Licenses  → number
          Total Licenses     → number
          Source             → multi_select
          Last Synced        → date
          Notes              → rich_text
    #>

    $props = @{
        "Service Name" = @{
            title = @(
                @{ text = @{ content = $Service.ServiceName } }
            )
        }
        # Always update sync timestamp
        "Last Synced" = @{
            date = @{ start = (Get-Date -Format "yyyy-MM-dd") }
        }
    }

    if ($Service.Category)     { $props["Category"]      = @{ select = @{ name = $Service.Category } } }
    if ($Service.Status)       { $props["Status"]        = @{ select = @{ name = $Service.Status } } }
    if ($null -ne $Service.Cost) { $props["Cost"]        = @{ number = $Service.Cost } }
    if ($Service.CostUnit)     { $props["Cost Unit"]     = @{ select = @{ name = $Service.CostUnit } } }
    if ($Service.BillingCycle) { $props["Billing Cycle"] = @{ select = @{ name = $Service.BillingCycle } } }

    if ($Service.RenewalDate) {
        $props["Renewal Date"] = @{ date = @{ start = $Service.RenewalDate } }
    }

    if ($null -ne $Service.AssignedLicenses) {
        $props["Assigned Licenses"] = @{ number = [int]$Service.AssignedLicenses }
    }

    if ($null -ne $Service.TotalLicenses) {
        $props["Total Licenses"] = @{ number = [int]$Service.TotalLicenses }
    }

    if ($Service.Source) {
        $sources = @($Service.Source) | ForEach-Object { @{ name = $_ } }
        $props["Source"] = @{ multi_select = $sources }
    }

    if ($Service.Notes) {
        $truncated = if ($Service.Notes.Length -gt 2000) {
            $Service.Notes.Substring(0, 2000)
        } else { $Service.Notes }

        $props["Notes"] = @{
            rich_text = @( @{ text = @{ content = $truncated } } )
        }
    }

    return $props
}

function Sync-ServiceToNotion {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [PSCustomObject]$Config,
        [PSCustomObject]$Service
    )

    $headers = @{
        "Authorization"  = "Bearer $($Config.NotionToken)"
        "Notion-Version" = $Config.NotionApiVersion
        "Content-Type"   = "application/json"
    }

    $properties = ConvertTo-NotionProperties -Service $Service
    $existingId = Find-NotionPage -Config $Config -ServiceName $Service.ServiceName

    if ($existingId) {
        # UPDATE
        if ($PSCmdlet.ShouldProcess($Service.ServiceName, "Update in Notion")) {
            $body = @{ properties = $properties } | ConvertTo-Json -Depth 10

            try {
                Invoke-RestMethod `
                    -Uri "https://api.notion.com/v1/pages/$existingId" `
                    -Method Patch `
                    -Headers $headers `
                    -Body $body | Out-Null

                Write-Log "  ↻ Updated: $($Service.ServiceName)" -Level SUCCESS
            }
            catch {
                Write-Log "  ✗ Update failed: $($Service.ServiceName) — $_" -Level ERROR
            }
        }
    }
    else {
        # CREATE
        if ($PSCmdlet.ShouldProcess($Service.ServiceName, "Create in Notion")) {
            $body = @{
                parent     = @{ database_id = $Config.NotionDatabaseId }
                properties = $properties
            } | ConvertTo-Json -Depth 10

            try {
                Invoke-RestMethod `
                    -Uri "https://api.notion.com/v1/pages" `
                    -Method Post `
                    -Headers $headers `
                    -Body $body | Out-Null

                Write-Log "  ✚ Created: $($Service.ServiceName)" -Level SUCCESS
            }
            catch {
                Write-Log "  ✗ Create failed: $($Service.ServiceName) — $_" -Level ERROR
            }
        }
    }

    # Notion rate limit: 3 requests/sec
    Start-Sleep -Milliseconds 350
}

function Sync-AllToNotion {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [PSCustomObject]$Config,
        [array]$Services
    )

    if (-not (Test-NotionConnection -Config $Config)) { return }

    Write-Section "Syncing $($Services.Count) services to Notion"

    $total   = $Services.Count
    $current = 0

    foreach ($svc in $Services) {
        $current++
        $pct = [math]::Round(($current / $total) * 100)

        if (-not $svc.ServiceName) {
            Write-Log "  ⚠ Skipping record with no ServiceName (SkuPartNumber: $($svc.SkuPartNumber))" -Level WARN
            continue
        }

        Write-Progress -Activity "Syncing to Notion" `
            -Status "$current/$total — $($svc.ServiceName)" `
            -PercentComplete $pct

        Sync-ServiceToNotion -Config $Config -Service $svc
    }

    Write-Progress -Activity "Syncing to Notion" -Completed
    Write-Log "Notion sync complete — $total records processed" -Level SUCCESS
}

Export-ModuleMember -Function Test-NotionConnection, Sync-AllToNotion, Sync-ServiceToNotion
