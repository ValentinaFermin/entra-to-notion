# User Provisioning Workflows

## Complete Onboarding Workflow

### Full User Provisioning Script
```powershell
# provision-new-employee.ps1

<#
.SYNOPSIS
    Complete user provisioning for new MacBook users
.DESCRIPTION
    Creates Entra ID user, assigns licenses, creates mailbox, stores password in Bitwarden
.PARAMETER UserEmail
    User's email address
.PARAMETER DisplayName
    User's full name
.PARAMETER Department
    User's department
.PARAMETER JobTitle
    User's job title
.PARAMETER Manager
    Manager's email address
.PARAMETER StartDate
    Employee start date
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$UserEmail,
    
    [Parameter(Mandatory=$true)]
    [string]$DisplayName,
    
    [Parameter(Mandatory=$true)]
    [string]$Department,
    
    [Parameter(Mandatory=$true)]
    [string]$JobTitle,
    
    [Parameter(Mandatory=$false)]
    [string]$Manager,
    
    [Parameter(Mandatory=$false)]
    [datetime]$StartDate = (Get-Date)
)

# Configuration
$BitwardenOrgId = "your-bitwarden-org-id"
$DefaultGroups = @("All Employees", "MacBook Users")
$LicenseSku = "SPE_E5"

Write-Host "`n=== Starting User Provisioning ===" -ForegroundColor Cyan
Write-Host "User: $DisplayName ($UserEmail)"
Write-Host "Department: $Department"
Write-Host "Start Date: $($StartDate.ToString('yyyy-MM-dd'))"
Write-Host "`n"

