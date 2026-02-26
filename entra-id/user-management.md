# Entra ID User Management Commands

## Authentication
```powershell
# Connect using service principal
$TenantId = "your-tenant-id"
$ClientId = "your-client-id"
$ClientSecret = "your-client-secret"

$SecureSecret = ConvertTo-SecureString $ClientSecret -AsPlainText -Force
$Credential = New-Object System.Management.Automation.PSCredential($ClientId, $SecureSecret)

Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $Credential
```

## User Operations

### Create User
```powershell
$PasswordProfile = @{
    Password = "TempPass123!"
    ForceChangePasswordNextSignIn = $true
}

$UserParams = @{
    AccountEnabled = $true
    DisplayName = "John Doe"
    MailNickname = "jdoe"
    UserPrincipalName = "jdoe@company.com"
    PasswordProfile = $PasswordProfile
    Department = "Engineering"
    JobTitle = "Software Engineer"
    UsageLocation = "US"
}

New-MgUser @UserParams
```

### Get User
```powershell
# Single user
Get-MgUser -UserId "jdoe@company.com"

# All users
Get-MgUser -All

# Filter users
Get-MgUser -Filter "Department eq 'Engineering'"

# Get user with manager
Get-MgUser -UserId "jdoe@company.com" -ExpandProperty Manager
```

### Update User
```powershell
Update-MgUser -UserId "jdoe@company.com" -Department "IT" -JobTitle "Senior Engineer"

# Update manager
$ManagerId = (Get-MgUser -Filter "UserPrincipalName eq 'manager@company.com'").Id
Set-MgUserManagerByRef -UserId "jdoe@company.com" -OdataId "https://graph.microsoft.com/v1.0/users/$ManagerId"
```

### Disable User
```powershell
Update-MgUser -UserId "jdoe@company.com" -AccountEnabled:$false
```

### Delete User
```powershell
Remove-MgUser -UserId "jdoe@company.com"
```

## Group Operations

### Create Group
```powershell
$GroupParams = @{
    DisplayName = "MacBook Users"
    MailEnabled = $false
    MailNickname = "macbook-users"
    SecurityEnabled = $true
    Description = "All MacBook users"
}

New-MgGroup @GroupParams
```

### Add User to Group
```powershell
$UserId = (Get-MgUser -Filter "UserPrincipalName eq 'jdoe@company.com'").Id
$GroupId = (Get-MgGroup -Filter "DisplayName eq 'MacBook Users'").Id

New-MgGroupMember -GroupId $GroupId -DirectoryObjectId $UserId
```

### Remove User from Group
```powershell
Remove-MgGroupMemberByRef -GroupId $GroupId -DirectoryObjectId $UserId
```

### List Group Members
```powershell
Get-MgGroupMember -GroupId $GroupId -All
```

## Bulk Operations

### Import Users from CSV
```powershell
$Users = Import-Csv "users.csv"

foreach ($User in $Users) {
    $PasswordProfile = @{
        Password = "TempPass123!"
        ForceChangePasswordNextSignIn = $true
    }
    
    $UserParams = @{
        AccountEnabled = $true
        DisplayName = $User.DisplayName
        MailNickname = $User.MailNickname
        UserPrincipalName = $User.UPN
        PasswordProfile = $PasswordProfile
        Department = $User.Department
        JobTitle = $User.JobTitle
        UsageLocation = "US"
    }
    
    try {
        New-MgUser @UserParams
        Write-Host "Created: $($User.UPN)" -ForegroundColor Green
    }
    catch {
        Write-Host "Failed: $($User.UPN) - $_" -ForegroundColor Red
    }
}
```

### Export All Users
```powershell
Get-MgUser -All -Property DisplayName,UserPrincipalName,Department,JobTitle,AccountEnabled |
    Select-Object DisplayName,UserPrincipalName,Department,JobTitle,AccountEnabled |
    Export-Csv "all-users.csv" -NoTypeInformation
```

## Device Management

### Get User's Registered Devices
```powershell
Get-MgUserRegisteredDevice -UserId "jdoe@company.com"
```

### Get User's Owned Devices
```powershell
Get-MgUserOwnedDevice -UserId "jdoe@company.com"
```

## Authentication Methods

### Get User's Authentication Methods
```powershell
Get-MgUserAuthenticationMethod -UserId "jdoe@company.com"
```

### Reset User Password
```powershell
$NewPassword = "NewTempPass456!"
Update-MgUser -UserId "jdoe@company.com" -PasswordProfile @{
    Password = $NewPassword
    ForceChangePasswordNextSignIn = $true
}
```

### Auto-Generate Password, Reset & Force Change on Next Login
```powershell
# Cross-platform password generator (works on macOS/Linux/Windows)
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
$AutoPassword = -join ($PasswordChars | Get-Random -Count $PasswordChars.Count)

Update-MgUser -UserId "jdoe@company.com" -PasswordProfile @{
    Password = $AutoPassword
    ForceChangePasswordNextSignIn = $true
}

Write-Host "Password reset for jdoe@company.com" -ForegroundColor Green
Write-Host "Temporary password: $AutoPassword"
```

## License Management

### List Available Licenses (Subscribed SKUs)
```powershell
Get-MgSubscribedSku -All | Select-Object SkuPartNumber, SkuId, ConsumedUnits,
    @{Name="TotalUnits"; Expression={$_.PrepaidUnits.Enabled}}
```

