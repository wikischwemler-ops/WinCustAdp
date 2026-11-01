<#
    Template - files starting with "_" are skipped by Customize.ps1.
    Copy to <Area>-<Function>.ps1, e.g. Apps-RemoveBloatware.ps1
    Use scripts for changes a .reg file cannot do (services, apps, features, files).

    Customize.ps1 runs this elevated. Throw on failure; Customize.ps1 reports it
    and continues with the next script.
#>

$ErrorActionPreference = 'Stop'

# Write-Host 'Doing something...'
