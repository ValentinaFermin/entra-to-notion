# Monitoring and Reporting Scripts

## Daily Health Check

### Complete System Health Check
```powershell
# daily-health-check.ps1

<#
.SYNOPSIS
    Daily health check for MacBook fleet infrastructure
.DESCRIPTION
    Checks Entra ID, Exchange Online, licenses, and generates alerts
#>

$ErrorActionPreference = "Stop"
$ReportDate = Get-Date -Format "yyyy-MM-dd"
$Alerts = @()

Write-Host "=== Daily Health Check - $ReportDate ===" -ForegroundColor Cyan

# Connect to services
Connect-MgGraph -Scopes "User.Read.All", "Organization.Read.All"
Connect-ExchangeOnline -ShowBanner:$false

# 1. License Status
Write-Host "`n[1] Checking License Status..." -ForegroundColor Yellow
$LicenseThreshold = 10

$LicenseStatus = Get-MgSubscribedSku | ForEach-Object {
    $Available = $_.PrepaidUnits.Enabled - $_.ConsumedUnits
    
    [PSCustomObject]@{
        License = $_.SkuPartNumber
        Total = $_.PrepaidUnits.Enabled
        Consumed = $_.ConsumedUnits
        Available = $Available
        PercentUsed = [math]::Round(($_.ConsumedUnits / $_.PrepaidUnits.Enabled * 100), 2)
        Status = if ($Available -lt $LicenseThreshold) { "ALERT" } else { "OK" }
    }
}

$LicenseStatus | Format-Table -AutoSize

$LowLicenses = $LicenseStatus | Where-Object {$_.Status -eq "ALERT"}
if ($LowLicenses) {
    $Alerts += "LOW LICENSES: $($LowLicenses.Count) license types below threshold"
    Write-Host "⚠ WARNING: Low licenses detected" -ForegroundColor Yellow
} else {
    Write-Host "✓ All licenses OK" -ForegroundColor Green
}

# 2. New Users (Last 24 Hours)
Write-Host "`n[2] Checking New Users..." -ForegroundColor Yellow
$Yesterday = (Get-Date).AddDays(-1).ToString("yyyy-MM-ddTHH:mm:ssZ")
$NewUsers = Get-MgUser -Filter "createdDateTime ge $Yesterday" -All

Write-Host "New users in last 24h: $($NewUsers.Count)" -ForegroundColor Cyan
$NewUsers | Select-Object DisplayName, UserPrincipalName, CreatedDateTime | Format-Table

# 3. Disabled Users
Write-Host "`n[3] Checking Disabled Users..." -ForegroundColor Yellow
$DisabledUsers = Get-MgUser -Filter "accountEnabled eq false" -All
Write-Host "Total disabled users: $($DisabledUsers.Count)" -ForegroundColor Cyan

$RecentlyDisabled = $DisabledUsers | Where-Object {
    $_.CreatedDateTime -gt (Get-Date).AddDays(-7)
}
if ($RecentlyDisabled) {
    Write-Host "Recently disabled (last 7 days): $($RecentlyDisabled.Count)" -ForegroundColor Yellow
    $RecentlyDisabled | Select-Object DisplayName, UserPrincipalName | Format-Table
}

# 4. Users Without Licenses
Write-Host "`n[4] Checking Unlicensed Users..." -ForegroundColor Yellow
$UnlicensedUsers = Get-MgUser -All -Property DisplayName,UserPrincipalName,AssignedLicenses,AccountEnabled |
    Where-Object {$_.AccountEnabled -and $_.AssignedLicenses.Count -eq 0}

Write-Host "Active users without licenses: $($UnlicensedUsers.Count)" -ForegroundColor Cyan
if ($UnlicensedUsers.Count -gt 0) {
    $Alerts += "UNLICENSED USERS: $($UnlicensedUsers.Count) active users without licenses"
    $UnlicensedUsers | Select-Object DisplayName, UserPrincipalName | Format-Table
}

