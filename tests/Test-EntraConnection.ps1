<#
.SYNOPSIS
    Tests Entra ID / Graph API connectivity and permissions.

.DESCRIPTION
    Validates:
      1. OAuth2 client credentials authentication
      2. Required Graph API permissions
      3. Basic data retrieval from each endpoint
    Run this before the full audit to catch config issues early.
#>

$ErrorActionPreference = "Stop"

$modulesRoot = Join-Path $PSScriptRoot ".." "src"
Import-Module (Join-Path $modulesRoot "Utils" "Logger.psm1") -Force
Import-Module (Join-Path $modulesRoot "Utils" "Config.psm1") -Force
Import-Module (Join-Path $modulesRoot "Utils" "SkuMapping.psm1") -Force
Import-Module (Join-Path $modulesRoot "Collectors" "EntraCollector.psm1") -Force

Write-Banner
Write-Log "Testing Entra ID / Graph API connection..."

$Config = Get-TrackerConfig

# --- Test 1: Authentication ---
Write-Log "Test 1: Authentication"
$connected = Connect-EntraGraph -Config $Config
if (-not $connected) {
    Write-Log "FAILED — Check ENTRA_TENANT_ID, ENTRA_CLIENT_ID, ENTRA_CLIENT_SECRET" -Level ERROR
    exit 1
}
Write-Log "PASSED" -Level SUCCESS

# --- Test 2: Subscribed SKUs ---
Write-Log "Test 2: Read subscribed SKUs (Organization.Read.All)"
try {
    $skus = Get-MgSubscribedSku -All
    Write-Log "PASSED — Found $($skus.Count) SKUs" -Level SUCCESS
}
catch {
    Write-Log "FAILED — Missing Organization.Read.All permission? $_" -Level ERROR
}

# --- Test 3: Enterprise Applications ---
Write-Log "Test 3: Read enterprise apps (Application.Read.All)"
try {
    $apps = Get-MgServicePrincipal -Top 5 `
        -Filter "tags/any(t: t eq 'WindowsAzureActiveDirectoryIntegratedApp')" `
        -Property DisplayName, AppId
    Write-Log "PASSED — Sample: $($apps[0].DisplayName)" -Level SUCCESS
}
catch {
    Write-Log "FAILED — Missing Application.Read.All permission? $_" -Level ERROR
}

# --- Test 4: Directory Subscriptions ---
Write-Log "Test 4: Read directory subscriptions (Directory.Read.All)"
try {
    $context = Get-MgContext
    $headers = @{ Authorization = "Bearer $((Get-MgContext).AuthType)" }

    # Use REST since the SDK doesn't expose this cleanly
    $tokenBody = @{
        client_id     = $Config.EntraClientId
        client_secret = $Config.EntraClientSecret
        scope         = "https://graph.microsoft.com/.default"
        grant_type    = "client_credentials"
    }
    $tokenResp = Invoke-RestMethod `
        -Uri "https://login.microsoftonline.com/$($Config.EntraTenantId)/oauth2/v2.0/token" `
        -Method Post -Body $tokenBody

    $restHeaders = @{ Authorization = "Bearer $($tokenResp.access_token)" }
    $subs = Invoke-RestMethod `
        -Uri "https://graph.microsoft.com/v1.0/directory/subscriptions" `
        -Headers $restHeaders

    Write-Log "PASSED — Found $($subs.value.Count) subscriptions" -Level SUCCESS
}
catch {
    Write-Log "WARN — Could not read directory subscriptions: $_" -Level WARN
    Write-Log "This is optional but provides renewal dates" -Level WARN
}

# --- Test 5: Sign-in Activity ---
Write-Log "Test 5: Read sign-in activity (AuditLog.Read.All)"
try {
    $testApp = Get-MgServicePrincipal -Top 1 -Property DisplayName, SignInActivity
    if ($testApp.SignInActivity) {
        Write-Log "PASSED — Sign-in activity data available" -Level SUCCESS
    }
    else {
        Write-Log "PASSED — Permission granted (no activity data on sample)" -Level SUCCESS
    }
}
catch {
    Write-Log "WARN — AuditLog.Read.All not granted. Sign-in data unavailable." -Level WARN
}

Disconnect-EntraGraph

Write-Host ""
Write-Log "All connection tests complete!" -Level SUCCESS
Write-Host ""
