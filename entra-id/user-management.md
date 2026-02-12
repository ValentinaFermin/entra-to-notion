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
