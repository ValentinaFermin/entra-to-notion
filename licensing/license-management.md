# Microsoft 365 License Management

## Authentication
```powershell
Connect-MgGraph -Scopes "User.ReadWrite.All", "Organization.Read.All"
```

## View Available Licenses

### List All Subscribed SKUs
```powershell
Get-MgSubscribedSku | Select-Object SkuPartNumber,ConsumedUnits,
    @{N="Available";E={$_.PrepaidUnits.Enabled - $_.ConsumedUnits}}
```

### Common SKU Part Numbers
- `SPE_E5` - Microsoft 365 E5
- `POWER_BI_PRO` - Power BI Pro
- `FLOW_FREE` - Power Automate Free
- `EMSPREMIUM` - Enterprise Mobility + Security E5
- `IDENTITY_THREAT_PROTECTION` - Microsoft Defender for Identity

### Get Specific SKU Details
```powershell
$E5Sku = Get-MgSubscribedSku -All | Where-Object {$_.SkuPartNumber -eq "SPE_E5"}
$E5Sku | Select-Object SkuPartNumber,ConsumedUnits,
    @{N="Enabled";E={$_.PrepaidUnits.Enabled}},
    @{N="Available";E={$_.PrepaidUnits.Enabled - $_.ConsumedUnits}}
```

## Assign Licenses

### Assign Single License
```powershell
# Get SKU ID
$SkuId = (Get-MgSubscribedSku -All | Where-Object {$_.SkuPartNumber -eq "SPE_E5"}).SkuId

# Assign to user
Set-MgUserLicense -UserId "jdoe@company.com" -AddLicenses @{SkuId = $SkuId} -RemoveLicenses @()
```

### Assign Multiple Licenses
```powershell
$E5SkuId = (Get-MgSubscribedSku -All | Where-Object {$_.SkuPartNumber -eq "SPE_E5"}).SkuId
$PowerBISkuId = (Get-MgSubscribedSku -All | Where-Object {$_.SkuPartNumber -eq "POWER_BI_PRO"}).SkuId

Set-MgUserLicense -UserId "jdoe@company.com" `
    -AddLicenses @(
        @{SkuId = $E5SkuId}
        @{SkuId = $PowerBISkuId}
    ) `
    -RemoveLicenses @()
```

### Assign License with Disabled Services
```powershell
# Get service plan IDs to disable
$E5Sku = Get-MgSubscribedSku -All | Where-Object {$_.SkuPartNumber -eq "SPE_E5"}
$E5Sku.ServicePlans | Select-Object ServicePlanName,ServicePlanId

# Disable specific services (e.g., Yammer, Sway)
$DisabledPlans = @(
    "43de0ff5-c92c-492b-9116-175376d08c38", # Yammer
    "a23b959c-7ce8-4e57-9140-b90eb88a9e97"  # Sway
)

Set-MgUserLicense -UserId "jdoe@company.com" `
    -AddLicenses @{
        SkuId = $E5Sku.SkuId
        DisabledPlans = $DisabledPlans
    } `
    -RemoveLicenses @()
```

## Remove Licenses

### Remove Single License
```powershell
$E5SkuId = (Get-MgSubscribedSku -All | Where-Object {$_.SkuPartNumber -eq "SPE_E5"}).SkuId

Set-MgUserLicense -UserId "jdoe@company.com" -AddLicenses @() -RemoveLicenses @($E5SkuId)
```

### Remove All Licenses
```powershell
$User = Get-MgUserLicenseDetail -UserId "jdoe@company.com"
$LicensesToRemove = $User.SkuId

Set-MgUserLicense -UserId "jdoe@company.com" -AddLicenses @() -RemoveLicenses $LicensesToRemove
```

## View User Licenses

### Get User's Assigned Licenses
```powershell
Get-MgUserLicenseDetail -UserId "jdoe@company.com" |
    Select-Object @{N="License";E={$_.SkuPartNumber}}
```

### Get User's License with Service Plans
```powershell
$User = Get-MgUser -UserId "jdoe@company.com" -Property AssignedLicenses,LicenseAssignmentStates

foreach ($License in $User.AssignedLicenses) {
    $Sku = Get-MgSubscribedSku -SubscribedSkuId $License.SkuId
    Write-Host "License: $($Sku.SkuPartNumber)"
    
    $Sku.ServicePlans | Where-Object {
        $License.DisabledPlans -notcontains $_.ServicePlanId
    } | Select-Object ServicePlanName | Format-Table
}
```

## Bulk License Operations

### Assign Licenses from CSV
```powershell
$Users = Import-Csv "license-assignments.csv"
$E5SkuId = (Get-MgSubscribedSku -All | Where-Object {$_.SkuPartNumber -eq "SPE_E5"}).SkuId

foreach ($User in $Users) {
    try {
        Set-MgUserLicense -UserId $User.Email -AddLicenses @{SkuId = $E5SkuId} -RemoveLicenses @()
        Write-Host "Assigned to $($User.Email)" -ForegroundColor Green
    }
    catch {
        Write-Host "Failed for $($User.Email): $_" -ForegroundColor Red
    }
}
```

