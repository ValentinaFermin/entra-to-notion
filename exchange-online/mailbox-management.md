# Exchange Online Management Commands

## Authentication
```powershell
# Connect with service principal
Connect-ExchangeOnline -CertificateThumbprint "thumbprint" -AppId "app-id" -Organization "company.onmicrosoft.com"

# Connect with credentials (for testing)
Connect-ExchangeOnline -UserPrincipalName admin@company.com
```

## Mailbox Operations

### Create Mailbox (User Mailbox)
```powershell
# User mailbox is created automatically with Entra ID user
# Verify mailbox exists
Get-Mailbox -Identity "jdoe@company.com"
```

### Create Shared Mailbox
```powershell
New-Mailbox -Name "IT Support" -Shared -PrimarySmtpAddress "support@company.com"

# Add members
Add-MailboxPermission -Identity "support@company.com" -User "jdoe@company.com" -AccessRights FullAccess -InheritanceType All
Add-RecipientPermission -Identity "support@company.com" -Trustee "jdoe@company.com" -AccessRights SendAs -Confirm:$false
```

### Create Room Mailbox
```powershell
New-Mailbox -Name "Conference Room A" -Room -PrimarySmtpAddress "room-a@company.com"

Set-CalendarProcessing -Identity "room-a@company.com" -AutomateProcessing AutoAccept
```

### Get Mailbox
```powershell
# Single mailbox
Get-Mailbox -Identity "jdoe@company.com"

# All mailboxes
Get-Mailbox -ResultSize Unlimited

# Shared mailboxes only
Get-Mailbox -RecipientTypeDetails SharedMailbox -ResultSize Unlimited

# User mailboxes only
Get-Mailbox -RecipientTypeDetails UserMailbox -ResultSize Unlimited
```

### Update Mailbox Settings
```powershell
# Set mailbox quota
Set-Mailbox -Identity "jdoe@company.com" -ProhibitSendQuota 50GB -ProhibitSendReceiveQuota 55GB -IssueWarningQuota 45GB

# Set retention policy
Set-Mailbox -Identity "jdoe@company.com" -RetentionPolicy "Default MRM Policy"

# Enable litigation hold
Set-Mailbox -Identity "jdoe@company.com" -LitigationHoldEnabled $true
```

### Convert User Mailbox to Shared
```powershell
Set-Mailbox -Identity "jdoe@company.com" -Type Shared
```

## Email Address Management

### Add Email Alias
```powershell
Set-Mailbox -Identity "jdoe@company.com" -EmailAddresses @{Add="john.doe@company.com"}
```

### Set Primary SMTP Address
```powershell
Set-Mailbox -Identity "jdoe@company.com" -PrimarySmtpAddress "john.doe@company.com" -EmailAddressPolicyEnabled $false
```

### Remove Email Alias
```powershell
Set-Mailbox -Identity "jdoe@company.com" -EmailAddresses @{Remove="old@company.com"}
```

## Permissions

### Grant Full Access
```powershell
Add-MailboxPermission -Identity "shared@company.com" -User "jdoe@company.com" -AccessRights FullAccess -InheritanceType All
```

### Grant Send As
```powershell
Add-RecipientPermission -Identity "shared@company.com" -Trustee "jdoe@company.com" -AccessRights SendAs -Confirm:$false
```

### Grant Send on Behalf
```powershell
Set-Mailbox -Identity "manager@company.com" -GrantSendOnBehalfTo @{Add="jdoe@company.com"}
```

### Remove Permissions
```powershell
Remove-MailboxPermission -Identity "shared@company.com" -User "jdoe@company.com" -AccessRights FullAccess -Confirm:$false
Remove-RecipientPermission -Identity "shared@company.com" -Trustee "jdoe@company.com" -AccessRights SendAs -Confirm:$false
```

### List Mailbox Permissions
```powershell
Get-MailboxPermission -Identity "shared@company.com" | Where-Object {$_.User -notlike "NT AUTHORITY\SELF"}
Get-RecipientPermission -Identity "shared@company.com" | Where-Object {$_.Trustee -ne "NT AUTHORITY\SELF"}
```

## Distribution Groups

### Create Distribution Group
```powershell
New-DistributionGroup -Name "Engineering Team" -PrimarySmtpAddress "engineering@company.com"
```

### Add Members
```powershell
Add-DistributionGroupMember -Identity "engineering@company.com" -Member "jdoe@company.com"
```

### Remove Members
```powershell
Remove-DistributionGroupMember -Identity "engineering@company.com" -Member "jdoe@company.com"
```

### List Group Members
```powershell
Get-DistributionGroupMember -Identity "engineering@company.com"
```

## Mail Flow

### Get Message Trace
```powershell
# Last 7 days
Get-MessageTrace -SenderAddress "jdoe@company.com" -StartDate (Get-Date).AddDays(-7) -EndDate (Get-Date)

# Specific recipient
Get-MessageTrace -RecipientAddress "recipient@external.com" -StartDate (Get-Date).AddDays(-1) -EndDate (Get-Date)

# Extended trace (up to 90 days)
Start-HistoricalSearch -ReportTitle "Monthly Report" -StartDate (Get-Date).AddDays(-30) -EndDate (Get-Date) -ReportType MessageTrace -SenderAddress "jdoe@company.com"
```

