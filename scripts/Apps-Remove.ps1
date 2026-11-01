<#
    Removes every app listed in config\apps-remove.json:
    - installed packages for all users (Remove-AppxPackage -AllUsers)
    - provisioned packages in the Windows image, so new users do not get them

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

    try {
        foreach ($p in $packages) {
            if ($PSCmdlet.ShouldProcess($p.PackageFullName, 'Remove app for all users')) {
                Remove-AppxPackage -Package $p.PackageFullName -AllUsers
            }
        }
        foreach ($i in $images) {
            if ($PSCmdlet.ShouldProcess($i.PackageName, 'Remove provisioned app')) {
                Remove-AppxProvisionedPackage -Online -PackageName $i.PackageName | Out-Null
            }
        }
        Write-Host "    [OK]   ${name}" -ForegroundColor Green
    } catch {
        Write-Host "    [FAIL] ${name}: $($_.Exception.Message)" -ForegroundColor Red
        $failed.Add($name)
    }
}

if ($failed.Count -gt 0) {
    throw "Could not remove: $($failed -join ', ')"
}
