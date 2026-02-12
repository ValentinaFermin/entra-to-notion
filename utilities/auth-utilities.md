# Authentication and Utilities

## Service Principal Setup

### Create Service Principal for Automation
```powershell
# setup-service-principal.ps1

<#
.SYNOPSIS
    Creates a service principal for automated authentication
#>

Connect-MgGraph -Scopes "Application.ReadWrite.All"

# Create app registration
$AppParams = @{
    DisplayName = "MacOS Fleet Automation"
    SignInAudience = "AzureADMyOrg"
}

$App = New-MgApplication @AppParams

# Create service principal
$SP = New-MgServicePrincipal -AppId $App.AppId

Write-Host "Application Created:"
Write-Host "  App ID: $($App.AppId)"
Write-Host "  Object ID: $($App.Id)"
Write-Host "  Service Principal ID: $($SP.Id)"

# Create client secret
$PasswordCred = @{
    DisplayName = "Automation Secret"
    EndDateTime = (Get-Date).AddYears(2)
}

$Secret = Add-MgApplicationPassword -ApplicationId $App.Id -PasswordCredential $PasswordCred

Write-Host "`nClient Secret:"
Write-Host "  Secret Value: $($Secret.SecretText)"
Write-Host "  Secret ID: $($Secret.KeyId)"
Write-Host "  Expires: $($Secret.EndDateTime)"

Write-Host "`n⚠ IMPORTANT: Save these values securely!"
Write-Host "You won't be able to see the secret again.`n"

# Required API Permissions
$RequiredPermissions = @(
    "User.ReadWrite.All",
    "Group.ReadWrite.All",
    "Directory.ReadWrite.All",
    "Organization.Read.All"
)

Write-Host "Required API Permissions:"
$RequiredPermissions | ForEach-Object { Write-Host "  - $_" }
Write-Host "`nGrant admin consent in Azure Portal:`n"
Write-Host "https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/CallAnAPI/appId/$($App.AppId)`n"

# Save to config file
$Config = @{
    TenantId = (Get-MgOrganization).Id
    ClientId = $App.AppId
    ClientSecretPlaceholder = "REPLACE_WITH_SECRET"
    ServicePrincipalId = $SP.Id
}

$Config | ConvertTo-Json | Out-File "config.json"
Write-Host "✓ Config template saved: config.json"

Disconnect-MgGraph
```

## Configuration Management

### Configuration File Template
```json
{
  "TenantId": "your-tenant-id",
  "ClientId": "your-client-id",
  "ClientSecret": "your-client-secret",
  "BitwardenOrgId": "your-bitwarden-org-id",
  "DefaultLicense": "SPE_E5",
  "DefaultGroups": ["All Employees", "MacBook Users"],
  "EmailDomain": "company.com",
  "RetentionDays": 90,
  "LicenseThreshold": 10
}
```

### Load Configuration
```powershell
# config-loader.ps1

function Get-AutomationConfig {
    if (Test-Path "config.json") {
        return Get-Content "config.json" | ConvertFrom-Json
    } else {
        throw "Configuration file not found. Run setup-service-principal.ps1 first."
    }
}

# Usage
$Config = Get-AutomationConfig
```

## Authentication Functions

### Unified Authentication
```powershell
# auth-functions.ps1

function Connect-AutomationServices {
    param(
        [Parameter(Mandatory=$false)]
        [string]$ConfigPath = "config.json"
    )
    
    if (-not (Test-Path $ConfigPath)) {
        throw "Config file not found: $ConfigPath"
    }
    
    $Config = Get-Content $ConfigPath | ConvertFrom-Json
    
    # Connect to Microsoft Graph
    Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Yellow
    $SecureSecret = ConvertTo-SecureString $Config.ClientSecret -AsPlainText -Force
    $Credential = New-Object System.Management.Automation.PSCredential($Config.ClientId, $SecureSecret)
    
    Connect-MgGraph -TenantId $Config.TenantId -ClientSecretCredential $Credential
    Write-Host "✓ Connected to Microsoft Graph" -ForegroundColor Green
    
    # Connect to Exchange Online
    Write-Host "Connecting to Exchange Online..." -ForegroundColor Yellow
    # Note: Exchange requires certificate auth for service principal
    # This is a placeholder - implement with certificate
    Write-Host "⚠ Exchange Online requires certificate authentication" -ForegroundColor Yellow
    
    # Unlock Bitwarden
    Write-Host "Unlocking Bitwarden..." -ForegroundColor Yellow
    $env:BW_SESSION = bw unlock --raw
    Write-Host "✓ Bitwarden unlocked" -ForegroundColor Green
    
    return $Config
}

function Disconnect-AutomationServices {
    Write-Host "Disconnecting services..." -ForegroundColor Yellow
    
    Disconnect-MgGraph -ErrorAction SilentlyContinue
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
    bw lock
    
    Write-Host "✓ Disconnected" -ForegroundColor Green
}

# Usage:
# $Config = Connect-AutomationServices
# ... do work ...
# Disconnect-AutomationServices
```

## Helper Functions

### Password Generator
```powershell
# password-generator.ps1

