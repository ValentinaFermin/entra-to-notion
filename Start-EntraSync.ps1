<#
.SYNOPSIS
    Entra ID → Notion Sync — Subscription & License Tracker

.DESCRIPTION
    Pulls license SKUs and enterprise applications from Microsoft Entra ID
    via Graph API, then syncs to a Notion database.

    Supports both:
      - Interactive (delegated) auth: Connect-MgGraph -Scopes ...
      - App-only (client credentials) auth: via .env config

.EXAMPLE
    .\Start-EntraSync.ps1                     # Full sync
    .\Start-EntraSync.ps1 -WhatIf             # Dry run
    .\Start-EntraSync.ps1 -Interactive         # Use delegated auth (your browser)
    .\Start-EntraSync.ps1 -SkipEnterpriseApps  # Licenses only
    .\Start-EntraSync.ps1 -SkipNotion -ExportCsv
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Interactive,          # Use delegated auth instead of client credentials
    [switch]$SkipEnterpriseApps,
    [switch]$SkipNotion,
    [switch]$ExportCsv,
    [switch]$ExportJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ============================================================
#  IMPORT MODULES
# ============================================================

$src = Join-Path $PSScriptRoot "src"
Import-Module (Join-Path $src "Utils" "Logger.psm1")     -Force
Import-Module (Join-Path $src "Utils" "Config.psm1")     -Force
Import-Module (Join-Path $src "Utils" "SkuMapping.psm1") -Force
Import-Module (Join-Path $src "Collectors" "EntraCollector.psm1") -Force
Import-Module (Join-Path $src "Notion" "NotionSync.psm1") -Force

# ============================================================
#  MAIN
# ============================================================

Write-Banner

$Config = Get-TrackerConfig
Write-Log "Configuration loaded"

$outputDir = Join-Path $PSScriptRoot "output"
Initialize-AuditLog -OutputDir $outputDir

# --- AUTHENTICATE ---
if ($Interactive) {
    # Delegated auth — opens browser consent prompt
    Write-Log "Using interactive (delegated) authentication..."

    $scopes = @(
        "User.Read.All",
        "Application.Read.All",
        "Organization.Read.All",
        "Directory.Read.All",
        "AuditLog.Read.All"
    )

    try {
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    } catch { }

    Connect-MgGraph -Scopes $scopes -NoWelcome
    Write-Log "Connected via interactive auth" -Level SUCCESS

    # Verify scopes
    $granted = (Get-MgContext).Scopes
    Write-Log "Granted scopes: $($granted -join ', ')"

    $required = @("Application.Read.All", "Organization.Read.All")
    $missing = $required | Where-Object { $_ -notin $granted }
    if ($missing) {
        Write-Log "Missing scopes: $($missing -join ', ')" -Level WARN
        Write-Log "You may need admin consent. Ask your Global Admin to approve." -Level WARN
    }
}
else {
    # App-only auth via client credentials
    $connected = Connect-EntraGraph -Config $Config
    if (-not $connected) {
        Write-Log "Try: .\Start-EntraSync.ps1 -Interactive" -Level WARN
        exit 1
    }
}

$allServices = @()

# --- PHASE 1: LICENSE SKUs ---
$licenses = Get-EntraLicenses -Config $Config
$allServices += $licenses

# --- PHASE 2: ENTERPRISE APPS ---
if (-not $SkipEnterpriseApps) {
    $apps = Get-EntraEnterpriseApps -Config $Config
    $allServices += $apps
}

# --- SUMMARY ---
Write-Section "Summary"
Write-Log "Total records: $($allServices.Count)"
Write-Log "  Licenses:        $(($allServices | Where-Object RecordType -eq 'License').Count)"
Write-Log "  Enterprise Apps: $(($allServices | Where-Object RecordType -eq 'Enterprise App').Count)"

Write-Host ""
$allServices | Sort-Object RecordType, ServiceName | Format-Table -Property `
    @{Label='Service';  Expression={$_.ServiceName}; Width=40},
    @{Label='Type';     Expression={$_.RecordType};  Width=16},
    @{Label='Category'; Expression={$_.Category};    Width=15},
    @{Label='Status';   Expression={$_.Status};      Width=14},
    @{Label='Assigned'; Expression={$_.AssignedLicenses}; Width=9},
    @{Label='Total';    Expression={$_.TotalLicenses};    Width=7}

# --- EXPORTS ---
$ts = Get-Date -Format "yyyyMMdd_HHmmss"

if ($ExportCsv) {
    $path = Join-Path $outputDir "entra_audit_$ts.csv"
    $allServices | Export-Csv -Path $path -NoTypeInformation
    Write-Log "CSV exported: $path" -Level SUCCESS
}

if ($ExportJson) {
    $path = Join-Path $outputDir "entra_audit_$ts.json"
    $allServices | ConvertTo-Json -Depth 5 | Out-File $path -Encoding utf8
    Write-Log "JSON exported: $path" -Level SUCCESS
}

# Always save latest backup
$allServices | ConvertTo-Json -Depth 5 | Out-File (Join-Path $outputDir "latest.json") -Encoding utf8

# --- NOTION SYNC ---
if (-not $SkipNotion) {
    Sync-AllToNotion -Config $Config -Services $allServices
}

# --- CLEANUP ---
if (-not $Interactive) {
    Disconnect-EntraGraph
}
else {
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
}

Write-Host ""
Write-Log "Done! $($allServices.Count) services processed." -Level SUCCESS
Write-Host ""

return $allServices