# 5. Mailbox Health
Write-Host "`n[5] Checking Mailbox Health..." -ForegroundColor Yellow

# Large mailboxes (>40GB)
$LargeMailboxes = Get-Mailbox -ResultSize Unlimited | Get-MailboxStatistics |
    Where-Object {
        $Size = $_.TotalItemSize.Value.ToString().Split("(")[1].Split(" ")[0].Replace(",","")
        [int64]$Size -gt 40GB
    } |
    Select-Object DisplayName, @{N="Size(GB)";E={[math]::Round(($_.TotalItemSize.Value.ToString().Split("(")[1].Split(" ")[0].Replace(",","")/1GB),2)}}

if ($LargeMailboxes) {
    Write-Host "Mailboxes over 40GB: $($LargeMailboxes.Count)" -ForegroundColor Yellow
    $LargeMailboxes | Format-Table
    $Alerts += "LARGE MAILBOXES: $($LargeMailboxes.Count) mailboxes over 40GB"
}

# Shared mailbox permissions
$SharedMailboxes = Get-Mailbox -RecipientTypeDetails SharedMailbox -ResultSize Unlimited
Write-Host "Total shared mailboxes: $($SharedMailboxes.Count)" -ForegroundColor Cyan

# 6. Failed Logins (Security)
Write-Host "`n[6] Checking Failed Login Attempts..." -ForegroundColor Yellow
# Note: Requires Azure AD Premium for sign-in logs
# This is a placeholder - implement with Microsoft Graph sign-in logs API

# 7. Service Health
Write-Host "`n[7] Checking Service Health..." -ForegroundColor Yellow
# Get service health from Microsoft Graph
$ServiceHealth = Get-MgServiceAnnouncementIssue -Filter "service eq 'Exchange' or service eq 'AzureActiveDirectory'"

if ($ServiceHealth) {
    Write-Host "⚠ Active service issues: $($ServiceHealth.Count)" -ForegroundColor Yellow
    $ServiceHealth | Select-Object Service, Title, Status | Format-Table
    $Alerts += "SERVICE ISSUES: $($ServiceHealth.Count) active incidents"
} else {
    Write-Host "✓ No service issues" -ForegroundColor Green
}

# 8. Generate Report
Write-Host "`n[8] Generating Report..." -ForegroundColor Yellow

$Report = [PSCustomObject]@{
    Date = $ReportDate
    TotalUsers = (Get-MgUser -All).Count
    ActiveUsers = (Get-MgUser -Filter "accountEnabled eq true" -All).Count
    DisabledUsers = $DisabledUsers.Count
    NewUsers24h = $NewUsers.Count
    UnlicensedUsers = $UnlicensedUsers.Count
    LowLicenses = $LowLicenses.Count
    LargeMailboxes = if ($LargeMailboxes) { $LargeMailboxes.Count } else { 0 }
    ServiceIssues = if ($ServiceHealth) { $ServiceHealth.Count } else { 0 }
    AlertsCount = $Alerts.Count
}

$Report | Format-List

# Export detailed report
$ReportPath = "health-check-$ReportDate.json"
$Report | ConvertTo-Json | Out-File $ReportPath
Write-Host "✓ Report saved: $ReportPath" -ForegroundColor Green

# 9. Send Alert Email if Issues Found
if ($Alerts.Count -gt 0) {
    Write-Host "`n⚠ ALERTS DETECTED:" -ForegroundColor Red
    $Alerts | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    
    $AlertBody = @"
Daily Health Check - $ReportDate

ALERTS:
$($Alerts -join "`n")

Summary:
- Total Users: $($Report.TotalUsers)
- Active Users: $($Report.ActiveUsers)
- New Users (24h): $($Report.NewUsers24h)
- Unlicensed Users: $($Report.UnlicensedUsers)
- Low Licenses: $($Report.LowLicenses)
- Large Mailboxes: $($Report.LargeMailboxes)

Full report: $ReportPath
"@
    
    # Send email (configure SMTP settings)
    # Send-MailMessage -To "admin@company.com" -Subject "⚠ Health Check Alert - $ReportDate" -Body $AlertBody
    
    Write-Host "`n⚠ Email alert would be sent (configure SMTP)" -ForegroundColor Yellow
} else {
    Write-Host "`n✓ No issues detected - All systems healthy" -ForegroundColor Green
}

