<#
.SYNOPSIS
    Microsoft Entra ID data collector.

.DESCRIPTION
    Collects from Microsoft Graph API:
      - Subscribed SKUs (paid license plans with seat counts)
      - Directory subscriptions (renewal dates)
      - Enterprise applications (3rd-party SaaS via SSO)
      - App role assignments (user/group counts)
      - Sign-in activity (last login dates)

    Required App Registration permissions (Application type):
      - Application.Read.All
      - Organization.Read.All
      - Directory.Read.All
      - AuditLog.Read.All (optional — for sign-in activity)
#>

# Module-scoped token for REST calls
$script:GraphToken = $null

function Connect-EntraGraph {
    param([PSCustomObject]$Config)

    if (-not $Config.EntraTenantId -or
        -not $Config.EntraClientId -or
        -not $Config.EntraClientSecret) {
        Write-Log "Entra ID credentials not configured — skipping." -Level WARN
        return $false
    }

    Write-Log "Authenticating to Microsoft Graph..."

    # Connect Graph SDK (for Get-Mg* cmdlets)
    try {
        $secureSecret = ConvertTo-SecureString $Config.EntraClientSecret -AsPlainText -Force
        $credential   = New-Object System.Management.Automation.PSCredential(
            $Config.EntraClientId, $secureSecret
        )

        Connect-MgGraph -TenantId $Config.EntraTenantId `
                        -ClientSecretCredential $credential `
                        -NoWelcome

        Write-Log "Connected to Graph SDK" -Level SUCCESS
    }
    catch {
        Write-Log "Graph SDK connection failed: $_" -Level ERROR
        return $false
    }

    # Get raw bearer token for REST calls
    try {
        $tokenResponse = Invoke-RestMethod `
            -Uri "https://login.microsoftonline.com/$($Config.EntraTenantId)/oauth2/v2.0/token" `
            -Method Post `
            -Body @{
                client_id     = $Config.EntraClientId
                client_secret = $Config.EntraClientSecret
                scope         = "https://graph.microsoft.com/.default"
                grant_type    = "client_credentials"
            }

        $script:GraphToken = $tokenResponse.access_token
        Write-Log "Obtained Graph bearer token" -Level SUCCESS
        return $true
    }
    catch {
        Write-Log "Token request failed: $_" -Level ERROR
        return $false
    }
}

function Disconnect-EntraGraph {
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    $script:GraphToken = $null
}

function Get-EntraLicenses {
    param([PSCustomObject]$Config)

    <#
    .DESCRIPTION
        Pulls all subscribed SKUs and enriches with:
          - Friendly product names
          - Assigned/total/available seat counts
          - Renewal dates from directory subscriptions
          - Status mapping (Enabled → Active, Warning → Renewing Soon, etc.)

        Returns an array of standardized service record objects.
    #>

    Write-Section "Entra ID — License SKUs"

    # Get friendly name mapping
    $nameMap = Get-SkuNameMapping

    # Get all subscribed SKUs
    $skus = Get-MgSubscribedSku -All
    Write-Log "Found $($skus.Count) subscribed SKUs"

    # Get subscription lifecycle dates
    $subDates = @{}
    try {
        $headers = @{ Authorization = "Bearer $script:GraphToken" }
        $response = Invoke-RestMethod `
            -Uri "https://graph.microsoft.com/v1.0/directory/subscriptions" `
            -Headers $headers

        foreach ($sub in $response.value) {
            if ($sub.skuId) {
                $subDates[$sub.skuId] = @{
                    NextLifecycle = $sub.nextLifecycleDateTime
                    Status        = $sub.status
                    Created       = $sub.createdDateTime
                    TotalLicenses = $sub.totalLicenses
                }
            }
        }
        Write-Log "Loaded $($subDates.Count) subscription lifecycle records"
    }
    catch {
        Write-Log "Could not fetch subscription dates: $_" -Level WARN
    }

    # Build service records
    $results = foreach ($sku in $skus) {
        $total     = $sku.PrepaidUnits.Enabled
        $consumed  = $sku.ConsumedUnits
        $available = $total - $consumed

        $friendlyName = Resolve-SkuFriendlyName -SkuPartNumber $sku.SkuPartNumber -NameMap $nameMap
        if (-not $friendlyName) {
            $friendlyName = if ($sku.SkuPartNumber) { $sku.SkuPartNumber -replace '_', ' ' } else { "Unknown SKU ($($sku.SkuId))" }
        }

        $status = switch ($sku.CapabilityStatus) {
            "Enabled"   { "Active" }
            "Warning"   { "Renewing Soon" }
            "Suspended" { "Overdue" }
            "Deleted"   { "Cancelled" }
            default     { "Under Review" }
        }

        # Renewal date
        $renewalDate = $null
        $lifecycle = $subDates[$sku.SkuId]
        if ($lifecycle -and $lifecycle.NextLifecycle) {
            try { $renewalDate = ([datetime]$lifecycle.NextLifecycle).ToString("yyyy-MM-dd") }
            catch { }
        }

        $category = Get-SkuCategory -SkuName $sku.SkuPartNumber

        [PSCustomObject]@{
            ServiceName      = $friendlyName
            SkuPartNumber    = $sku.SkuPartNumber
            Category         = $category
            Status           = $status
            Cost             = $null
            CostUnit         = "/user/mo"
            BillingCycle     = "Annual"
            RenewalDate      = $renewalDate
            AssignedLicenses = $consumed
            TotalLicenses    = $total
            Source           = "Entra ID"
            Notes            = "$available unused licenses. SKU: $($sku.SkuPartNumber)"
            RecordType       = "License"
        }
    }

    Write-Log "Processed $($results.Count) license records" -Level SUCCESS
    return $results
}

function Get-EntraEnterpriseApps {
    param([PSCustomObject]$Config)

    <#
    .DESCRIPTION
        Pulls all 3rd-party enterprise applications (SaaS via SSO).
        Enriches with sign-in activity and user/group assignments.
        Flags stale apps with no recent sign-in.
    #>

    Write-Section "Entra ID — Enterprise Applications"

    # Build property list
    $selectProps = @(
        "DisplayName", "AppId", "AccountEnabled", "ServicePrincipalType",
        "PreferredSingleSignOnMode", "CreatedDateTime", "Homepage", "LoginUrl", "Tags",
        "AppRoleAssignmentRequired"
    )

    if ($Config.IncludeSignInActivity) {
        $selectProps += "SignInActivity"
    }

    $allApps = Get-MgServicePrincipal -All `
        -Filter "tags/any(t: t eq 'WindowsAzureActiveDirectoryIntegratedApp')" `
        -Property $selectProps

    Write-Log "Found $($allApps.Count) integrated enterprise apps"

    # Filter out Microsoft internal service principals
    $microsoftFilter = "microsoft|office 365|windows azure|graph explorer|" +
                       "azure ad|o365 suite|aad |msiam_access|p2p server"

    $thirdParty = $allApps | Where-Object {
        $_.DisplayName -notmatch $microsoftFilter
    }

    Write-Log "$($thirdParty.Count) are 3rd-party SaaS apps"

    $results = foreach ($app in $thirdParty) {
        # --- Sign-in activity ---
        $lastSignIn = $null
        $isStale = $false

        if ($Config.IncludeSignInActivity -and $app.SignInActivity) {
            $interactive    = $app.SignInActivity.LastSignInDateTime
            $nonInteractive = $app.SignInActivity.LastNonInteractiveSignInDateTime

            $lastSignIn = @($interactive, $nonInteractive) |
                Where-Object { $_ } |
                Sort-Object -Descending |
                Select-Object -First 1

            if ($lastSignIn) {
                $daysSince = (New-TimeSpan -Start $lastSignIn -End (Get-Date)).Days
                $isStale = $daysSince -gt $Config.StaleAppThresholdDays
            }
        }

        # --- Assignment counts ---
        $userCount  = 0
        $groupCount = 0
        $openAccess = -not $app.AppRoleAssignmentRequired  # True = everyone can access

        if ($Config.IncludeAssignmentCounts -and -not $openAccess) {
            # Only count assignments when they're actually required
            try {
                $assignments = Get-MgServicePrincipalAppRoleAssignedTo `
                    -ServicePrincipalId $app.Id -All

                $userCount  = ($assignments | Where-Object PrincipalType -eq 'User').Count
                $groupCount = ($assignments | Where-Object PrincipalType -eq 'Group').Count
            }
            catch { }
        }

        # --- Status ---
        $status = if (-not $app.AccountEnabled) {
            "Under Review"
        } elseif ($isStale) {
            "Under Review"
        } else {
            "Active"
        }

        # --- Notes ---
        $notesParts = @(
            "SSO: $($app.PreferredSingleSignOnMode ?? 'none')"
        )
        if ($openAccess) {
            $notesParts += "Access: Open to all users (assignment not required)"
        }
        else {
            $notesParts += "Users: $userCount, Groups: $groupCount"
        }
        if ($lastSignIn) {
            $notesParts += "Last sign-in: $($lastSignIn.ToString('yyyy-MM-dd'))"
        }
        if ($isStale) {
            $notesParts += "STALE — no sign-in in $($Config.StaleAppThresholdDays)+ days"
        }

        # For open-access apps, AssignedLicenses = $null (not 0, which is misleading)
        $assignedCount = if ($openAccess) { $null } else { $userCount }

        [PSCustomObject]@{
            ServiceName      = $app.DisplayName
            SkuPartNumber    = $null
            Category         = Get-AppCategory -AppName $app.DisplayName
            Status           = $status
            Cost             = $null
            CostUnit         = "/user/mo"
            BillingCycle     = $null
            RenewalDate      = $null
            AssignedLicenses = $assignedCount
            TotalLicenses    = $null
            Source           = "Entra ID"
            Notes            = ($notesParts -join ". ") + "."
            RecordType       = "Enterprise App"
        }
    }

    Write-Log "Processed $($results.Count) enterprise app records" -Level SUCCESS
    return $results
}

Export-ModuleMember -Function Connect-EntraGraph, Disconnect-EntraGraph,
                              Get-EntraLicenses, Get-EntraEnterpriseApps
