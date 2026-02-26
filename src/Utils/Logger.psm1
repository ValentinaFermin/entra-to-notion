<#
.SYNOPSIS
    Logging utility for Platform Tracker.

.DESCRIPTION
    Provides colored console output and optional file logging.
    Log levels: INFO, SUCCESS, WARN, ERROR
    Writes to both console and output/audit.log when file logging is enabled.
#>

$script:LogFile = $null

function Initialize-AuditLog {
    param([string]$OutputDir)

    if (-not (Test-Path $OutputDir)) {
        New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $script:LogFile = Join-Path $OutputDir "audit_$timestamp.log"

    # Write header
    $header = @"
============================================================
  Platform & Service Tracker — Audit Log
  Started: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
  Host:    $($env:COMPUTERNAME ?? $env:HOSTNAME ?? "unknown")
  User:    $($env:USERNAME ?? $env:USER ?? "unknown")
============================================================
"@
    $header | Out-File -FilePath $script:LogFile -Encoding utf8
}

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet("INFO", "SUCCESS", "WARN", "ERROR")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $formatted = "[$timestamp] [$Level] $Message"

    # Console output with color
    $color = switch ($Level) {
        "INFO"    { "Cyan" }
        "SUCCESS" { "Green" }
        "WARN"    { "Yellow" }
        "ERROR"   { "Red" }
    }
    Write-Host $formatted -ForegroundColor $color

    # File output
    if ($script:LogFile) {
        $formatted | Out-File -FilePath $script:LogFile -Append -Encoding utf8
    }
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Log "═══ $Title ═══"
}

function Write-Banner {
    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║     Platform & Service Tracker — Audit Sync     ║" -ForegroundColor Cyan
    Write-Host "  ╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

Export-ModuleMember -Function Initialize-AuditLog, Write-Log, Write-Section, Write-Banner