function New-SecurePassword {
    param(
        [int]$Length = 16,
        [int]$MinSpecialChars = 4
    )
    
    Add-Type -AssemblyName System.Web
    return [System.Web.Security.Membership]::GeneratePassword($Length, $MinSpecialChars)
}
```

### Email Validation
```powershell
function Test-EmailAddress {
    param([string]$Email)
    
    return $Email -match '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
}
```

### Logging
```powershell
# logging.ps1

function Write-AutomationLog {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO",
        
        [string]$LogFile = "automation.log"
    )
    
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$Timestamp] [$Level] $Message"
    
    # Console output with color
    $Color = switch ($Level) {
        "INFO" { "White" }
        "WARNING" { "Yellow" }
        "ERROR" { "Red" }
        "SUCCESS" { "Green" }
    }
    
    Write-Host $LogEntry -ForegroundColor $Color
    
    # File output
    $LogEntry | Out-File $LogFile -Append
}

# Usage:
# Write-AutomationLog "User created successfully" -Level SUCCESS
# Write-AutomationLog "License threshold reached" -Level WARNING
```

### Error Handler
```powershell
# error-handler.ps1

function Invoke-WithErrorHandling {
    param(
        [Parameter(Mandatory=$true)]
        [ScriptBlock]$ScriptBlock,
        
        [string]$ErrorMessage = "An error occurred"
    )
    
    try {
        & $ScriptBlock
    }
    catch {
        Write-AutomationLog "$ErrorMessage : $($_.Exception.Message)" -Level ERROR
        Write-AutomationLog $_.ScriptStackTrace -Level ERROR
        throw
    }
}

# Usage:
# Invoke-WithErrorHandling {
#     New-MgUser @UserParams
# } -ErrorMessage "Failed to create user"
```

## Rate Limiting

### API Rate Limiter
```powershell
# rate-limiter.ps1

$Script:LastAPICall = Get-Date
$Script:MinInterval = 1  # seconds between calls

function Invoke-WithRateLimit {
    param(
        [Parameter(Mandatory=$true)]
        [ScriptBlock]$ScriptBlock,
        
        [int]$MinIntervalSeconds = 1
    )
    
    $TimeSinceLastCall = (Get-Date) - $Script:LastAPICall
    $WaitTime = $MinIntervalSeconds - $TimeSinceLastCall.TotalSeconds
    
    if ($WaitTime -gt 0) {
        Start-Sleep -Seconds $WaitTime
    }
    
    $Result = & $ScriptBlock
    $Script:LastAPICall = Get-Date
    
    return $Result
}

# Usage:
# Invoke-WithRateLimit {
#     New-MgUser @UserParams
# } -MinIntervalSeconds 2
```

## Data Validation

### User Data Validator
```powershell
# validators.ps1

function Test-UserData {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$UserData
    )
    
    $Errors = @()
    
    # Required fields
    if (-not $UserData.Email -or -not (Test-EmailAddress $UserData.Email)) {
        $Errors += "Invalid or missing email"
    }
    
    if (-not $UserData.DisplayName) {
        $Errors += "Missing display name"
    }
    
    if (-not $UserData.Department) {
        $Errors += "Missing department"
    }
    
    # Email domain check
    if ($UserData.Email -notlike "*@company.com") {
        $Errors += "Email must be @company.com domain"
    }
    
    if ($Errors.Count -gt 0) {
        throw "Validation errors:`n" + ($Errors -join "`n")
    }
    
    return $true
}
```

## Backup and Restore

### Backup Current State
```powershell
# backup-state.ps1

function Backup-TenantState {
    $BackupDate = Get-Date -Format "yyyy-MM-dd-HHmmss"
    $BackupDir = "backups/$BackupDate"
    
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    
    Connect-MgGraph -Scopes "User.Read.All", "Group.Read.All"
    
    # Export users
    Get-MgUser -All -Property * |
        Export-Clixml "$BackupDir/users.xml"
    
    # Export groups
    Get-MgGroup -All |
        Export-Clixml "$BackupDir/groups.xml"
    
    # Export licenses
    Get-MgSubscribedSku |
        Export-Clixml "$BackupDir/licenses.xml"
    
    Write-Host "✓ Backup complete: $BackupDir" -ForegroundColor Green
    
    Disconnect-MgGraph
}
```

## Scheduler Setup

### Windows Task Scheduler Setup
```powershell
# setup-scheduled-tasks.ps1

# Daily health check at 6 AM
$Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-File `"$PSScriptRoot\monitoring\daily-health-check.ps1`""
$Trigger = New-ScheduledTaskTrigger -Daily -At 6AM
$Settings = New-ScheduledTaskSettingsSet -RunOnlyIfNetworkAvailable

Register-ScheduledTask -TaskName "Fleet-DailyHealthCheck" -Action $Action -Trigger $Trigger -Settings $Settings -User "SYSTEM"

Write-Host "✓ Scheduled task created: Fleet-DailyHealthCheck" -ForegroundColor Green
```
