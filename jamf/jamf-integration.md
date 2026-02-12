# JAMF Pro Integration

## API Authentication

### Generate API Token
```bash
# Get bearer token
JAMF_URL="https://your-instance.jamfcloud.com"
USERNAME="api-user"
PASSWORD="api-password"

TOKEN=$(curl -s -u "$USERNAME:$PASSWORD" "$JAMF_URL/api/v1/auth/token" -X POST | jq -r '.token')
echo "Token: $TOKEN"
```

### PowerShell Authentication
```powershell
$JamfUrl = "https://your-instance.jamfcloud.com"
$Credential = Get-Credential

$Headers = @{
    "Authorization" = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($Credential.UserName):$($Credential.GetNetworkCredential().Password)"))
}

$TokenResponse = Invoke-RestMethod -Uri "$JamfUrl/api/v1/auth/token" -Method Post -Headers $Headers
$BearerToken = $TokenResponse.token
```

## Computer Management

### Get All Computers
```bash
curl -H "Authorization: Bearer $TOKEN" \
  "$JAMF_URL/JSSResource/computers" \
  -H "Accept: application/json"
```

### Get Computer Details
```bash
COMPUTER_ID=123

curl -H "Authorization: Bearer $TOKEN" \
  "$JAMF_URL/JSSResource/computers/id/$COMPUTER_ID" \
  -H "Accept: application/json"
```

### Search Computers by User
```bash
USER_EMAIL="jdoe@company.com"

curl -H "Authorization: Bearer $TOKEN" \
  "$JAMF_URL/JSSResource/computers/match/$USER_EMAIL" \
  -H "Accept: application/json"
```

## User Assignment

### Assign Computer to User
```bash
COMPUTER_ID=123
USER_NAME="jdoe@company.com"

curl -H "Authorization: Bearer $TOKEN" \
  "$JAMF_URL/JSSResource/computers/id/$COMPUTER_ID" \
  -X PUT \
  -H "Content-Type: application/xml" \
  -d "<computer>
        <location>
          <username>$USER_NAME</username>
          <email_address>$USER_NAME</email_address>
        </location>
      </computer>"
```

### PowerShell: Update Computer Assignment
```powershell
function Set-JamfComputerUser {
    param(
        [int]$ComputerId,
        [string]$UserEmail,
        [string]$FullName
    )
    
    $Headers = @{
        "Authorization" = "Bearer $BearerToken"
        "Content-Type" = "application/xml"
    }
    
    $Body = @"
<computer>
    <location>
        <username>$UserEmail</username>
        <email_address>$UserEmail</email_address>
        <real_name>$FullName</real_name>
    </location>
</computer>
"@
    
    Invoke-RestMethod -Uri "$JamfUrl/JSSResource/computers/id/$ComputerId" `
        -Method Put -Headers $Headers -Body $Body
}
```

## Configuration Profiles

### List Configuration Profiles
```bash
curl -H "Authorization: Bearer $TOKEN" \
  "$JAMF_URL/JSSResource/osxconfigurationprofiles" \
  -H "Accept: application/json"
```

### Deploy Profile to Computer
```bash
PROFILE_ID=10
COMPUTER_ID=123

curl -H "Authorization: Bearer $TOKEN" \
  "$JAMF_URL/JSSResource/computergroups/id/1" \
  -X PUT \
  -H "Content-Type: application/xml" \
  -d "<computer_group>
        <computers>
          <computer><id>$COMPUTER_ID</id></computer>
        </computers>
      </computer_group>"
```

## Mobile Device Commands

### Send Blank Push
```bash
COMPUTER_ID=123

curl -H "Authorization: Bearer $TOKEN" \
  "$JAMF_URL/JSSResource/computercommands/command/BlankPush/id/$COMPUTER_ID" \
  -X POST
```

### Lock Computer
```bash
curl -H "Authorization: Bearer $TOKEN" \
  "$JAMF_URL/api/v1/computer-prestages/$PRESTAGE_ID/scope" \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{"serialNumbers":["C02ABC123"]}'
```

## Inventory Collection

### Trigger Inventory Update
```bash
COMPUTER_ID=123

curl -H "Authorization: Bearer $TOKEN" \
  "$JAMF_URL/JSSResource/computercommands/command/UpdateInventory/id/$COMPUTER_ID" \
  -X POST
```

## Integration with User Provisioning

### Complete JAMF Integration Script
```powershell
# jamf-integration.ps1

function Initialize-JamfSession {
    param(
        [string]$JamfUrl = "https://your-instance.jamfcloud.com",
        [PSCredential]$Credential
    )
    
    $BasicAuth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($Credential.UserName):$($Credential.GetNetworkCredential().Password)"))
    
    $Headers = @{
        "Authorization" = "Basic $BasicAuth"
    }
    
    $TokenResponse = Invoke-RestMethod -Uri "$JamfUrl/api/v1/auth/token" -Method Post -Headers $Headers
    
    return @{
        Url = $JamfUrl
        Token = $TokenResponse.token
        Expiration = $TokenResponse.expires
    }
}

