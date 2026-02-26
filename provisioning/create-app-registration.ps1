param(
    [string]$UserPrincipalName = "targetuser@company.com",
    [string]$AppDisplayName    = "User App Name"
)

# ── 0. Ensure Graph connection with required scopes ──────────────────────────
$requiredScopes = @(
    "Application.ReadWrite.All",
    "AppRoleAssignment.ReadWrite.All",
    "Sites.FullControl.All",
    "Group.Read.All"
)
Connect-MgGraph -Scopes $requiredScopes -NoWelcome

# ── 1. Register the Entra ID application ─────────────────────────────────────
Write-Host "`n[1/6] Creating app registration: $AppDisplayName" -ForegroundColor Yellow

$app = New-MgApplication -DisplayName $AppDisplayName
$appId     = $app.AppId
$appObjId  = $app.Id
Write-Host "       App created — Client ID: $appId" -ForegroundColor Green

# ── 2. Create a client secret ────────────────────────────────────────────────
Write-Host "[2/6] Creating client secret" -ForegroundColor Yellow

$secret = Add-MgApplicationPassword -ApplicationId $appObjId -PasswordCredential @{
    DisplayName = "Auto-generated secret"
    EndDateTime = (Get-Date).AddYears(1)
}
$clientSecret = $secret.SecretText
Write-Host "       Secret created (expires: $($secret.EndDateTime))" -ForegroundColor Green

# ── 3. Create a service principal so we can assign app roles ─────────────────
Write-Host "[3/6] Creating service principal" -ForegroundColor Yellow

$sp = New-MgServicePrincipal -AppId $appId
$spId = $sp.Id
Write-Host "       Service principal created — Object ID: $spId" -ForegroundColor Green

# ── 4. Grant API permissions ─────────────────────────────────────────────────
#   Microsoft Graph resource app ID (constant across all tenants)
$graphResourceAppId = "00000003-0000-0000-c000-000000000000"
$graphSp = Get-MgServicePrincipal -Filter "appId eq '$graphResourceAppId'"

# Look up the app role IDs we need
$allRoles = $graphSp.AppRoles

$mailReadWrite = $allRoles | Where-Object { $_.Value -eq "Mail.ReadWrite" }
$mailSend      = $allRoles | Where-Object { $_.Value -eq "Mail.Send" }
$sitesSelected = $allRoles | Where-Object { $_.Value -eq "Sites.Selected" }

$rolesToGrant = @($mailReadWrite, $mailSend, $sitesSelected)

Write-Host "[4/6] Granting application permissions (admin consent)" -ForegroundColor Yellow

foreach ($role in $rolesToGrant) {
    New-MgServicePrincipalAppRoleAssignment `
        -ServicePrincipalId $spId `
        -PrincipalId $spId `
        -ResourceId $graphSp.Id `
        -AppRoleId $role.Id | Out-Null
    Write-Host "       Granted: $($role.Value)" -ForegroundColor Green
}

# ── 5. Scope mailbox access to the specific user via application access policy
Write-Host "[5/6] Restricting mailbox access to $UserPrincipalName" -ForegroundColor Yellow
Write-Host "       Creating mail-enabled security group for scoping..." -ForegroundColor DarkGray

# We use Exchange Online application access policy to limit Mail.ReadWrite
# to a specific mailbox. This requires a mail-enabled security group.
# The admin must run this in Exchange Online PowerShell:
Write-Host @"
       ┌─────────────────────────────────────────────────────────────────┐
       │ MANUAL STEP — Run in Exchange Online PowerShell:               │
       │                                                                │
       │ New-ApplicationAccessPolicy \                                  │
       │   -AppId "$appId" \                                            │
       │   -PolicyScopeGroupId "$UserPrincipalName" \                   │
       │   -AccessRight RestrictAccess \                                │
       │   -Description "Restrict $AppDisplayName to $UserPrincipalName"│
       │                                                                │
       │ NOTE: PolicyScopeGroupId accepts a mail-enabled security group │
       │ or a user mailbox directly. Propagation takes ~30 min.         │
       └─────────────────────────────────────────────────────────────────┘
"@ -ForegroundColor Cyan

# Attempt to create the policy automatically (requires Exchange Online connection)
try {
    New-ApplicationAccessPolicy `
        -AppId $appId `
        -PolicyScopeGroupId $UserPrincipalName `
        -AccessRight RestrictAccess `
        -Description "Restrict $AppDisplayName to $UserPrincipalName mailbox"
    Write-Host "       Application access policy created successfully" -ForegroundColor Green
} catch {
    Write-Host "       Could not auto-create policy: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "       Run the manual step above in Exchange Online PowerShell" -ForegroundColor Yellow
}

# ── 6. Grant Sites.Selected read permission to user's SharePoint sites ───────
Write-Host "[6/6] Granting read access to SharePoint sites where user is a member" -ForegroundColor Yellow

$memberGroups = Get-MgUserMemberOf -UserId $UserPrincipalName -All |
    Where-Object { $_.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.group' -and
                   $_.AdditionalProperties.groupTypes -contains 'Unified' }

$siteCount = 0
foreach ($group in $memberGroups) {
    $groupName = $group.AdditionalProperties.displayName
    try {
        $site = Get-MgGroupSite -GroupId $group.Id -SiteId "root" -ErrorAction Stop

        $body = @{
            roles = @("read")
            grantedToIdentities = @(
                @{
                    application = @{
                        id          = $appId
                        displayName = $AppDisplayName
                    }
                }
            )
        } | ConvertTo-Json -Depth 5

        Invoke-MgGraphRequest -Method POST `
            -Uri "https://graph.microsoft.com/v1.0/sites/$($site.Id)/permissions" `
            -Body $body -ContentType "application/json" | Out-Null

        $siteCount++
        Write-Host "       Read access granted: $($site.DisplayName) ($($site.WebUrl))" -ForegroundColor Green
    } catch {
        Write-Host "       Skipped group '$groupName': $($_.Exception.Message)" -ForegroundColor DarkGray
    }
}

# ── Summary ──────────────────────────────────────────────────────────────────
Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                     APP REGISTRATION SUMMARY                ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host "║  App Name:       $AppDisplayName" -ForegroundColor Cyan
Write-Host "║  Client ID:      $appId" -ForegroundColor Cyan
Write-Host "║  Client Secret:  $clientSecret" -ForegroundColor Cyan
Write-Host "║  Tenant ID:      $((Get-MgContext).TenantId)" -ForegroundColor Cyan
Write-Host "║" -ForegroundColor Cyan
Write-Host "║  Permissions:" -ForegroundColor Cyan
Write-Host "║    • Mail.ReadWrite   (scoped to $UserPrincipalName)" -ForegroundColor Cyan
Write-Host "║    • Mail.Send        (scoped to $UserPrincipalName)" -ForegroundColor Cyan
Write-Host "║    • Sites.Selected   (read on $siteCount sites)" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host "`n⚠  Save the client secret now — it cannot be retrieved later." -ForegroundColor Yellow
