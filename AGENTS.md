# AGENTS.md

## Cursor Cloud specific instructions

### Overview
This is a PowerShell-based CLI tool ("Entra ID → Notion Sync") that pulls license SKUs and enterprise applications from Microsoft Entra ID via the Microsoft Graph API, then syncs them to a Notion database. There are no local services to start — it is a run-and-exit script.

### Runtime
- **PowerShell 7+** (`pwsh`) is required. Installed via the Microsoft APT repository.
- **Microsoft.Graph** PowerShell module (≥ 2.0.0) is the sole dependency, installed via `./Install-Dependencies.ps1`.

### Running the tool
See `README.md` for all usage flags. Key commands:
- `pwsh ./Start-EntraSync.ps1 -SkipNotion -ExportCsv` — collect from Entra ID, export locally (skip Notion sync)
- `pwsh ./Start-EntraSync.ps1 -WhatIf` — dry run
- `pwsh ./Start-EntraSync.ps1 -SkipNotion -ExportCsv -WhatIf` — dry run with local export

### Testing
- **Module import test**: `pwsh -Command 'Import-Module ./src/Utils/Logger.psm1; Import-Module ./src/Utils/Config.psm1; Import-Module ./src/Utils/SkuMapping.psm1; Import-Module ./src/Collectors/EntraCollector.psm1; Import-Module ./src/Notion/NotionSync.psm1; Write-Host "OK"'`
- **Connection tests** (require real credentials): `pwsh ./tests/Test-EntraConnection.ps1` and `pwsh ./tests/Test-NotionConnection.ps1`
- There are no automated unit test frameworks (e.g., Pester) configured in this repo.

### Credentials
Running the full sync requires external API credentials configured in `config/.env` (copy from `config/.env.example`):
- `ENTRA_TENANT_ID`, `ENTRA_CLIENT_ID`, `ENTRA_CLIENT_SECRET` — Microsoft Entra ID app registration
- `NOTION_TOKEN`, `NOTION_DATABASE_ID` — Notion integration (optional; can skip with `-SkipNotion`)

### Gotchas
- The config loader in `Config.psm1` looks for `.env` in both `config/.env` and the repo root `/.env`. If neither exists, it falls back to environment variables.
- `Install-Dependencies.ps1` is idempotent — it checks for an existing `Microsoft.Graph` module before installing.
- The `output/` directory is created automatically by `Initialize-AuditLog` if it doesn't exist.
- There is no linter or formatter configured for this repo. Module import validation serves as the primary code-quality check.