try {
    # 1. Generate Secure Password
    Write-Host "[1/9] Generating secure password..." -ForegroundColor Yellow
    Add-Type -AssemblyName System.Web
    $TempPassword = [System.Web.Security.Membership]::GeneratePassword(16, 4)
    Write-Host "✓ Password generated" -ForegroundColor Green

    # 2. Create Entra ID User
    Write-Host "[2/9] Creating Entra ID user..." -ForegroundColor Yellow
    Connect-MgGraph -Scopes "User.ReadWrite.All", "Group.ReadWrite.All"
    
    $PasswordProfile = @{
        Password = $TempPassword
        ForceChangePasswordNextSignIn = $true
    }
    
    $UserParams = @{
        AccountEnabled = $true
        DisplayName = $DisplayName
        MailNickname = $UserEmail.Split('@')[0]
        UserPrincipalName = $UserEmail
        PasswordProfile = $PasswordProfile
        Department = $Department
        JobTitle = $JobTitle
        UsageLocation = "US"
        EmployeeHireDate = $StartDate
    }
    
    $NewUser = New-MgUser @UserParams
    Write-Host "✓ User created - ID: $($NewUser.Id)" -ForegroundColor Green
    Start-Sleep -Seconds 5

    # 3. Set Manager
    if ($Manager) {
        Write-Host "[3/9] Setting manager..." -ForegroundColor Yellow
        $ManagerId = (Get-MgUser -Filter "UserPrincipalName eq '$Manager'").Id
        Set-MgUserManagerByRef -UserId $NewUser.Id -OdataId "https://graph.microsoft.com/v1.0/users/$ManagerId"
        Write-Host "✓ Manager set: $Manager" -ForegroundColor Green
    } else {
        Write-Host "[3/9] No manager specified, skipping..." -ForegroundColor Gray
    }

    # 4. Add to Groups
    Write-Host "[4/9] Adding to groups..." -ForegroundColor Yellow
    foreach ($GroupName in $DefaultGroups) {
        $Group = Get-MgGroup -Filter "DisplayName eq '$GroupName'"
        if ($Group) {
            New-MgGroupMember -GroupId $Group.Id -DirectoryObjectId $NewUser.Id
            Write-Host "✓ Added to: $GroupName" -ForegroundColor Green
        }
    }

    # 5. Assign License
    Write-Host "[5/9] Assigning license..." -ForegroundColor Yellow
    Start-Sleep -Seconds 10  # Wait for replication
    $SkuId = (Get-MgSubscribedSku -All | Where-Object {$_.SkuPartNumber -eq $LicenseSku}).SkuId
    Set-MgUserLicense -UserId $NewUser.Id -AddLicenses @{SkuId = $SkuId} -RemoveLicenses @()
    Write-Host "✓ License assigned: $LicenseSku" -ForegroundColor Green

    # 6. Wait for Mailbox Creation
    Write-Host "[6/9] Waiting for mailbox creation..." -ForegroundColor Yellow
    Connect-ExchangeOnline -ShowBanner:$false
    
    $MaxAttempts = 10
    $Attempt = 0
    $MailboxCreated = $false
    
    while ($Attempt -lt $MaxAttempts -and -not $MailboxCreated) {
        Start-Sleep -Seconds 30
        $Attempt++
        
        try {
            $Mailbox = Get-Mailbox -Identity $UserEmail -ErrorAction Stop
            $MailboxCreated = $true
            Write-Host "✓ Mailbox created" -ForegroundColor Green
        }
        catch {
            Write-Host "  Attempt $Attempt/$MaxAttempts - Still waiting..." -ForegroundColor Gray
        }
    }
    
    if (-not $MailboxCreated) {
        Write-Host "⚠ Mailbox not ready after $MaxAttempts attempts" -ForegroundColor Yellow
    }

    # 7. Configure Mailbox Settings
    if ($MailboxCreated) {
        Write-Host "[7/9] Configuring mailbox..." -ForegroundColor Yellow
        Set-Mailbox -Identity $UserEmail -RetentionPolicy "Default MRM Policy"
        Write-Host "✓ Mailbox configured" -ForegroundColor Green

        # 8. Set default calendar permissions to LimitedDetails
        Write-Host "[8/9] Setting calendar default permissions..." -ForegroundColor Yellow
        try {
            Set-MailboxFolderPermission -Identity "${UserEmail}:\Calendar" -User Default -AccessRights LimitedDetails -ErrorAction Stop
            Write-Host "✓ Calendar default permission set to LimitedDetails" -ForegroundColor Green
        } catch {
            Write-Host "⚠ Could not set calendar permissions — set manually later" -ForegroundColor Yellow
        }
    } else {
        Write-Host "[7/9] Skipping mailbox configuration" -ForegroundColor Gray
        Write-Host "[8/9] Skipping calendar permissions (no mailbox)" -ForegroundColor Gray
    }

    # 9. Store Password in Bitwarden
    Write-Host "[9/9] Storing password in Bitwarden..." -ForegroundColor Yellow
    $env:BW_SESSION = bw unlock --raw
    
    $ItemJson = @{
        organizationId = $BitwardenOrgId
        type = 2
        secureNote = @{
            type = 0
        }
        name = "$DisplayName - Initial Password"
        notes = @"
Username: $UserEmail
Password: $TempPassword
Department: $Department
Job Title: $JobTitle
Manager: $Manager
Start Date: $($StartDate.ToString('yyyy-MM-dd'))
Created: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

IMPORTANT: User must change password on first login
"@
    } | ConvertTo-Json -Compress
    
    $BitwardenItem = bw create item $ItemJson | ConvertFrom-Json
    bw sync
    Write-Host "✓ Password stored - Item ID: $($BitwardenItem.id)" -ForegroundColor Green

    # Summary
    Write-Host "`n=== Provisioning Complete ===" -ForegroundColor Green
    Write-Host "User: $DisplayName"
    Write-Host "Email: $UserEmail"
    Write-Host "Entra ID: $($NewUser.Id)"
    Write-Host "License: $LicenseSku"
    Write-Host "Bitwarden: $($BitwardenItem.id)"
    Write-Host "`nNext Steps:"
    Write-Host "1. Share Bitwarden password with manager/IT"
    Write-Host "2. Verify user can login to portal.office.com"
    Write-Host "3. Schedule MacBook assignment via JAMF"

    # Create summary object
    $Summary = [PSCustomObject]@{
        DisplayName = $DisplayName
        Email = $UserEmail
        EntraId = $NewUser.Id
        Department = $Department
        JobTitle = $JobTitle
        Manager = $Manager
        License = $LicenseSku
        BitwardenItemId = $BitwardenItem.id
        CreatedDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Status = "Success"
    }
    
    return $Summary
}
catch {
    Write-Host "`n❌ ERROR: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    
    $Summary = [PSCustomObject]@{
        DisplayName = $DisplayName
        Email = $UserEmail
        Status = "Failed"
        Error = $_.Exception.Message
    }
    
    return $Summary
}
finally {
    Disconnect-MgGraph -ErrorAction SilentlyContinue
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
}
```

## Bulk Provisioning from CSV

### Bulk User Import Script
```powershell
# bulk-provision-users.ps1

