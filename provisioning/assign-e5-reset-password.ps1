param(
    [Parameter(Mandatory=$true)]
    [string]$UserPrincipalName
)

# Requires Privileged Authentication Administrator or Global Administrator role
Connect-MgGraph -Scopes "User.ReadWrite.All", "Directory.ReadWrite.All", "Organization.Read.All", "UserAuthenticationMethod.ReadWrite.All"

$User = Get-MgUser -Filter "UserPrincipalName eq '$UserPrincipalName'"
if (-not $User) {
    Write-Host "User not found: $UserPrincipalName" -ForegroundColor Red
    exit 1
}

Update-MgUser -UserId $User.Id -UsageLocation "ES"
Write-Host "[0/5] Usage location set to Spain (ES)" -ForegroundColor Green

# 1. Assign E5 license
$E5Sku = Get-MgSubscribedSku -All | Where-Object { $_.SkuPartNumber -eq "SPE_E5" }
if (-not $E5Sku) {
    Write-Host "E5 SKU not found in tenant" -ForegroundColor Red
    exit 1
}

$AvailableUnits = $E5Sku.PrepaidUnits.Enabled - $E5Sku.ConsumedUnits
if ($AvailableUnits -le 0) {
    Write-Host "No available E5 licenses ($($E5Sku.ConsumedUnits)/$($E5Sku.PrepaidUnits.Enabled) consumed)" -ForegroundColor Red
    exit 1
}

Set-MgUserLicense -UserId $User.Id -AddLicenses @(@{ SkuId = $E5Sku.SkuId }) -RemoveLicenses @()
Write-Host "[1/5] E5 license assigned" -ForegroundColor Green

# 2. Assign Power Automate Free license (FLOW_FREE)
$FlowSku = Get-MgSubscribedSku -All | Where-Object { $_.SkuPartNumber -eq "FLOW_FREE" }
if (-not $FlowSku) {
    Write-Host "Power Automate Free SKU not found in tenant — skipping" -ForegroundColor Yellow
} else {
    $FlowAvailable = $FlowSku.PrepaidUnits.Enabled - $FlowSku.ConsumedUnits
    if ($FlowAvailable -le 0) {
        Write-Host "No available Power Automate Free licenses ($($FlowSku.ConsumedUnits)/$($FlowSku.PrepaidUnits.Enabled) consumed) — skipping" -ForegroundColor Yellow
    } else {
        Set-MgUserLicense -UserId $User.Id -AddLicenses @(@{ SkuId = $FlowSku.SkuId }) -RemoveLicenses @()
        Write-Host "[2/5] Power Automate Free license assigned" -ForegroundColor Green
    }
}

# 3. Set default calendar permissions to LimitedDetails
Connect-ExchangeOnline -ShowBanner:$false
$MaxAttempts = 6
$CalendarSet = $false
for ($attempt = 1; $attempt -le $MaxAttempts -and -not $CalendarSet; $attempt++) {
    try {
        Set-MailboxFolderPermission -Identity "${UserPrincipalName}:\Calendar" -User Default -AccessRights LimitedDetails -ErrorAction Stop
        $CalendarSet = $true
        Write-Host "[3/5] Calendar default permission set to LimitedDetails" -ForegroundColor Green
    } catch {
        if ($attempt -lt $MaxAttempts) {
            Write-Host "  Calendar not ready yet — attempt $attempt/$MaxAttempts, retrying in 30s..." -ForegroundColor Gray
            Start-Sleep -Seconds 30
        } else {
            Write-Host "Calendar permission could not be set after $MaxAttempts attempts — set manually later" -ForegroundColor Yellow
        }
    }
}
Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue

# 4. Generate and set new password
Write-Host "Generating temporary password..." -ForegroundColor Yellow
$Upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
$Lower = 'abcdefghijklmnopqrstuvwxyz'
$Digits = '0123456789'
$Special = '!@#$%&*?'
$All = $Upper + $Lower + $Digits + $Special

$PasswordChars = @(
    $Upper[(Get-Random -Maximum $Upper.Length)]
    $Lower[(Get-Random -Maximum $Lower.Length)]
    $Digits[(Get-Random -Maximum $Digits.Length)]
    $Special[(Get-Random -Maximum $Special.Length)]
)
for ($i = $PasswordChars.Count; $i -lt 16; $i++) {
    $PasswordChars += $All[(Get-Random -Maximum $All.Length)]
}
$NewPassword = -join ($PasswordChars | Get-Random -Count $PasswordChars.Count)
Write-Host "Generated temporary password: $NewPassword" -ForegroundColor Yellow

# 5. Reset password + force change on next login
try {
    Update-MgUser -UserId $User.Id -PasswordProfile @{
        Password = $NewPassword
        ForceChangePasswordNextSignIn = $true
    } -ErrorAction Stop
    Write-Host "[4/5] Password reset" -ForegroundColor Green
    Write-Host "[5/5] User must change password on next login" -ForegroundColor Green
    $PasswordReset = $true
} catch {
    Write-Host "[4/5] ERROR: Password reset failed — $($_.Exception.Message)" -ForegroundColor Red
    $PasswordReset = $false
}

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "User:               $UserPrincipalName"
Write-Host "Licenses:           Microsoft 365 E5, Power Automate Free"
if ($CalendarSet) {
    Write-Host "Calendar:           Default permission set to LimitedDetails" -ForegroundColor Green
} else {
    Write-Host "Calendar:           FAILED — set manually later" -ForegroundColor Red
}
if ($PasswordReset) {
    Write-Host "Temporary password: $NewPassword"
    Write-Host "Force change:       Yes (next login)"
} else {
    Write-Host "Password reset:     FAILED — reset manually later" -ForegroundColor Red
}
