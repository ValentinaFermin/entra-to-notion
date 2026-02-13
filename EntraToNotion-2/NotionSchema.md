# Notion Database Schema

Create a **full-page database** in Notion with the following properties.

> **Tip**: After creating the database, click **•••** → **Connections** → add your Platform Tracker integration.

## Required Properties

| Property            | Type          | Configuration                                                                  |
|---------------------|---------------|--------------------------------------------------------------------------------|
| **Service Name**    | Title         | Default title column                                                           |
| **Category**        | Select        | Options: `Identity`, `Security`, `MDM`, `Collaboration`, `Infrastructure`, `Communications`, `Monitoring` |
| **Status**          | Select        | Options: `Active`, `Renewing Soon`, `Overdue`, `Under Review`, `Cancelled`     |
| **Cost**            | Number        | Format: **Dollar** ($)                                                         |
| **Cost Unit**       | Select        | Options: `/user/mo`, `/device/mo`, `/host/mo`, `/mo`, `flat`                  |
| **Billing Cycle**   | Select        | Options: `Monthly`, `Annual`, `Pay-as-you-go`                                 |
| **Renewal Date**    | Date          | No end date needed                                                             |
| **Assigned Licenses** | Number     | Plain number                                                                   |
| **Total Licenses**  | Number        | Plain number                                                                   |
| **Source**          | Multi-select  | Options: `Entra ID`, `Bitwarden`, `Jamf Pro`, `Manual`                        |
| **Last Synced**     | Date          | Auto-updated by the script on each run                                         |
| **Notes**           | Rich text     | Free-form notes (auto-populated with usage info)                               |

## Recommended Views

Create these views on top of the database for different use cases:

### 1. Status Board (Board view)
- **Group by**: Status
- Shows services grouped into Active / Renewing Soon / Overdue / Under Review columns

### 2. Renewal Calendar (Calendar view)
- **Date property**: Renewal Date
- Visual timeline of upcoming renewals

### 3. By Source (Table view)
- **Group by**: Source
- See which services came from Entra ID vs Bitwarden vs Jamf vs Manual

### 4. Cost Overview (Table view)
- **Sort by**: Cost (descending)
- **Filter**: Status = Active
- Shows your highest-cost services first

### 5. Stale Apps (Table view)
- **Filter**: Status = "Under Review" AND Source = "Entra ID"
- Surfaces apps flagged as unused — candidates for cancellation

## Adding Services Manually

For services not covered by API collectors (e.g., Cloudflare, Datadog, AWS), add them manually:
1. Set **Source** to `Manual`
2. Fill in **Cost**, **Renewal Date**, and **Billing Cycle** from your invoices
3. The script will skip these rows on future syncs (matched by Service Name)

## Property Color Coding Suggestions

For the **Status** select property, use these colors for visual clarity:
- Active → **Green**
- Renewing Soon → **Yellow**
- Overdue → **Red**
- Under Review → **Blue**
- Cancelled → **Gray**
