# Entra ID → Notion Sync

Pulls license SKUs and enterprise applications from Microsoft Entra ID, then syncs to a Notion database.

```
EntraToNotion/
├── Start-EntraSync.ps1              # Main entry point
├── Install-Dependencies.ps1
├── .vscode/                         # F5 debug + Ctrl+Shift+B tasks
├── src/
│   ├── Collectors/
│   │   └── EntraCollector.psm1      # Licenses + enterprise apps
│   ├── Notion/
│   │   └── NotionSync.psm1          # Upsert to Notion
│   └── Utils/
│       ├── Config.psm1              # .env loader
│       ├── Logger.psm1              # Console + file logging
│       └── SkuMapping.psm1          # SKU → friendly name mapping
├── config/.env.example              # Template — copy to .env and fill in
├── config/.env                      # Your credentials (gitignored)
├── tests/
│   ├── Test-EntraConnection.ps1
│   └── Test-NotionConnection.ps1
├── output/                          # Exports + logs
└── NotionSchema.md                  # Database setup guide
```

## Quick Start

```powershell
.\Install-Dependencies.ps1

# Option A: Interactive auth (recommended to start)
.\Start-EntraSync.ps1 -Interactive

# Option B: App-only auth (for automation)
.\Start-EntraSync.ps1
```

## Auth Modes

**Interactive (delegated)** — opens browser, you consent:
```powershell
.\Start-EntraSync.ps1 -Interactive
```

**App-only (client credentials)** — for scheduled runs:
1. Create Entra App Registration with the following permissions (Application type):
   - `Application.Read.All`, `Organization.Read.All`, `Directory.Read.All`, `AuditLog.Read.All`
2. Grant admin consent in the Azure portal
3. Fill in `config/.env` (use `config/.env.example` as reference)
4. Run `.\Start-EntraSync.ps1`

## Notion Setup

See [NotionSchema.md](NotionSchema.md) for database property requirements.

## Usage

```powershell
.\Start-EntraSync.ps1                     # Full sync
.\Start-EntraSync.ps1 -WhatIf             # Dry run
.\Start-EntraSync.ps1 -SkipEnterpriseApps  # Licenses only
.\Start-EntraSync.ps1 -SkipNotion -ExportCsv  # Local export
```
