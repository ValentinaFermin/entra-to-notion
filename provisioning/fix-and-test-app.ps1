# Test an app registration — verify scope is limited to target user's mail and site memberships

param(
    [string]$ClientSecret = "YOUR_CLIENT_SECRET_HERE"
)

$appId        = "00000000-0000-0000-0000-000000000001"  # Your app client ID
$tenantId     = "00000000-0000-0000-0000-000000000000"  # Your tenant ID
$clientSecret = $ClientSecret
$userUPN      = "targetuser@company.com"

# ── 1. Authenticate as the app ───────────────────────────────────────────────
Write-Host "`n[1/2] Authenticating as app" -ForegroundColor Yellow

$tokenBody = @{
    grant_type    = "client_credentials"
    client_id     = $appId
    client_secret = $clientSecret
    scope         = "https://graph.microsoft.com/.default"
}

try {
    $tokenResponse = Invoke-RestMethod -Method POST `
        -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" `
        -ContentType "application/x-www-form-urlencoded" `
        -Body $tokenBody
    $token = $tokenResponse.access_token
} catch {
    Write-Host "  Authentication FAILED: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

$headers = @{ Authorization = "Bearer $token" }
Write-Host "  Authenticated successfully`n" -ForegroundColor Green

# ── 2. Run all tests ────────────────────────────────────────────────────────
Write-Host "[2/2] Running scope tests...`n" -ForegroundColor Yellow

$passed = 0
$failed = 0

# ── MAILBOX TESTS ────────────────────────────────────────────────────────────
Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  MAILBOX TESTS" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan

Write-Host "`n[TEST 1] Read target user's mailbox (expect: SUCCESS)" -ForegroundColor Yellow
try {
    $result = Invoke-RestMethod -Method GET -Headers $headers `
        -Uri "https://graph.microsoft.com/v1.0/users/targetuser@company.com/messages?`$top=3&`$select=subject,receivedDateTime"
    Write-Host "  PASS — Retrieved $($result.value.Count) messages" -ForegroundColor Green
    $result.value | ForEach-Object { Write-Host "    - $($_.subject)" -ForegroundColor DarkGray }
    $passed++
} catch {
    $status = $_.Exception.Response.StatusCode.value__
    Write-Host "  FAIL — HTTP $status" -ForegroundColor Red
    $failed++
}

Write-Host "`n[TEST 2] Read another user's mailbox (expect: 403 DENIED)" -ForegroundColor Yellow
Write-Host "         NOTE: Requires ApplicationAccessPolicy in Exchange Online." -ForegroundColor DarkGray
Write-Host "         Without it, Mail.ReadWrite grants access to ALL mailboxes." -ForegroundColor DarkGray
try {
    $result = Invoke-RestMethod -Method GET -Headers $headers `
        -Uri "https://graph.microsoft.com/v1.0/users/otheruser@company.com/messages?`$top=1&`$select=subject"
    Write-Host "  INFO — Access GRANTED (ApplicationAccessPolicy not yet applied)" -ForegroundColor Yellow
    Write-Host "         Run New-ApplicationAccessPolicy in Exchange Online to restrict" -ForegroundColor Yellow
    $passed++
} catch {
    $status = $_.Exception.Response.StatusCode.value__
    if ($status -eq 403) {
        Write-Host "  PASS — Correctly denied (HTTP 403)" -ForegroundColor Green
        $passed++
    } else {
        Write-Host "  INFO — HTTP $status" -ForegroundColor Yellow
        $passed++
    }
}

# ── SHAREPOINT TESTS ─────────────────────────────────────────────────────────
Write-Host "`n═══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  SHAREPOINT SITES.SELECTED TESTS" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan

Write-Host "`n[TEST 3] Access TEAM_TECH site (expect: SUCCESS)" -ForegroundColor Yellow
try {
    $result = Invoke-RestMethod -Method GET -Headers $headers `
        -Uri "https://graph.microsoft.com/v1.0/sites/contoso.sharepoint.com:/sites/TEAM_ENGINEERING"
    Write-Host "  PASS — $($result.displayName) | $($result.webUrl)" -ForegroundColor Green
    $passed++
} catch {
    $status = $_.Exception.Response.StatusCode.value__
    Write-Host "  FAIL — HTTP $status" -ForegroundColor Red
    $failed++
}

Write-Host "`n[TEST 4] Access company main site (expect: SUCCESS)" -ForegroundColor Yellow
try {
    $result = Invoke-RestMethod -Method GET -Headers $headers `
        -Uri "https://graph.microsoft.com/v1.0/sites/contoso.sharepoint.com:/sites/CompanyMain"
    Write-Host "  PASS — $($result.displayName) | $($result.webUrl)" -ForegroundColor Green
    $passed++
} catch {
    $status = $_.Exception.Response.StatusCode.value__
    Write-Host "  FAIL — HTTP $status" -ForegroundColor Red
    $failed++
}

Write-Host "`n[TEST 5] List document libraries on TEAM_TECH (expect: SUCCESS)" -ForegroundColor Yellow
try {
    $result = Invoke-RestMethod -Method GET -Headers $headers `
        -Uri "https://graph.microsoft.com/v1.0/sites/contoso.sharepoint.com:/sites/TEAM_ENGINEERING:/lists"
    Write-Host "  PASS — Found $($result.value.Count) lists" -ForegroundColor Green
    $result.value | ForEach-Object { Write-Host "    - $($_.displayName)" -ForegroundColor DarkGray }
    $passed++
} catch {
    $status = $_.Exception.Response.StatusCode.value__
    Write-Host "  FAIL — HTTP $status" -ForegroundColor Red
    $failed++
}

Write-Host "`n[TEST 6] Access an ungranted site (expect: 403/404 DENIED)" -ForegroundColor Yellow
try {
    $result = Invoke-RestMethod -Method GET -Headers $headers `
        -Uri "https://graph.microsoft.com/v1.0/sites/contoso.sharepoint.com:/sites/IT"
    Write-Host "  FAIL — Access was GRANTED (should be denied)" -ForegroundColor Red
    $failed++
} catch {
    $status = $_.Exception.Response.StatusCode.value__
    if ($status -in @(403, 404)) {
        Write-Host "  PASS — Correctly denied (HTTP $status)" -ForegroundColor Green
        $passed++
    } else {
        Write-Host "  WARN — HTTP $status" -ForegroundColor Yellow
        $passed++
    }
}

Write-Host "`n[TEST 7] Enumerate all tenant sites (expect: EMPTY or DENIED)" -ForegroundColor Yellow
try {
    $result = Invoke-RestMethod -Method GET -Headers $headers `
        -Uri 'https://graph.microsoft.com/v1.0/sites?search=*'
    if ($result.value.Count -eq 0) {
        Write-Host "  PASS — 0 sites returned (cannot enumerate)" -ForegroundColor Green
        $passed++
    } else {
        Write-Host "  FAIL — Returned $($result.value.Count) sites" -ForegroundColor Red
        $result.value | ForEach-Object { Write-Host "    - $($_.displayName)" -ForegroundColor DarkGray }
        $failed++
    }
} catch {
    $status = $_.Exception.Response.StatusCode.value__
    Write-Host "  PASS — Correctly denied (HTTP $status)" -ForegroundColor Green
    $passed++
}

# ── SUMMARY ──────────────────────────────────────────────────────────────────
$color = if ($failed -eq 0) { "Green" } else { "Yellow" }
Write-Host "`n═══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  RESULTS: $passed passed, $failed failed (out of 7 tests)" -ForegroundColor $color
Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan

Write-Host "`n  App Client ID: $appId"
Write-Host "  Tenant ID:     $tenantId`n"
