<#
.SYNOPSIS
    Configuration loader for Entra → Notion sync.
#>

function Import-EnvFile {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        Write-Warning "No .env file at $Path — using environment variables."
        return
    }
    Get-Content $Path | ForEach-Object {
        $line = $_.Trim()
        if ($line -eq '' -or $line.StartsWith('#')) { return }
        $parts = $line -split '=', 2
        if ($parts.Count -eq 2) {
            $key   = $parts[0].Trim()
            $value = $parts[1].Trim().Trim('"').Trim("'")
            if (-not [System.Environment]::GetEnvironmentVariable($key)) {
                [System.Environment]::SetEnvironmentVariable($key, $value, 'Process')
            }
        }
    }
}

function Get-TrackerConfig {
    # Load .env
    Import-EnvFile -Path (Join-Path $PSScriptRoot ".." ".." "config" ".env")
    Import-EnvFile -Path (Join-Path $PSScriptRoot ".." ".." ".env")

    return [PSCustomObject]@{
        # Entra ID
        EntraTenantId       = $env:ENTRA_TENANT_ID
        EntraClientId       = $env:ENTRA_CLIENT_ID
        EntraClientSecret   = $env:ENTRA_CLIENT_SECRET
        # Notion
        NotionToken         = $env:NOTION_TOKEN
        NotionDatabaseId    = $env:NOTION_DATABASE_ID
        NotionApiVersion    = "2022-06-28"
        # Options
        StaleAppThresholdDays   = [int]($env:STALE_THRESHOLD_DAYS ?? 90)
        IncludeSignInActivity   = $true
        IncludeAssignmentCounts = $true
    }
}

Export-ModuleMember -Function Get-TrackerConfig, Import-EnvFile
