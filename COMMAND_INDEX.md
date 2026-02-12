# Command Index - Quick Reference

## Entra ID Operations

### User Management
```powershell
# Create user
New-MgUser -AccountEnabled $true -DisplayName "Name" -UserPrincipalName "user@company.com"

# Get user
Get-MgUser -UserId "user@company.com"

# Update user
Update-MgUser -UserId "user@company.com" -Department "IT"

# Disable user
Update-MgUser -UserId "user@company.com" -AccountEnabled:$false

# Delete user
Remove-MgUser -UserId "user@company.com"
```

### Group Management
```powershell
# Create group
New-MgGroup -DisplayName "Group Name" -MailEnabled $false -SecurityEnabled $true

# Add member
New-MgGroupMember -GroupId $GroupId -DirectoryObjectId $UserId

# Remove member
Remove-MgGroupMemberByRef -GroupId $GroupId -DirectoryObjectId $UserId
```

## Exchange Online

### Mailbox Operations
```powershell
# Get mailbox
Get-Mailbox -Identity "user@company.com"

# Create shared mailbox
New-Mailbox -Name "Support" -Shared -PrimarySmtpAddress "support@company.com"

# Grant permissions
Add-MailboxPermission -Identity "shared@company.com" -User "user@company.com" -AccessRights FullAccess
Add-RecipientPermission -Identity "shared@company.com" -Trustee "user@company.com" -AccessRights SendAs

# Convert to shared
Set-Mailbox -Identity "user@company.com" -Type Shared
```

## Licensing

### License Assignment
```powershell
# Get SKU
$SkuId = (Get-MgSubscribedSku -All | Where-Object {$_.SkuPartNumber -eq "SPE_E5"}).SkuId

# Assign license
Set-MgUserLicense -UserId "user@company.com" -AddLicenses @{SkuId = $SkuId} -RemoveLicenses @()

# Remove license
Set-MgUserLicense -UserId "user@company.com" -AddLicenses @() -RemoveLicenses @($SkuId)

# View user licenses
Get-MgUserLicenseDetail -UserId "user@company.com"
```

## Bitwarden

### Password Management
```bash
# Login
bw login
export BW_SESSION=$(bw unlock --raw)

# Create password item
bw create item '{"organizationId":"org-id","type":2,"name":"User Password","notes":"Password info"}'

# Search items
bw list items --search "User Name"

# Get password
bw get password "item-id"

# Sync
bw sync
```

## JAMF Pro

### Device Management
```bash
# Get computer
curl -H "Authorization: Bearer $TOKEN" "$JAMF_URL/JSSResource/computers/id/123"

# Assign to user
curl -H "Authorization: Bearer $TOKEN" "$JAMF_URL/JSSResource/computers/id/123" -X PUT \
  -d '<computer><location><username>user@company.com</username></location></computer>'

# Update inventory
curl -H "Authorization: Bearer $TOKEN" "$JAMF_URL/JSSResource/computercommands/command/UpdateInventory/id/123" -X POST
```

## Complete Workflows

### New User Provisioning
```powershell
.\provisioning\provision-new-employee.ps1 `
    -UserEmail "jdoe@company.com" `
    -DisplayName "John Doe" `
    -Department "Engineering" `
    -JobTitle "Software Engineer" `
    -Manager "manager@company.com"
```

### User Offboarding
```powershell
.\provisioning\offboard-employee.ps1 `
    -UserEmail "jdoe@company.com" `
    -ForwardEmailTo "manager@company.com" `
    -RetentionDays 90
```

### Bulk Provisioning
```powershell
.\provisioning\bulk-provision-users.ps1 -CsvPath "users.csv"
```

## Monitoring

### Daily Health Check
```powershell
.\monitoring\daily-health-check.ps1
```

### Weekly Report
```powershell
.\monitoring\weekly-user-report.ps1 -DaysBack 7
```

### Monthly Cost Report
```powershell
.\monitoring\monthly-cost-report.ps1
```

### Live Monitoring
```powershell
.\monitoring\monitor-live.ps1
```

## Utilities

### Authentication
```powershell
# Connect to all services
$Config = Connect-AutomationServices -ConfigPath "config.json"

# Disconnect
Disconnect-AutomationServices
```

### Setup Service Principal
```powershell
.\utilities\setup-service-principal.ps1
```

### Backup State
```powershell
Backup-TenantState
```

## Common Tasks

### Reset User Password
```powershell
Update-MgUser -UserId "user@company.com" -PasswordProfile @{
    Password = "NewPassword123!"
    ForceChangePasswordNextSignIn = $true
}
```

### Enable MFA for User
```powershell
# MFA enforcement is done through Conditional Access policies or Security Defaults
```

### Export All Users
```powershell
Get-MgUser -All -Property DisplayName,UserPrincipalName,Department,JobTitle,AccountEnabled |
    Export-Csv "all-users.csv" -NoTypeInformation
```

### Check License Usage
```powershell
Get-MgSubscribedSku | Select-Object SkuPartNumber,ConsumedUnits,
    @{N="Available";E={$_.PrepaidUnits.Enabled - $_.ConsumedUnits}} | Format-Table
```

### Message Trace
```powershell
Get-MessageTrace -SenderAddress "user@company.com" `
    -StartDate (Get-Date).AddDays(-7) `
    -EndDate (Get-Date)
```

### Get Mailbox Sizes
```powershell
Get-Mailbox -ResultSize Unlimited | Get-MailboxStatistics |
    Select-Object DisplayName,TotalItemSize,ItemCount |
    Export-Csv "mailbox-sizes.csv" -NoTypeInformation
```

## Troubleshooting

### Connection Issues
```powershell
# Test Graph connection
Get-MgContext

# Test Exchange connection
Get-ConnectionInformation

# Reconnect
Connect-MgGraph -Scopes "User.ReadWrite.All"
Connect-ExchangeOnline
```

### Permission Issues
```powershell
# Check current permissions
Get-MgContext | Select-Object -ExpandProperty Scopes

# Required scopes:
# User.ReadWrite.All, Group.ReadWrite.All, Directory.ReadWrite.All
```

### Rate Limiting
```powershell
# Implement delays between bulk operations
Start-Sleep -Seconds 2
```

## Emergency Procedures

### Disable Compromised Account
```powershell
Update-MgUser -UserId "compromised@company.com" -AccountEnabled:$false
# Revoke all sessions
Revoke-MgUserSignInSession -UserId "compromised@company.com"
```

### Restore Deleted User (within 30 days)
```powershell
# List deleted users
Get-MgDirectoryDeletedItem -DirectoryObjectId Microsoft.Graph.User

# Restore
Restore-MgDirectoryDeletedItem -DirectoryObjectId $DeletedUserId
```

### Reset Admin Password
```powershell
# Use emergency access account or Azure Portal
# Cannot be done via API for security
```
