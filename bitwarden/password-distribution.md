# Bitwarden Password Distribution

## Prerequisites

### Install Bitwarden CLI
```bash
# macOS
brew install bitwarden-cli

# Or download from
# https://bitwarden.com/download/

# Verify installation
bw --version
```

## Authentication

### Login
```bash
# Interactive login
bw login

# Login with environment variables
export BW_CLIENTID="your-client-id"
export BW_CLIENTSECRET="your-client-secret"
bw login --apikey

# Get session token
export BW_SESSION=$(bw unlock --raw)
```

### Unlock Vault
```bash
# Unlock and store session
export BW_SESSION=$(bw unlock --raw)

# Verify unlock status
bw status
```

### Logout
```bash
bw logout
```

## Organization Management

### Sync Vault
```bash
bw sync
```

### List Organizations
```bash
bw list organizations
```

### Get Organization ID
```bash
bw list organizations | jq -r '.[] | select(.name=="Company Name") | .id'
```

## Item Management

### Create Secure Note (Password Record)
```bash
# Create JSON template
cat > password-item.json << 'EOF'
{
  "organizationId": "org-id-here",
  "type": 2,
  "secureNote": {
    "type": 0
  },
  "name": "John Doe - Initial Password",
  "notes": "Username: jdoe@company.com\nPassword: TempPass123!\nValid until first login",
  "folderId": null
}
EOF

# Create item
bw create item $(cat password-item.json | jq -c)
```

### Create Login Item
```bash
cat > login-item.json << 'EOF'
{
  "organizationId": "org-id-here",
  "type": 1,
  "login": {
    "username": "jdoe@company.com",
    "password": "TempPass123!",
    "totp": null,
    "uris": [
      {
        "uri": "https://portal.office.com",
        "match": null
      }
    ]
  },
  "name": "John Doe - Microsoft 365",
  "notes": "First login requires password change",
  "folderId": null
}
EOF

bw create item $(cat login-item.json | jq -c)
```

### List Items
```bash
# All items
bw list items

# Search by name
bw list items --search "John Doe"

# Filter by organization
bw list items --organizationid "org-id"
```

### Get Item
```bash
# By ID
bw get item "item-id"

# By name
bw get item "John Doe - Initial Password"

# Get password field
bw get password "item-id"
```

### Update Item
```bash
# Get existing item
bw get item "item-id" > item.json

# Edit item.json
# Then update
bw edit item "item-id" $(cat item.json | jq -c)
```

### Delete Item
```bash
bw delete item "item-id"
```

## Collection Management

### Create Collection
```bash
cat > collection.json << 'EOF'
{
  "organizationId": "org-id-here",
  "name": "New Hire Passwords",
  "externalId": null,
  "groups": []
}
EOF

bw create org-collection $(cat collection.json | jq -c)
```

### List Collections
```bash
bw list org-collections --organizationid "org-id"
```

### Assign Item to Collection
```bash
# This requires editing the item and adding collectionIds
bw get item "item-id" | jq '.collectionIds += ["collection-id"]' > item.json
bw edit item "item-id" $(cat item.json | jq -c)
```

## User Provisioning Integration

### PowerShell Script: Create User Password in Bitwarden
```powershell
# create-user-password.ps1

param(
    [Parameter(Mandatory=$true)]
    [string]$UserEmail,
    
    [Parameter(Mandatory=$true)]
    [string]$DisplayName,
    
    [Parameter(Mandatory=$true)]
    [string]$TempPassword,
    
    [Parameter(Mandatory=$true)]
    [string]$OrganizationId
)

# Unlock Bitwarden
$env:BW_SESSION = bw unlock --raw

# Create password item
$ItemJson = @{
    organizationId = $OrganizationId
    type = 2  # Secure Note
    secureNote = @{
        type = 0
    }
    name = "$DisplayName - Initial Password"
    notes = @"
Username: $UserEmail
Password: $TempPassword
Valid until: First login
Created: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
"@
    folderId = $null
} | ConvertTo-Json -Compress

# Create item in Bitwarden
$Result = bw create item $ItemJson | ConvertFrom-Json

Write-Host "Password stored in Bitwarden - Item ID: $($Result.id)" -ForegroundColor Green

# Sync
bw sync
```