# Cleanup
Disconnect-MgGraph -ErrorAction SilentlyContinue
Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue

Write-Host "`n=== Health Check Complete ===" -ForegroundColor Cyan
```

## Weekly Reports

### Weekly User Activity Report
```powershell
# weekly-user-report.ps1

param(
    [int]$DaysBack = 7
)

Connect-MgGraph -Scopes "User.Read.All", "AuditLog.Read.All"

$StartDate = (Get-Date).AddDays(-$DaysBack).ToString("yyyy-MM-dd")
$EndDate = (Get-Date).ToString("yyyy-MM-dd")

Write-Host "=== Weekly User Report ($StartDate to $EndDate) ===" -ForegroundColor Cyan

# New users
$NewUsers = Get-MgUser -Filter "createdDateTime ge $($StartDate)T00:00:00Z" -All |
    Select-Object DisplayName, UserPrincipalName, Department, CreatedDateTime

Write-Host "`nNew Users: $($NewUsers.Count)"
$NewUsers | Format-Table

# Modified users
# Note: Requires change tracking - implement with audit logs

# License changes
$AllUsers = Get-MgUser -All -Property DisplayName,UserPrincipalName,AssignedLicenses

$LicenseReport = $AllUsers | Where-Object {$_.AssignedLicenses.Count -gt 0} | ForEach-Object {
    $User = $_
    $Licenses = Get-MgUserLicenseDetail -UserId $User.Id
    
    [PSCustomObject]@{
        User = $User.DisplayName
        Email = $User.UserPrincipalName
        Licenses = ($Licenses.SkuPartNumber -join ", ")
        Count = $Licenses.Count
    }
}

Write-Host "`nLicense Summary:"
$LicenseReport | Group-Object Licenses | Select-Object Name, Count | Format-Table

# Export
$NewUsers | Export-Csv "weekly-new-users-$EndDate.csv" -NoTypeInformation
$LicenseReport | Export-Csv "weekly-licenses-$EndDate.csv" -NoTypeInformation

Disconnect-MgGraph
```

## Monthly Cost Report

### Monthly License Cost Analysis
```powershell
# monthly-cost-report.ps1

Connect-MgGraph -Scopes "User.Read.All"

# Define costs (update monthly)
$LicenseCosts = @{
    "SPE_E5" = 57.00
    "POWER_BI_PRO" = 9.99
    "FLOW_PER_USER" = 15.00
    "EMSPREMIUM" = 14.80
    "Microsoft_365_Copilot" = 30.00
}

Write-Host "=== Monthly License Cost Report ===" -ForegroundColor Cyan
Write-Host "Report Date: $(Get-Date -Format 'yyyy-MM-dd')`n"

$TotalMonthlyCost = 0
$CostBreakdown = @()

Get-MgSubscribedSku | ForEach-Object {
    $SkuName = $_.SkuPartNumber
    $Consumed = $_.ConsumedUnits
    
    if ($LicenseCosts.ContainsKey($SkuName)) {
        $CostPerLicense = $LicenseCosts[$SkuName]
        $SubtotalCost = $Consumed * $CostPerLicense
        $TotalMonthlyCost += $SubtotalCost
        
        $CostBreakdown += [PSCustomObject]@{
            License = $SkuName
            Quantity = $Consumed
            CostPerLicense = $CostPerLicense
            SubTotal = $SubtotalCost
        }
    }
}

$CostBreakdown | Format-Table -AutoSize

Write-Host "`nTotal Monthly Cost: `$$($TotalMonthlyCost.ToString('N2'))" -ForegroundColor Cyan
Write-Host "Annual Cost: `$$($($TotalMonthlyCost * 12).ToString('N2'))`n" -ForegroundColor Cyan