param(
    [Parameter(Mandatory=$true)]
    [string]$CsvPath
)

$Users = Import-Csv $CsvPath
$Results = @()

Write-Host "Starting bulk provisioning for $($Users.Count) users`n" -ForegroundColor Cyan

foreach ($User in $Users) {
    Write-Host "`n--- Processing: $($User.DisplayName) ---" -ForegroundColor Cyan
    
    $Result = .\provision-new-employee.ps1 `
        -UserEmail $User.Email `
        -DisplayName $User.DisplayName `
        -Department $User.Department `
        -JobTitle $User.JobTitle `
        -Manager $User.Manager `
        -StartDate $User.StartDate
    
    $Results += $Result
    
    # Rate limiting
    Start-Sleep -Seconds 5
}

# Export results
$Results | Export-Csv "provisioning-results-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv" -NoTypeInformation

Write-Host "`n=== Bulk Provisioning Complete ===" -ForegroundColor Green
Write-Host "Success: $(($Results | Where-Object {$_.Status -eq 'Success'}).Count)"
Write-Host "Failed: $(($Results | Where-Object {$_.Status -eq 'Failed'}).Count)"
```

### CSV Template
```csv
DisplayName,Email,Department,JobTitle,Manager,StartDate
John Doe,jdoe@company.com,Engineering,Software Engineer,manager@company.com,2026-03-01
Jane Smith,jsmith@company.com,Marketing,Marketing Manager,,2026-03-01
```

## Offboarding Workflow

### Complete User Offboarding Script
```powershell
# offboard-employee.ps1

param(
    [Parameter(Mandatory=$true)]
    [string]$UserEmail,
    
    [Parameter(Mandatory=$false)]
    [datetime]$TermDate = (Get-Date),
    
    [Parameter(Mandatory=$false)]
    [string]$ForwardEmailTo,
    
    [Parameter(Mandatory=$false)]
    [int]$RetentionDays = 90
)

Write-Host "`n=== Starting User Offboarding ===" -ForegroundColor Cyan
Write-Host "User: $UserEmail"
Write-Host "Termination Date: $($TermDate.ToString('yyyy-MM-dd'))"
Write-Host "`n"

