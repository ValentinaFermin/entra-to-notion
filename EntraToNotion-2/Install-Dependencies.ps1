<#
.SYNOPSIS
    Installs required PowerShell modules.
#>

$modules = @(
    @{ Name = "Microsoft.Graph"; MinVersion = "2.0.0" }
)

Write-Host "`n  Installing dependencies...`n" -ForegroundColor Cyan

foreach ($mod in $modules) {
    $installed = Get-Module -ListAvailable -Name $mod.Name |
        Where-Object { $_.Version -ge [version]$mod.MinVersion } |
        Select-Object -First 1

    if ($installed) {
        Write-Host "  ✓ $($mod.Name) v$($installed.Version)" -ForegroundColor Green
    }
    else {
        Write-Host "  ↓ Installing $($mod.Name)..." -ForegroundColor Yellow
        try {
            Install-Module -Name $mod.Name -Scope CurrentUser -Force -AllowClobber
            Write-Host "  ✓ $($mod.Name) installed" -ForegroundColor Green
        }
        catch {
            Write-Host "  ✗ Failed: $_" -ForegroundColor Red
        }
    }
}

Write-Host "`n  Done! Run .\Start-EntraSync.ps1 to begin.`n" -ForegroundColor Cyan
