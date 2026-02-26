$tenantId     = "00000000-0000-0000-0000-000000000000"  # Your tenant ID
$clientId     = "00000000-0000-0000-0000-000000000001"  # Your app client ID
$clientSecret = "YOUR_CLIENT_SECRET_HERE"

# ── Authenticate as the app using OAuth2 client credentials ──────────────────
Write-Host "`n=== Authenticating as app ===" -ForegroundColor Cyan

$tokenBody = @{
    grant_type    = "client_credentials"
    client_id     = $clientId
    client_secret = $clientSecret
    scope         = "https://graph.microsoft.com/.default"
}

$tokenResponse = Invoke-RestMethod -Method POST `
    -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" `
    -ContentType "application/x-www-form-urlencoded" `
    -Body $tokenBody

$token = $tokenResponse.access_token
$headers = @{ Authorization = "Bearer $token" }

if ($token) {
    Write-Host "Authenticated successfully`n" -ForegroundColor Green
} else {
    Write-Host "Authentication FAILED" -ForegroundColor Red
    exit 1
}

$passed = 0
$failed = 0

# ── MAILBOX TESTS ────────────────────────────────────────────────────────────

Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  MAILBOX TESTS" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan

# TEST 1: Read target user's mailbox — should SUCCEED
Write-Host "`n[TEST 1] Read target user's mailbox (expect: SUCCESS)" -ForegroundColor Yellow
try {
    $result = Invoke-RestMethod -Method GET -Headers $headers `
        -Uri "https://graph.microsoft.com/v1.0/users/targetuser@company.com/messages?`$top=3&`$select=subject,receivedDateTime"
    Write-Host "  PASS — Retrieved $($result.value.Count) messages" -ForegroundColor Green
    $result.value | ForEach-Object { Write-Host "    • $($_.subject)" -ForegroundColor DarkGray }
    $passed++
} catch {
    $status = $_.Exception.Response.StatusCode.value__
    Write-Host "  FAIL — HTTP $status : $($_.ErrorDetails.Message)" -ForegroundColor Red
    $failed++
}

# TEST 2: Read another user's mailbox — should FAIL (403)
Write-Host "`n[TEST 2] Read another user's mailbox (expect: 403 DENIED)" -ForegroundColor Yellow
try {
    $result = Invoke-RestMethod -Method GET -Headers $headers `
        -Uri "https://graph.microsoft.com/v1.0/users/otheruser@company.com/messages?`$top=3&`$select=subject,receivedDateTime"
    Write-Host "  FAIL — Access was GRANTED (should have been denied!)" -ForegroundColor Red
    $failed++
} catch {
    $status = $_.Exception.Response.StatusCode.value__
    if ($status -eq 403) {
        Write-Host "  PASS — Correctly denied (HTTP 403)" -ForegroundColor Green
        $passed++
    } else {
        Write-Host "  WARN — Denied but unexpected status: HTTP $status" -ForegroundColor Yellow
        $passed++
    }
}

# ── SHAREPOINT SITE TESTS ───────────────────────────────────────────────────

Write-Host "`n═══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  SHAREPOINT SITES.SELECTED TESTS" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan

# TEST 3: Access TEAM_TECH site — should SUCCEED
Write-Host "`n[TEST 3] Access TEAM_TECH site (expect: SUCCESS)" -ForegroundColor Yellow
try {
    $result = Invoke-RestMethod -Method GET -Headers $headers `
        -Uri "https://graph.microsoft.com/v1.0/sites/contoso.sharepoint.com:/sites/TEAM_ENGINEERING"
    Write-Host "  PASS — Site: $($result.displayName) | URL: $($result.webUrl)" -ForegroundColor Green
    $passed++
} catch {
    $status = $_.Exception.Response.StatusCode.value__
    Write-Host "  FAIL — HTTP $status" -ForegroundColor Red
    $failed++
}

# TEST 4: Access company main site — should SUCCEED
Write-Host "`n[TEST 4] Access company main site (expect: SUCCESS)" -ForegroundColor Yellow
try {
    $result = Invoke-RestMethod -Method GET -Headers $headers `
        -Uri "https://graph.microsoft.com/v1.0/sites/contoso.sharepoint.com:/sites/CompanyMain"
    Write-Host "  PASS — Site: $($result.displayName) | URL: $($result.webUrl)" -ForegroundColor Green
    $passed++
} catch {
    $status = $_.Exception.Response.StatusCode.value__
    Write-Host "  FAIL — HTTP $status" -ForegroundColor Red
    $failed++
}

# TEST 5: List document libraries on TEAM_TECH — should SUCCEED
Write-Host "`n[TEST 5] List document libraries on TEAM_TECH (expect: SUCCESS)" -ForegroundColor Yellow
try {
    $result = Invoke-RestMethod -Method GET -Headers $headers `
        -Uri "https://graph.microsoft.com/v1.0/sites/contoso.sharepoint.com:/sites/TEAM_ENGINEERING:/lists"
    Write-Host "  PASS — Found $($result.value.Count) lists" -ForegroundColor Green
    $result.value | ForEach-Object { Write-Host "    • $($_.displayName)" -ForegroundColor DarkGray }
    $passed++
} catch {
    $status = $_.Exception.Response.StatusCode.value__
    Write-Host "  FAIL — HTTP $status" -ForegroundColor Red
    $failed++
}

# TEST 6: Access a site NOT granted — should FAIL (403)
Write-Host "`n[TEST 6] Access ungrated site (expect: 403 DENIED)" -ForegroundColor Yellow
try {
    $result = Invoke-RestMethod -Method GET -Headers $headers `
        -Uri "https://graph.microsoft.com/v1.0/sites/contoso.sharepoint.com:/sites/IT"
    Write-Host "  FAIL — Access was GRANTED (should have been denied!)" -ForegroundColor Red
    $failed++
} catch {
    $status = $_.Exception.Response.StatusCode.value__
    if ($status -eq 403) {
        Write-Host "  PASS — Correctly denied (HTTP 403)" -ForegroundColor Green
        $passed++
    } elseif ($status -eq 404) {
        Write-Host "  PASS — Site not found/not accessible (HTTP 404)" -ForegroundColor Green
        $passed++
    } else {
        Write-Host "  WARN — Denied but unexpected status: HTTP $status" -ForegroundColor Yellow
        $passed++
    }
}

# TEST 7: Enumerate all sites — should FAIL or return empty
Write-Host "`n[TEST 7] Enumerate all tenant sites (expect: EMPTY or DENIED)" -ForegroundColor Yellow
try {
    $result = Invoke-RestMethod -Method GET -Headers $headers `
        -Uri "https://graph.microsoft.com/v1.0/sites?search=*"
    if ($result.value.Count -eq 0) {
        Write-Host "  PASS — Returned 0 sites (cannot enumerate)" -ForegroundColor Green
        $passed++
    } else {
        Write-Host "  FAIL — Returned $($result.value.Count) sites (should not be able to enumerate)" -ForegroundColor Red
        $result.value | ForEach-Object { Write-Host "    • $($_.displayName)" -ForegroundColor DarkGray }
        $failed++
    }
} catch {
    $status = $_.Exception.Response.StatusCode.value__
    Write-Host "  PASS — Correctly denied enumeration (HTTP $status)" -ForegroundColor Green
    $passed++
}

# ── SUMMARY ──────────────────────────────────────────────────────────────────
Write-Host "`n═══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  RESULTS: $passed passed, $failed failed (out of 7 tests)" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })
Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
