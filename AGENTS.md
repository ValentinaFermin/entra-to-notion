# AGENTS.md

## Cursor Cloud specific instructions

### Project overview

EntraToNotion-2 is a PowerShell-based tool that syncs Microsoft Entra ID (Azure AD) license and enterprise app data to a Notion database. All source code lives under `EntraToNotion-2/`.

### Runtime

- **PowerShell 7+** (`pwsh`) is required. Install via the Microsoft apt repository on Ubuntu 24.04.
- **Microsoft.Graph** PowerShell module (≥ 2.0.0) is the only PS dependency. Install with `pwsh -NonInteractive -File ./Install-Dependencies.ps1` from the `EntraToNotion-2/` directory.

### Running the application

All commands run from `EntraToNotion-2/`:

| Command | Purpose |
|---|---|
| `pwsh -File ./Start-EntraSync.ps1` | Full sync (needs Entra + Notion credentials) |
| `pwsh -File ./Start-EntraSync.ps1 -SkipNotion -ExportJson` | Local export only (needs Entra credentials) |
| `pwsh -File ./Start-EntraSync.ps1 -WhatIf` | Dry run |
| `pwsh -File ./Start-EntraSync.ps1 -Interactive` | Delegated auth (opens browser) |

### Credentials (external cloud APIs)

The script requires credentials configured via `config/.env` or environment variables:
- `ENTRA_TENANT_ID`, `ENTRA_CLIENT_ID`, `ENTRA_CLIENT_SECRET` — Microsoft Entra ID app registration
- `NOTION_TOKEN`, `NOTION_DATABASE_ID` — Notion integration

Without these, the script exits gracefully at the auth step (exit code 1). There are no mocks or local stubs.

### Linting / Testing

- **No linter or test framework** is configured. Validation is done via PowerShell syntax parsing:
  ```
  pwsh -Command '[System.Management.Automation.Language.Parser]::ParseFile("path.ps1", [ref]$null, [ref]$errors)'
  ```
- **Integration tests** in `tests/` (`Test-EntraConnection.ps1`, `Test-NotionConnection.ps1`) hit real APIs and require credentials.
- Note: The test scripts reference `Get-PlatformTrackerConfig` but `Config.psm1` exports `Get-TrackerConfig`. These tests will fail with a "command not found" error until this mismatch is resolved.

### Gotchas

- `$PSScriptRoot` is empty when running inline PowerShell commands (`pwsh -Command '...'`). Always use `pwsh -File ./script.ps1` for scripts that depend on `$PSScriptRoot`.
- The `config/` directory and `.env.example` referenced in the README do not exist in the repo. Config falls back to environment variables.