try {
    Connect-MgGraph -Scopes "User.ReadWrite.All"
    Connect-ExchangeOnline -ShowBanner:$false

    # 1. Disable User Account
    Write-Host "[1/6] Disabling user account..." -ForegroundColor Yellow
    Update-MgUser -UserId $UserEmail -AccountEnabled:$false
    Write-Host "✓ Account disabled" -ForegroundColor Green

    # 2. Remove from Groups (except retention groups)
    Write-Host "[2/6] Removing from groups..." -ForegroundColor Yellow
    $User = Get-MgUser -UserId $UserEmail
    $Memberships = Get-MgUserMemberOf -UserId $User.Id
    
    foreach ($Group in $Memberships) {
        $GroupDetails = Get-MgGroup -GroupId $Group.Id
        if ($GroupDetails.DisplayName -notlike "*Retention*") {
            Remove-MgGroupMemberByRef -GroupId $Group.Id -DirectoryObjectId $User.Id
            Write-Host "✓ Removed from: $($GroupDetails.DisplayName)" -ForegroundColor Green
        }
    }

    # 3. Convert Mailbox to Shared
    Write-Host "[3/6] Converting mailbox to shared..." -ForegroundColor Yellow
    Set-Mailbox -Identity $UserEmail -Type Shared
    Write-Host "✓ Mailbox converted to shared" -ForegroundColor Green

    # 4. Set Email Forwarding
    if ($ForwardEmailTo) {
        Write-Host "[4/6] Setting email forwarding..." -ForegroundColor Yellow
        Set-Mailbox -Identity $UserEmail -ForwardingAddress $ForwardEmailTo -DeliverToMailboxAndForward $true
        Write-Host "✓ Email forwarding to: $ForwardEmailTo" -ForegroundColor Green
    } else {
        Write-Host "[4/6] No email forwarding specified" -ForegroundColor Gray
    }

    # 5. Set Out of Office
    Write-Host "[5/6] Setting out of office..." -ForegroundColor Yellow
    $OOOMessage = "This employee is no longer with the company. For assistance, please contact support@company.com"
    Set-MailboxAutoReplyConfiguration -Identity $UserEmail `
        -AutoReplyState Enabled `
        -InternalMessage $OOOMessage `
        -ExternalMessage $OOOMessage
    Write-Host "✓ Out of office configured" -ForegroundColor Green

    # 6. Remove Licenses (after retention period)
    Write-Host "[6/6] Scheduling license removal..." -ForegroundColor Yellow
    $RemovalDate = $TermDate.AddDays($RetentionDays)
    Write-Host "⚠ Licenses will be removed on: $($RemovalDate.ToString('yyyy-MM-dd'))" -ForegroundColor Yellow
    Write-Host "  Run license removal manually after retention period" -ForegroundColor Gray

    Write-Host "`n=== Offboarding Complete ===" -ForegroundColor Green
    Write-Host "Next Steps:"
    Write-Host "1. Revoke JAMF device enrollment"
    Write-Host "2. Delete Bitwarden password entry"
    Write-Host "3. Remove from third-party apps (GitHub, Notion, etc.)"
    Write-Host "4. Schedule mailbox deletion after $RetentionDays days"
    Write-Host "5. Remove licenses on: $($RemovalDate.ToString('yyyy-MM-dd'))"
}
catch {
    Write-Host "`n❌ ERROR: $_" -ForegroundColor Red
}
finally {
    Disconnect-MgGraph -ErrorAction SilentlyContinue
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
}
```

## Role-Based Provisioning

### Engineering Team Provisioning
```powershell
# provision-engineer.ps1

# Extends base provisioning with engineering-specific setup
.\provision-new-employee.ps1 @PSBoundParameters

# Additional steps for engineers
$UserEmail = $PSBoundParameters.UserEmail

# Add to engineering groups
$EngineeringGroups = @(
    "GitHub-Developers",
    "GitLab-Engineers",
    "VPN-Access",
    "Development-Tools"
)

Connect-MgGraph -Scopes "Group.ReadWrite.All"
foreach ($GroupName in $EngineeringGroups) {
    $Group = Get-MgGroup -Filter "DisplayName eq '$GroupName'"
    if ($Group) {
        $UserId = (Get-MgUser -Filter "UserPrincipalName eq '$UserEmail'").Id
        New-MgGroupMember -GroupId $Group.Id -DirectoryObjectId $UserId
        Write-Host "Added to: $GroupName" -ForegroundColor Green
    }
}

# Assign Power Automate license
$FlowSkuId = (Get-MgSubscribedSku -All | Where-Object {$_.SkuPartNumber -like "*FLOW*"}).SkuId
if ($FlowSkuId) {
    Set-MgUserLicense -UserId $UserId -AddLicenses @{SkuId = $FlowSkuId} -RemoveLicenses @()
    Write-Host "✓ Power Automate license assigned" -ForegroundColor Green
}
```