# Cost per department
Write-Host "Cost by Department:" -ForegroundColor Yellow

$DepartmentCosts = Get-MgUser -All -Property Department,AssignedLicenses |
    Where-Object {$_.AssignedLicenses.Count -gt 0} |
    Group-Object Department |
    ForEach-Object {
        $Dept = $_.Name
        $UserCount = $_.Count
        
        # Simplified: assume E5 for all
        $DeptCost = $UserCount * 57.00
        
        [PSCustomObject]@{
            Department = if ($Dept) { $Dept } else { "Unassigned" }
            Users = $UserCount
            EstimatedCost = $DeptCost
        }
    } |
    Sort-Object EstimatedCost -Descending

$DepartmentCosts | Format-Table -AutoSize

$CostBreakdown | Export-Csv "monthly-cost-$(Get-Date -Format 'yyyy-MM').csv" -NoTypeInformation

Disconnect-MgGraph
```

## Real-Time Monitoring

### Live Dashboard Data Collector
```powershell
# monitor-live.ps1

# Runs continuously and updates a JSON file for dashboard

$OutputFile = "live-stats.json"
$RefreshInterval = 300  # 5 minutes

Write-Host "Starting live monitoring... (Ctrl+C to stop)"
Write-Host "Refresh interval: $RefreshInterval seconds"
Write-Host "Output: $OutputFile`n"

while ($true) {
    try {
        Connect-MgGraph -Scopes "User.Read.All" -ErrorAction SilentlyContinue
        
        $Stats = [PSCustomObject]@{
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            TotalUsers = (Get-MgUser -ConsistencyLevel eventual -Count userCount).Count
            ActiveUsers = (Get-MgUser -Filter "accountEnabled eq true" -ConsistencyLevel eventual -Count activeCount).Count
            Licenses = Get-MgSubscribedSku | ForEach-Object {
                [PSCustomObject]@{
                    Name = $_.SkuPartNumber
                    Total = $_.PrepaidUnits.Enabled
                    Used = $_.ConsumedUnits
                    Available = $_.PrepaidUnits.Enabled - $_.ConsumedUnits
                }
            }
        }
        
        $Stats | ConvertTo-Json -Depth 3 | Out-File $OutputFile
        
        Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Updated - Total: $($Stats.TotalUsers) | Active: $($Stats.ActiveUsers)"
        
        Disconnect-MgGraph -ErrorAction SilentlyContinue
        
        Start-Sleep -Seconds $RefreshInterval
    }
    catch {
        Write-Host "Error: $_" -ForegroundColor Red
        Start-Sleep -Seconds 60
    }
}
```

## Audit Logging

### User Change Audit Logger
```powershell
# audit-user-changes.ps1

# Logs all user changes to a file

$AuditFile = "user-audit-$(Get-Date -Format 'yyyy-MM').log"

Connect-MgGraph -Scopes "AuditLog.Read.All"

# Get audit logs from last 24 hours
$StartDate = (Get-Date).AddDays(-1)

$AuditLogs = Get-MgAuditLogDirectoryAudit -Filter "activityDateTime ge $($StartDate.ToString('yyyy-MM-ddTHH:mm:ssZ'))" |
    Where-Object {$_.Category -eq "UserManagement"}

foreach ($Log in $AuditLogs) {
    $Entry = @{
        Timestamp = $Log.ActivityDateTime
        Activity = $Log.ActivityDisplayName
        User = $Log.InitiatedBy.User.UserPrincipalName
        TargetUser = $Log.TargetResources[0].UserPrincipalName
        Result = $Log.Result
    }
    
    $Entry | ConvertTo-Json -Compress | Out-File $AuditFile -Append
}

Write-Host "Audit log saved: $AuditFile"
Write-Host "Entries logged: $($AuditLogs.Count)"

Disconnect-MgGraph
```