### Assign Licenses Based on Group Membership
```powershell
# Note: Use Group-based licensing in Entra ID for production
$GroupId = (Get-MgGroup -Filter "DisplayName eq 'E5 Users'").Id
$Members = Get-MgGroupMember -GroupId $GroupId -All
$E5SkuId = (Get-MgSubscribedSku -All | Where-Object {$_.SkuPartNumber -eq "SPE_E5"}).SkuId

foreach ($Member in $Members) {
    $User = Get-MgUser -UserId $Member.Id
    
    # Check if already licensed
    $CurrentLicenses = Get-MgUserLicenseDetail -UserId $User.Id
    if ($CurrentLicenses.SkuId -notcontains $E5SkuId) {
        Set-MgUserLicense -UserId $User.Id -AddLicenses @{SkuId = $E5SkuId} -RemoveLicenses @()
        Write-Host "Assigned to $($User.UserPrincipalName)"
    }
}
```

## Reporting

### License Usage Report
```powershell
Get-MgSubscribedSku | ForEach-Object {
    [PSCustomObject]@{
        License = $_.SkuPartNumber
        Total = $_.PrepaidUnits.Enabled
        Assigned = $_.ConsumedUnits
        Available = $_.PrepaidUnits.Enabled - $_.ConsumedUnits
        PercentUsed = [math]::Round(($_.ConsumedUnits / $_.PrepaidUnits.Enabled * 100), 2)
    }
} | Format-Table -AutoSize
```

### Export All Licensed Users
```powershell
$AllUsers = Get-MgUser -All -Property DisplayName,UserPrincipalName,AssignedLicenses

$LicenseReport = foreach ($User in $AllUsers | Where-Object {$_.AssignedLicenses.Count -gt 0}) {
    $Licenses = Get-MgUserLicenseDetail -UserId $User.Id
    
    foreach ($License in $Licenses) {
        [PSCustomObject]@{
            DisplayName = $User.DisplayName
            Email = $User.UserPrincipalName
            License = $License.SkuPartNumber
        }
    }
}

$LicenseReport | Export-Csv "licensed-users.csv" -NoTypeInformation
```

### Users Without Licenses
```powershell
Get-MgUser -All -Property DisplayName,UserPrincipalName,AssignedLicenses,Department |
    Where-Object {$_.AssignedLicenses.Count -eq 0} |
    Select-Object DisplayName,UserPrincipalName,Department |
    Export-Csv "unlicensed-users.csv" -NoTypeInformation
```

### License Cost Analysis
```powershell
# Define license costs (update with actual costs)
$LicenseCosts = @{
    "SPE_E5" = 57.00
    "POWER_BI_PRO" = 9.99
    "EMSPREMIUM" = 14.80
}

$TotalCost = 0
Get-MgSubscribedSku | ForEach-Object {
    if ($LicenseCosts.ContainsKey($_.SkuPartNumber)) {
        $Cost = $_.ConsumedUnits * $LicenseCosts[$_.SkuPartNumber]
        $TotalCost += $Cost
        
        [PSCustomObject]@{
            License = $_.SkuPartNumber
            AssignedCount = $_.ConsumedUnits
            CostPerLicense = $LicenseCosts[$_.SkuPartNumber]
            TotalCost = $Cost
        }
    }
} | Format-Table -AutoSize

Write-Host "`nTotal Monthly Cost: `$$TotalCost" -ForegroundColor Cyan
```

## Power Automate Specific

### Assign Power Automate License
```powershell
# Power Automate per user plan
$FlowSkuId = (Get-MgSubscribedSku -All | Where-Object {$_.SkuPartNumber -eq "FLOW_PER_USER"}).SkuId

Set-MgUserLicense -UserId "automation-engineer@company.com" `
    -AddLicenses @{SkuId = $FlowSkuId} `
    -RemoveLicenses @()
```

### List Power Automate Licensed Users
```powershell
Get-MgUser -All -Property DisplayName,UserPrincipalName,AssignedLicenses |
    Where-Object {
        $UserId = $_.Id
        $Licenses = Get-MgUserLicenseDetail -UserId $UserId
        $Licenses.SkuPartNumber -like "*FLOW*"
    } |
    Select-Object DisplayName,UserPrincipalName
```

## Copilot License Management

### Assign Microsoft 365 Copilot
```powershell
# Microsoft 365 Copilot
$CopilotSkuId = (Get-MgSubscribedSku -All | Where-Object {$_.SkuPartNumber -eq "Microsoft_365_Copilot"}).SkuId

Set-MgUserLicense -UserId "automation-engineer@company.com" `
    -AddLicenses @{SkuId = $CopilotSkuId} `
    -RemoveLicenses @()
```

### Copilot ROI Tracking
```powershell
# Track Copilot adoption
$CopilotUsers = Import-Csv "copilot-users.csv"

foreach ($User in $CopilotUsers) {
    [PSCustomObject]@{
        User = $User.Email
        Role = $User.Role
        AssignedDate = $User.AssignedDate
        MonthlyCost = 30.00
        ProjectedSavingsHours = $User.ExpectedSavings
        ROI = ($User.ExpectedSavings * 50) - 30  # Assuming $50/hour value
    }
} | Export-Csv "copilot-roi.csv" -NoTypeInformation
```

## Automation Scripts

### Daily License Check
```powershell
$Threshold = 10  # Alert when fewer than 10 licenses available

$LowLicenses = Get-MgSubscribedSku | Where-Object {
    ($_.PrepaidUnits.Enabled - $_.ConsumedUnits) -lt $Threshold
}

if ($LowLicenses) {
    $Body = "Low license alert:`n`n"
    foreach ($License in $LowLicenses) {
        $Available = $License.PrepaidUnits.Enabled - $License.ConsumedUnits
        $Body += "$($License.SkuPartNumber): $Available remaining`n"
    }
    
    # Send email alert (configure SMTP)
    Send-MailMessage -To "admin@company.com" -Subject "License Alert" -Body $Body
}
```
