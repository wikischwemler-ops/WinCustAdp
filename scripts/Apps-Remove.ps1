<#
    Removes every app listed in config\apps-remove.json:
    - installed packages for all users (Remove-AppxPackage -AllUsers)
    - provisioned packages in the Windows image, so new users do not get them

    Stale entries that Windows still lists but whose files are already gone
    (e.g. from deleted user profiles or an old image) are reported, not
    treated as failures.

    Needs admin rights (Customize.ps1 runs it elevated).
    Standalone: .\scripts\Apps-Remove.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '..\config\apps-remove.json')
)

$ErrorActionPreference = 'Stop'

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Apps-Remove.ps1 needs administrator rights.'
}

# 0x80073CF1 package not found, 0x80070002 file not found, 0x80070003 path not found.
# Remove-AppxPackage wraps the code into the message text, DISM sets HResult.
$GoneHResults = @(-2147009295, -2147024894, -2147024893)
$GonePattern  = '0x80073CF1|0x80070002|0x80070003|not found|cannot find|nicht gefunden|nicht finden'

function Test-AlreadyGone($ErrorRecord) {
    $ex = $ErrorRecord.Exception
    return ($GoneHResults -contains $ex.HResult) -or ($ex.Message -match $GonePattern)
}

$names = @((Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json).remove)
Write-Host "  Apps to remove: $($names.Count) (from $ConfigPath)"

$provisioned = @(Get-AppxProvisionedPackage -Online)
$failed = New-Object System.Collections.Generic.List[string]

foreach ($name in $names) {
    $packages = @(Get-AppxPackage -AllUsers -Name $name)
    $images   = @($provisioned | Where-Object { $_.DisplayName -like $name })

    if ($packages.Count -eq 0 -and $images.Count -eq 0) {
        Write-Host "    [--]   ${name} (not installed)" -ForegroundColor DarkGray
        continue
    }

    # Try every entry, even if one of them fails.
    $removed = 0; $stale = 0; $errors = @()
    $targets = @($packages | ForEach-Object { @{ Kind = 'app'; Id = $_.PackageFullName } }) +
               @($images   | ForEach-Object { @{ Kind = 'image'; Id = $_.PackageName } })

    foreach ($t in $targets) {
        $action = if ($t.Kind -eq 'app') { 'Remove app for all users' } else { 'Remove provisioned app' }
        if (-not $PSCmdlet.ShouldProcess($t.Id, $action)) { continue }
        try {
            if ($t.Kind -eq 'app') {
                Remove-AppxPackage -Package $t.Id -AllUsers
            } else {
                Remove-AppxProvisionedPackage -Online -PackageName $t.Id | Out-Null
            }
            $removed++
        } catch {
            if (Test-AlreadyGone $_) { $stale++ } else { $errors += $_.Exception.Message.Trim() }
        }
    }

    if ($errors.Count -gt 0) {
        Write-Host "    [FAIL] ${name}: $($errors -join ' | ')" -ForegroundColor Red
        $failed.Add($name)
    } elseif ($removed -gt 0) {
        $note = if ($stale -gt 0) { " ($stale stale entries skipped)" } else { '' }
        Write-Host "    [OK]   ${name}$note" -ForegroundColor Green
    } elseif ($stale -gt 0) {
        Write-Host "    [--]   ${name} (already gone, $stale stale entries skipped)" -ForegroundColor DarkGray
    }
}

if ($failed.Count -gt 0) {
    throw "Could not remove: $($failed -join ', ')"
}
