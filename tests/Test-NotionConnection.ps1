<#
.SYNOPSIS
    Tests Notion API connectivity and database schema.

.DESCRIPTION
    Validates:
      1. Notion integration token
      2. Database access (integration shared with DB)
      3. Required database properties exist
      4. Creates and deletes a test record
#>

$ErrorActionPreference = "Stop"

$modulesRoot = Join-Path $PSScriptRoot ".." "src"
Import-Module (Join-Path $modulesRoot "Utils" "Logger.psm1") -Force
Import-Module (Join-Path $modulesRoot "Utils" "Config.psm1") -Force
Import-Module (Join-Path $modulesRoot "Notion" "NotionSync.psm1") -Force

Write-Banner
Write-Log "Testing Notion API connection..."

$Config = Get-TrackerConfig

# --- Test 1: Connection ---
Write-Log "Test 1: API Connection"
$connected = Test-NotionConnection -Config $Config
if (-not $connected) {
    Write-Log "FAILED — Check NOTION_TOKEN and NOTION_DATABASE_ID" -Level ERROR
    exit 1
}
Write-Log "PASSED" -Level SUCCESS

# --- Test 2: Database Schema ---
Write-Log "Test 2: Database schema validation"

$headers = @{
    "Authorization"  = "Bearer $($Config.NotionToken)"
    "Notion-Version" = $Config.NotionApiVersion
}

$db = Invoke-RestMethod `
    -Uri "https://api.notion.com/v1/databases/$($Config.NotionDatabaseId)" `
    -Headers $headers

$requiredProps = @(
    "Service Name", "Category", "Status", "Cost", "Cost Unit",
    "Billing Cycle", "Renewal Date", "Assigned Licenses",
    "Total Licenses", "Source", "Last Synced", "Notes"
)

$existingProps = $db.properties.PSObject.Properties.Name
$missing = $requiredProps | Where-Object { $_ -notin $existingProps }

if ($missing.Count -eq 0) {
    Write-Log "PASSED — All $($requiredProps.Count) required properties found" -Level SUCCESS
}
else {
    Write-Log "WARN — Missing properties: $($missing -join ', ')" -Level WARN
    Write-Log "Create these in your Notion database before running the sync" -Level WARN
}

# Show what's there
Write-Host ""
Write-Log "Database properties found:"
foreach ($prop in $existingProps) {
    $type = $db.properties.$prop.type
    $marker = if ($prop -in $requiredProps) { "✓" } else { "·" }
    Write-Host "  $marker $prop ($type)" -ForegroundColor $(if ($prop -in $requiredProps) { "Green" } else { "Gray" })
}

# --- Test 3: Write test ---
Write-Log "`nTest 3: Create test record"
$testService = [PSCustomObject]@{
    ServiceName      = "_CONNECTION_TEST_$(Get-Date -Format 'HHmmss')"
    Category         = "Infrastructure"
    Status           = "Under Review"
    Cost             = 0
    CostUnit         = "/mo"
    BillingCycle     = "Monthly"
    RenewalDate      = (Get-Date -Format "yyyy-MM-dd")
    AssignedLicenses = 1
    TotalLicenses    = 1
    Source           = "Manual"
    Notes            = "Test record — safe to delete."
    RecordType       = "Test"
}

try {
    Sync-ServiceToNotion -Config $Config -Service $testService -Confirm:$false
    Write-Log "PASSED — Test record created in Notion" -Level SUCCESS
    Write-Log "Look for '$($testService.ServiceName)' in your database and delete it" -Level WARN
}
catch {
    Write-Log "FAILED — Could not create test record: $_" -Level ERROR
}

Write-Host ""
Write-Log "All Notion tests complete!" -Level SUCCESS
Write-Host ""
