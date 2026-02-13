<#
.SYNOPSIS
    Microsoft SKU and app name classification utilities.

.DESCRIPTION
    Downloads Microsoft's official SKU-to-name mapping CSV.
    Provides category classification for SKUs and enterprise apps.
#>

$script:SkuNameCache = $null

function Get-SkuNameMapping {
    <#
    .DESCRIPTION
        Downloads Microsoft's official CSV that maps SkuPartNumber
        to Product_Display_Name. Cached for the session.
    #>

    if ($script:SkuNameCache) { return $script:SkuNameCache }

    Write-Log "Downloading Microsoft SKU name mapping..."

    $csvUrl = "https://download.microsoft.com/download/e/3/e/" +
              "e3e9faf2-f28b-490a-9ada-c6089a1fc5b0/" +
              "Product%20names%20and%20service%20plan%20identifiers%20for%20licensing.csv"

    try {
        $csvData = Invoke-WebRequest -Uri $csvUrl -UseBasicParsing | ConvertFrom-Csv
        $map = @{}

        foreach ($row in $csvData) {
            $key = $row.String_Id
            if ($key -and -not $map.ContainsKey($key)) {
                $map[$key] = $row.Product_Display_Name
            }
        }

        Write-Log "Loaded $($map.Count) SKU name mappings" -Level SUCCESS
        $script:SkuNameCache = $map
        return $map
    }
    catch {
        Write-Log "Could not download SKU mapping: $_" -Level WARN
        return @{}
    }
}

function Resolve-SkuFriendlyName {
    param(
        [string]$SkuPartNumber,
        [hashtable]$NameMap = @{}
    )

    if ($NameMap.ContainsKey($SkuPartNumber)) {
        return $NameMap[$SkuPartNumber]
    }

    # Fallback: manual mapping for common ones
    $fallback = @{
        "AAD_PREMIUM"          = "Entra ID P1"
        "AAD_PREMIUM_P2"       = "Entra ID P2"
        "ENTERPRISEPACK"       = "Microsoft 365 E3"
        "ENTERPRISEPREMIUM"    = "Microsoft 365 E5"
        "SPE_E3"               = "Microsoft 365 E3"
        "SPE_E5"               = "Microsoft 365 E5"
        "INTUNE_A"             = "Microsoft Intune Plan 1"
        "EMS"                  = "EMS E3"
        "EMSPREMIUM"           = "EMS E5"
        "EXCHANGESTANDARD"     = "Exchange Online Plan 1"
        "EXCHANGEENTERPRISE"   = "Exchange Online Plan 2"
        "FLOW_FREE"            = "Power Automate (Free)"
        "POWER_BI_STANDARD"    = "Power BI (Free)"
        "TEAMS_EXPLORATORY"    = "Teams Exploratory"
        "DEFENDER_ENDPOINT_P1" = "Defender for Endpoint P1"
    }

    if ($fallback.ContainsKey($SkuPartNumber)) {
        return $fallback[$SkuPartNumber]
    }

    return ($SkuPartNumber -replace '_', ' ')
}

function Get-SkuCategory {
    param([string]$SkuName)

    $name = $SkuName.ToUpper()

    if ($name -match "AAD_PREMIUM|ENTRA|IDENTITY")       { return "Identity" }
    if ($name -match "INTUNE|EMS")                        { return "MDM" }
    if ($name -match "DEFENDER|THREAT|SECURITY|ATP")      { return "Security" }
    if ($name -match "EXCHANGE|TEAMS|OFFICE|O365|M365|SPE|SHAREPOINT|ONEDRIVE") {
        return "Collaboration"
    }
    if ($name -match "AZURE|POWER")                       { return "Infrastructure" }
    if ($name -match "VISIOCLIENT|PROJECT")               { return "Collaboration" }

    return "Collaboration"
}

function Get-AppCategory {
    param([string]$AppName)

    $name = $AppName.ToLower()

    if ($name -match "slack|zoom|teams|webex|ringcentral")                           { return "Communications" }
    if ($name -match "github|jira|confluence|notion|asana|gitlab|trello|monday")     { return "Collaboration" }
    if ($name -match "aws|azure|gcp|cloudflare|datadog|pagerduty|terraform")         { return "Infrastructure" }
    if ($name -match "crowdstrike|sentinel|okta|duo|bitwarden|1password|lastpass")   { return "Security" }
    if ($name -match "jamf|intune|kandji|mosyle|addigy")                             { return "MDM" }
    if ($name -match "salesforce|hubspot|zendesk")                                   { return "Collaboration" }
    if ($name -match "figma|miro|canva|docusign|adobe")                              { return "Collaboration" }

    return "Collaboration"
}

Export-ModuleMember -Function Get-SkuNameMapping, Resolve-SkuFriendlyName, Get-SkuCategory, Get-AppCategory