### Bash Script: Bulk Import Passwords
```bash
#!/bin/bash
# bulk-import-passwords.sh

ORG_ID="your-org-id"
CSV_FILE="new-users.csv"

# Unlock vault
export BW_SESSION=$(bw unlock --raw)

# Read CSV and create items
tail -n +2 "$CSV_FILE" | while IFS=, read -r email name password; do
    # Create JSON
    cat > temp-item.json << EOF
{
  "organizationId": "$ORG_ID",
  "type": 2,
  "secureNote": {
    "type": 0
  },
  "name": "$name - Initial Password",
  "notes": "Username: $email\nPassword: $password\nValid until first login\nCreated: $(date +'%Y-%m-%d %H:%M:%S')",
  "folderId": null
}
EOF
    
    # Create item
    ITEM_ID=$(bw create item $(cat temp-item.json | jq -c) | jq -r '.id')
    echo "Created password for $email - Item ID: $ITEM_ID"
    
    # Rate limiting
    sleep 1
done

# Cleanup
rm temp-item.json
bw sync

echo "Bulk import completed"
```

## Sharing Passwords

### Share with Specific User
```bash
# Add user to collection
# Users must be invited to organization first

# Create collection for sharing
cat > share-collection.json << 'EOF'
{
  "organizationId": "org-id",
  "name": "Shared with IT Team",
  "externalId": null,
  "groups": []
}
EOF

COLLECTION_ID=$(bw create org-collection $(cat share-collection.json | jq -c) | jq -r '.id')

# Assign item to collection
bw get item "item-id" | jq --arg cid "$COLLECTION_ID" '.collectionIds += [$cid]' > item.json
bw edit item "item-id" $(cat item.json | jq -c)
```

## Reporting

### Export Passwords (Encrypted)
```bash
# Export vault (JSON)
bw export --format json --output vault-backup.json

# Export encrypted
bw export --format encrypted_json --password "backup-password" --output vault-encrypted.json
```

### List All Organization Items
```bash
bw list items --organizationid "org-id" | jq -r '.[] | "\(.name) - Created: \(.revisionDate)"'
```

### Password Expiry Report
```bash
# List items older than 90 days (manual review needed)
bw list items | jq -r '.[] | select(.revisionDate < (now - 7776000 | todate)) | "\(.name) - Last updated: \(.revisionDate)"'
```

## Automation Integration

### Complete User Provisioning Script
```powershell
# provision-new-user.ps1

param(
    [Parameter(Mandatory=$true)]
    [string]$UserEmail,
    
    [Parameter(Mandatory=$true)]
    [string]$DisplayName,
    
    [Parameter(Mandatory=$true)]
    [string]$Department,
    
    [string]$BitwardenOrgId = "your-org-id"
)

# Generate random password
Add-Type -AssemblyName System.Web
$TempPassword = [System.Web.Security.Membership]::GeneratePassword(16, 4)

# 1. Create Entra ID User
Connect-MgGraph -Scopes "User.ReadWrite.All"

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
    UsageLocation = "US"
}

$NewUser = New-MgUser @UserParams
Write-Host "✓ Created Entra ID user: $UserEmail" -ForegroundColor Green

# 2. Assign License
$E5SkuId = (Get-MgSubscribedSku -All | Where-Object {$_.SkuPartNumber -eq "SPE_E5"}).SkuId
Set-MgUserLicense -UserId $NewUser.Id -AddLicenses @{SkuId = $E5SkuId} -RemoveLicenses @()
Write-Host "✓ Assigned E5 license" -ForegroundColor Green

# 3. Store Password in Bitwarden
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
Valid until: First login
Created: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
"@
} | ConvertTo-Json -Compress

bw create item $ItemJson
bw sync
Write-Host "✓ Password stored in Bitwarden" -ForegroundColor Green

Write-Host "`n=== User Provisioning Complete ===" -ForegroundColor Cyan
Write-Host "User: $DisplayName ($UserEmail)"
Write-Host "Password available in Bitwarden: '$DisplayName - Initial Password'"
```

## Security Best Practices

### Regular Password Rotation Reminder
```bash
#!/bin/bash
# check-password-age.sh

export BW_SESSION=$(bw unlock --raw)

# Get items older than 90 days
CUTOFF_DATE=$(date -u -d '90 days ago' +%s)

bw list items --organizationid "org-id" | jq -r --arg cutoff "$CUTOFF_DATE" '.[] | 
  select(.revisionDate | fromdateiso8601 < ($cutoff | tonumber)) | 
  "\(.name) - Last updated: \(.revisionDate)"'
```

### Cleanup Used Passwords
```bash
# Delete items after user first login (run after verification)
# Create a "processed" collection and move items there instead of deletion
```