function Find-JamfComputerBySerial {
    param(
        [hashtable]$Session,
        [string]$SerialNumber
    )
    
    $Headers = @{
        "Authorization" = "Bearer $($Session.Token)"
        "Accept" = "application/json"
    }
    
    $Response = Invoke-RestMethod -Uri "$($Session.Url)/JSSResource/computers/serialnumber/$SerialNumber" `
        -Method Get -Headers $Headers
    
    return $Response.computer
}

function Set-JamfComputerOwner {
    param(
        [hashtable]$Session,
        [int]$ComputerId,
        [string]$UserEmail,
        [string]$FullName,
        [string]$Department
    )
    
    $Headers = @{
        "Authorization" = "Bearer $($Session.Token)"
        "Content-Type" = "application/xml"
    }
    
    $Body = @"
<computer>
    <location>
        <username>$UserEmail</username>
        <email_address>$UserEmail</email_address>
        <real_name>$FullName</real_name>
        <department>$Department</department>
    </location>
</computer>
"@
    
    Invoke-RestMethod -Uri "$($Session.Url)/JSSResource/computers/id/$ComputerId" `
        -Method Put -Headers $Headers -Body $Body
    
    Write-Host "✓ Computer $ComputerId assigned to $UserEmail" -ForegroundColor Green
}

function Send-JamfInventoryUpdate {
    param(
        [hashtable]$Session,
        [int]$ComputerId
    )
    
    $Headers = @{
        "Authorization" = "Bearer $($Session.Token)"
    }
    
    Invoke-RestMethod -Uri "$($Session.Url)/JSSResource/computercommands/command/UpdateInventory/id/$ComputerId" `
        -Method Post -Headers $Headers
    
    Write-Host "✓ Inventory update triggered for computer $ComputerId" -ForegroundColor Green
}

# Usage Example
$JamfCred = Get-Credential -Message "Enter JAMF API credentials"
$JamfSession = Initialize-JamfSession -Credential $JamfCred

# Find computer by serial
$Computer = Find-JamfComputerBySerial -Session $JamfSession -SerialNumber "C02ABC123"

# Assign to user
Set-JamfComputerOwner -Session $JamfSession `
    -ComputerId $Computer.general.id `
    -UserEmail "jdoe@company.com" `
    -FullName "John Doe" `
    -Department "Engineering"

# Trigger inventory update
Send-JamfInventoryUpdate -Session $JamfSession -ComputerId $Computer.general.id
```

## Automated Provisioning Workflow

### Complete Device + User Provisioning
```powershell
# provision-with-jamf.ps1

param(
    [Parameter(Mandatory=$true)]
    [string]$UserEmail,
    
    [Parameter(Mandatory=$true)]
    [string]$DisplayName,
    
    [Parameter(Mandatory=$true)]
    [string]$Department,
    
    [Parameter(Mandatory=$true)]
    [string]$SerialNumber  # MacBook serial number
)

Write-Host "=== Complete Provisioning with JAMF ===" -ForegroundColor Cyan

# 1. Provision user in Entra ID
Write-Host "`n[1/4] Provisioning user in Entra ID..." -ForegroundColor Yellow
$UserResult = .\provisioning\provision-new-employee.ps1 `
    -UserEmail $UserEmail `
    -DisplayName $DisplayName `
    -Department $Department `
    -JobTitle "Employee"

if ($UserResult.Status -ne "Success") {
    throw "User provisioning failed"
}

# 2. Initialize JAMF
Write-Host "`n[2/4] Connecting to JAMF..." -ForegroundColor Yellow
$JamfCred = Get-Credential -Message "JAMF API Credentials"
$JamfSession = Initialize-JamfSession -Credential $JamfCred

# 3. Find computer
Write-Host "`n[3/4] Finding computer in JAMF..." -ForegroundColor Yellow
$Computer = Find-JamfComputerBySerial -Session $JamfSession -SerialNumber $SerialNumber

if (-not $Computer) {
    throw "Computer not found: $SerialNumber"
}

Write-Host "Found: $($Computer.general.name) (ID: $($Computer.general.id))" -ForegroundColor Green

# 4. Assign computer to user
Write-Host "`n[4/4] Assigning computer to user..." -ForegroundColor Yellow
Set-JamfComputerOwner -Session $JamfSession `
    -ComputerId $Computer.general.id `
    -UserEmail $UserEmail `
    -FullName $DisplayName `
    -Department $Department

Send-JamfInventoryUpdate -Session $JamfSession -ComputerId $Computer.general.id

Write-Host "`n=== Provisioning Complete ===" -ForegroundColor Green
Write-Host "User: $DisplayName ($UserEmail)"
Write-Host "Computer: $SerialNumber"
Write-Host "JAMF ID: $($Computer.general.id)"
```

## Reporting

### Get Fleet Inventory
```powershell
function Get-JamfFleetReport {
    param([hashtable]$Session)
    
    $Headers = @{
        "Authorization" = "Bearer $($Session.Token)"
        "Accept" = "application/json"
    }
    
    $Computers = Invoke-RestMethod -Uri "$($Session.Url)/JSSResource/computers" `
        -Method Get -Headers $Headers
    
    $Report = foreach ($Computer in $Computers.computers) {
        $Details = Invoke-RestMethod -Uri "$($Session.Url)/JSSResource/computers/id/$($Computer.id)" `
            -Method Get -Headers $Headers
        
        [PSCustomObject]@{
            Name = $Details.computer.general.name
            Serial = $Details.computer.general.serial_number
            Model = $Details.computer.hardware.model
            OS = $Details.computer.hardware.os_version
            User = $Details.computer.location.username
            Email = $Details.computer.location.email_address
            Department = $Details.computer.location.department
            LastInventory = $Details.computer.general.last_contact_time
        }
    }
    
    return $Report
}

# Generate report
$FleetReport = Get-JamfFleetReport -Session $JamfSession
$FleetReport | Export-Csv "jamf-fleet-report.csv" -NoTypeInformation
```