### List All Transport Rules
```powershell
Get-TransportRule

# With details
Get-TransportRule | Format-List Name, State, Priority, Description

# Only enabled rules
Get-TransportRule | Where-Object {$_.State -eq "Enabled"}

# Export to CSV
Get-TransportRule | Export-Csv "transport-rules.csv" -NoTypeInformation
```

### Create Transport Rule
```powershell
New-TransportRule -Name "Block External Forwarding" `
    -FromScope InOrganization `
    -SentToScope NotInOrganization `
    -MessageTypeMatches AutoForward `
    -RejectMessageReasonText "External forwarding is not allowed"
```

## Email Forwarding

### List All Mailboxes with Forwarding Enabled
```powershell
Get-Mailbox -ResultSize Unlimited |
    Where-Object {$_.ForwardingAddress -ne $null} |
    Select-Object DisplayName, PrimarySmtpAddress, ForwardingAddress, DeliverToMailboxAndForward
```

### Export Forwarding Report to CSV
```powershell
Get-Mailbox -ResultSize Unlimited |
    Where-Object {$_.ForwardingAddress -ne $null} |
    Select-Object DisplayName, PrimarySmtpAddress, ForwardingAddress, DeliverToMailboxAndForward |
    Export-Csv "mailboxes-with-forwarding.csv" -NoTypeInformation
```

### List Only User Mailboxes with Forwarding
```powershell
Get-Mailbox -ResultSize Unlimited -RecipientTypeDetails UserMailbox |
    Where-Object {$_.ForwardingAddress -ne $null} |
    Select-Object DisplayName, PrimarySmtpAddress, ForwardingAddress, DeliverToMailboxAndForward
```

### Set Email Forwarding on a Mailbox
```powershell
Set-Mailbox -Identity "jdoe@company.com" -ForwardingAddress "manager@company.com" -DeliverToMailboxAndForward $true
```

### Remove Email Forwarding
```powershell
Set-Mailbox -Identity "jdoe@company.com" -ForwardingAddress $null -DeliverToMailboxAndForward $false
```

## Calendar Processing

### Configure Room Auto-Accept
```powershell
Set-CalendarProcessing -Identity "room-a@company.com" `
    -AutomateProcessing AutoAccept `
    -DeleteComments $false `
    -DeleteSubject $false `
    -AddOrganizerToSubject $false
```

### Set Booking Delegates
```powershell
Set-CalendarProcessing -Identity "room-a@company.com" -ResourceDelegates @("delegate1@company.com","delegate2@company.com")
```

## Bulk Operations

### Export All Mailboxes
```powershell
Get-Mailbox -ResultSize Unlimited | 
    Select-Object DisplayName,PrimarySmtpAddress,RecipientTypeDetails,WhenCreated |
    Export-Csv "all-mailboxes.csv" -NoTypeInformation
```

### Bulk Add Shared Mailbox Permissions
```powershell
$Permissions = Import-Csv "shared-mailbox-permissions.csv"

foreach ($Perm in $Permissions) {
    Add-MailboxPermission -Identity $Perm.Mailbox -User $Perm.User -AccessRights FullAccess -InheritanceType All
    Add-RecipientPermission -Identity $Perm.Mailbox -Trustee $Perm.User -AccessRights SendAs -Confirm:$false
    Write-Host "Added $($Perm.User) to $($Perm.Mailbox)"
}
```

### Bulk Set Out of Office
```powershell
$Users = Import-Csv "ooo-users.csv"

foreach ($User in $Users) {
    Set-MailboxAutoReplyConfiguration -Identity $User.Email `
        -AutoReplyState Enabled `
        -InternalMessage $User.Message `
        -ExternalMessage $User.Message
}
```

## Monitoring

### Mailbox Size Report
```powershell
Get-Mailbox -ResultSize Unlimited | Get-MailboxStatistics |
    Select-Object DisplayName,@{N="Size(GB)";E={[math]::Round(($_.TotalItemSize.Value.ToString().Split("(")[1].Split(" ")[0].Replace(",","")/1GB),2)}},ItemCount |
    Sort-Object "Size(GB)" -Descending |
    Export-Csv "mailbox-sizes.csv" -NoTypeInformation
```

### Inactive Mailboxes (No login 90+ days)
```powershell
Get-Mailbox -ResultSize Unlimited | Get-MailboxStatistics |
    Where-Object {$_.LastLogonTime -lt (Get-Date).AddDays(-90)} |
    Select-Object DisplayName,LastLogonTime
```

### Shared Mailbox Access Report
```powershell
Get-Mailbox -RecipientTypeDetails SharedMailbox -ResultSize Unlimited | ForEach-Object {
    $Mailbox = $_
    Get-MailboxPermission -Identity $Mailbox.Identity |
        Where-Object {$_.User -notlike "NT AUTHORITY\SELF"} |
        Select-Object @{N="Mailbox";E={$Mailbox.PrimarySmtpAddress}},User,AccessRights
} | Export-Csv "shared-mailbox-access.csv" -NoTypeInformation
```

## Cleanup

### Disconnect
```powershell
Disconnect-ExchangeOnline -Confirm:$false
```