### Assign Microsoft 365 E5 License
```powershell
$UserId = (Get-MgUser -Filter "UserPrincipalName eq 'jdoe@company.com'").Id
$E5SkuId = (Get-MgSubscribedSku -All | Where-Object { $_.SkuPartNumber -eq "SPE_E5" }).SkuId

Set-MgUserLicense -UserId $UserId -AddLicenses @(@{ SkuId = $E5SkuId }) -RemoveLicenses @()
Write-Host "E5 license assigned to jdoe@company.com" -ForegroundColor Green
```

### Assign E5 License with Specific Service Plans Disabled
```powershell
$UserId = (Get-MgUser -Filter "UserPrincipalName eq 'jdoe@company.com'").Id
$E5Sku = Get-MgSubscribedSku -All | Where-Object { $_.SkuPartNumber -eq "SPE_E5" }

# Disable specific plans (e.g., Yammer, Sway)
$DisabledPlans = $E5Sku.ServicePlans |
    Where-Object { $_.ServicePlanName -in @("YAMMER_ENTERPRISE", "SWAY") } |
    Select-Object -ExpandProperty ServicePlanId

Set-MgUserLicense -UserId $UserId -AddLicenses @(@{
    SkuId = $E5Sku.SkuId
    DisabledPlans = $DisabledPlans
}) -RemoveLicenses @()
```

### Get User's Assigned Licenses
```powershell
Get-MgUserLicenseDetail -UserId "jdoe@company.com" |
    Select-Object SkuPartNumber, SkuId
```

### Remove License
```powershell
$UserId = (Get-MgUser -Filter "UserPrincipalName eq 'jdoe@company.com'").Id
$E5SkuId = (Get-MgSubscribedSku -All | Where-Object { $_.SkuPartNumber -eq "SPE_E5" }).SkuId

Set-MgUserLicense -UserId $UserId -AddLicenses @() -RemoveLicenses @($E5SkuId)
```

## Combined: Assign E5 License + Set Location + Reset Password + Force Change

See `provisioning/assign-e5-reset-password.ps1` for the full script. It handles:
1. Setting usage location to Spain (ES)
2. Assigning Microsoft 365 E5 license (with availability checks)
3. Assigning Power Automate Free license
4. Generating a cross-platform secure password
5. Resetting password and forcing change on next login

### Required Scopes & Roles
```powershell
# Requires Privileged Authentication Administrator or Global Administrator role
Connect-MgGraph -Scopes "User.ReadWrite.All", "Directory.ReadWrite.All", "Organization.Read.All", "UserAuthenticationMethod.ReadWrite.All"
```

### Usage
```powershell
./provisioning/assign-e5-reset-password.ps1 -UserPrincipalName "jdoe@company.com"
```

## Admin Role Management

### Check Current User's Admin Roles
```powershell
$me = Get-MgContext
$userId = (Get-MgUser -UserId $me.Account).Id
Get-MgUserMemberOf -UserId $userId | ForEach-Object { Get-MgDirectoryRole -DirectoryRoleId $_.Id -ErrorAction SilentlyContinue } | Select-Object DisplayName
```

## SharePoint & Teams Integration

### Get SharePoint Site for a Specific Team
```powershell
Connect-MgGraph -Scopes "Group.Read.All", "Sites.Read.All"

$GroupId = (Get-MgGroup -Filter "displayName eq 'Your Team Name'" -Property Id,ResourceProvisioningOptions |
    Where-Object { $_.ResourceProvisioningOptions -contains "Team" }).Id
Get-MgGroupSite -GroupId $GroupId -SiteId "root" | Select-Object DisplayName, WebUrl
```

### List All Teams with Their SharePoint Sites
```powershell
Get-MgGroup -Filter "resourceProvisioningOptions/any(x:x eq 'Team')" -All | ForEach-Object {
    $Site = Get-MgGroupSite -GroupId $_.Id -SiteId "root" -ErrorAction SilentlyContinue
    [PSCustomObject]@{
        TeamName      = $_.DisplayName
        GroupId       = $_.Id
        SharePointUrl = $Site.WebUrl
    }
} | Format-Table -AutoSize
```

### Get Team Document Library (Files Tab) URL
```powershell
$GroupId = (Get-MgGroup -Filter "displayName eq 'Your Team Name'").Id
$Drive = Get-MgGroupDrive -GroupId $GroupId | Select-Object -First 1
Write-Host "Files URL: $($Drive.WebUrl)"
```

### Search for a Team by Name
```powershell
Get-MgGroup -Search '"displayName:team_name"' -ConsistencyLevel eventual -Property Id,DisplayName,ResourceProvisioningOptions | Select-Object DisplayName, Id
```

## Reporting

### Users Created Last 30 Days
```powershell
$Date = (Get-Date).AddDays(-30).ToString("yyyy-MM-ddTHH:mm:ssZ")
Get-MgUser -Filter "createdDateTime ge $Date" -All
```

### Disabled Users
```powershell
Get-MgUser -Filter "accountEnabled eq false" -All
```

### Users Without Manager
```powershell
Get-MgUser -All | Where-Object {
    $_.Id | Get-MgUserManager -ErrorAction SilentlyContinue | Out-Null
    !$?
}
```
