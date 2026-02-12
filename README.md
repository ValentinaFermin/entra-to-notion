# MacOS Fleet Automation Repository

Automation scripts and commands for managing 500 MacBooks with Azure Cloud infrastructure.

## Tech Stack
- **Identity**: Microsoft Entra ID (Azure AD)
- **Email**: Exchange Online
- **Password Management**: Bitwarden
- **Device Management**: JAMF Pro
- **Automation**: PowerShell, Python, Azure Automation

## Repository Structure

```
├── entra-id/           # Entra ID user and group management
├── exchange-online/    # Exchange Online mailbox automation
├── bitwarden/          # Bitwarden password distribution
├── jamf/               # JAMF Pro device management
├── licensing/          # Microsoft 365 license management
├── provisioning/       # User onboarding/offboarding workflows
├── monitoring/         # Service health and reporting
└── utilities/          # Helper scripts and tools
```

## Prerequisites

### PowerShell Modules
```powershell
Install-Module Microsoft.Graph -Scope CurrentUser
Install-Module ExchangeOnlineManagement -Scope CurrentUser
Install-Module Az.Automation -Scope CurrentUser
```

### Authentication
All scripts use service principal authentication for security.
See `utilities/authentication.md` for setup.

## Quick Start

1. Clone repository
2. Configure service principal credentials
3. Update configuration files
4. Test in development environment
5. Deploy to production

## License
Internal use only - [Organization Name]
