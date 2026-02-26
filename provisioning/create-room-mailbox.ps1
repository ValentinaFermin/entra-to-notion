# Create a meeting room — replicating existing room config (no license)

Connect-ExchangeOnline -UserPrincipalName admin@company.com
Connect-MgGraph -Scopes "User.ReadWrite.All","Group.ReadWrite.All","Directory.ReadWrite.All" -NoWelcome

# ── 1. Create the Room Mailbox ───────────────────────────────────────────────
Write-Host "`n[1/6] Creating room mailbox: New Meeting Room" -ForegroundColor Yellow

New-Mailbox -Name "New Meeting Room" `
    -DisplayName "New Meeting Room" `
    -Room `
    -PrimarySmtpAddress "room-new@company.com" `
    -Alias "mr.new"

Write-Host "       Room mailbox created" -ForegroundColor Green

# Wait for mailbox provisioning to propagate to Entra
Write-Host "       Waiting for Entra sync..." -ForegroundColor DarkGray
$maxWait = 12
for ($i = 1; $i -le $maxWait; $i++) {
    Start-Sleep -Seconds 10
    $user = Get-MgUser -Filter "mailNickname eq 'mr.new'" -ErrorAction SilentlyContinue
    if ($user) {
        Write-Host "       User synced to Entra: $($user.Id)" -ForegroundColor Green
        break
    }
    Write-Host "       Attempt $i/$maxWait — not yet synced..." -ForegroundColor DarkGray
}

if (-not $user) {
    Write-Host "       WARNING: User not yet visible in Entra. Continuing anyway..." -ForegroundColor Yellow
}

# ── 2. Set Entra user properties ─────────────────────────────────────────────
Write-Host "`n[2/6] Setting user properties" -ForegroundColor Yellow

if ($user) {
    Update-MgUser -UserId $user.Id `
        -CompanyName "Contoso" `
        -OfficeLocation "Branch Office" `
        -City "City Name" `
        -Country "Country" `
        -UsageLocation "US"
    Write-Host "       Properties set (Company, Office, City, Country, UsageLocation)" -ForegroundColor Green

    # Enable the room mailbox account
    Update-MgUser -UserId $user.Id -AccountEnabled:$true
    Write-Host "       Account enabled" -ForegroundColor Green
}

# ── 3. Configure calendar processing (match existing room config) ─────────────
Write-Host "`n[3/6] Configuring calendar processing" -ForegroundColor Yellow

Set-CalendarProcessing -Identity "room-new@company.com" `
    -AutomateProcessing AutoAccept `
    -AllowConflicts $false `
    -BookingWindowInDays 180 `
    -MaximumDurationInMinutes 1440 `
    -AllowRecurringMeetings $true `
    -EnforceCapacity $false `
    -AddOrganizerToSubject $true `
    -DeleteSubject $true `
    -DeleteComments $true `
    -RemovePrivateProperty $true

Write-Host "       Calendar processing configured (AutoAccept, 180-day window, 24h max)" -ForegroundColor Green

# ── 4. Set calendar permissions ──────────────────────────────────────────────
Write-Host "`n[4/6] Setting calendar permissions" -ForegroundColor Yellow

# Wait for calendar folder to be ready
$calReady = $false
for ($i = 1; $i -le 6; $i++) {
    try {
        Set-MailboxFolderPermission -Identity "room-new@company.com:\Calendar" `
            -User Default -AccessRights LimitedDetails -ErrorAction Stop
        $calReady = $true
        Write-Host "       Default permission set to LimitedDetails" -ForegroundColor Green
        break
    } catch {
        Write-Host "       Calendar not ready — attempt $i/6, retrying in 15s..." -ForegroundColor DarkGray
        Start-Sleep -Seconds 15
    }
}

if (-not $calReady) {
    Write-Host "       WARNING: Could not set calendar permissions — set manually later" -ForegroundColor Yellow
}

# ── 5. Add to groups (matching existing room config) ──────────────────────────
Write-Host "`n[5/6] Adding to groups" -ForegroundColor Yellow

if ($user) {
    # Compliance group
    $complianceGroup = Get-MgGroup -Filter "displayName eq 'GRP_Compliance_Users'" -ErrorAction SilentlyContinue
    if ($complianceGroup) {
        try {
            New-MgGroupMember -GroupId $complianceGroup.Id -DirectoryObjectId $user.Id -ErrorAction Stop
            Write-Host "       Added to: GRP_Compliance_Users" -ForegroundColor Green
        } catch {
            Write-Host "       Already in or cannot add to: GRP_Compliance_Users" -ForegroundColor DarkGray
        }
    }

    # All Users
    $allUsersGroup = Get-MgGroup -Filter "displayName eq 'All Users'" -ErrorAction SilentlyContinue
    if ($allUsersGroup) {
        try {
            New-MgGroupMember -GroupId $allUsersGroup.Id -DirectoryObjectId $user.Id -ErrorAction Stop
            Write-Host "       Added to: All Users" -ForegroundColor Green
        } catch {
            Write-Host "       Already in or cannot add to: All Users" -ForegroundColor DarkGray
        }
    }
}

# ── 6. Add to room list ─────────────────────────────────────────────────────
Write-Host "`n[6/6] Adding to room list" -ForegroundColor Yellow

try {
    Add-DistributionGroupMember -Identity "Company-RoomList" -Member "room-new@company.com" -ErrorAction Stop
    Write-Host "       Added to: Company-RoomList" -ForegroundColor Green
} catch {
    Write-Host "       Could not add to Company-RoomList: $($_.Exception.Message)" -ForegroundColor Yellow
}

# ── Summary ──────────────────────────────────────────────────────────────────
Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║              MEETING ROOM — CREATED                         ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host "║  Display Name:    New Meeting Room" -ForegroundColor Cyan
Write-Host "║  Email:           room-new@company.com" -ForegroundColor Cyan
Write-Host "║  Alias:           mr.new" -ForegroundColor Cyan
Write-Host "║  Type:            Room Mailbox (no license)" -ForegroundColor Cyan
Write-Host "║  Office:          Branch Office" -ForegroundColor Cyan
Write-Host "║  City:            City Name, Country" -ForegroundColor Cyan
Write-Host "║  Calendar:        AutoAccept, LimitedDetails for Default" -ForegroundColor Cyan
Write-Host "║  Groups:          GRP_Compliance_Users, All Users" -ForegroundColor Cyan
Write-Host "║  Room List:       Company-RoomList" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
