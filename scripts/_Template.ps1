<#
    Template - files starting with "_" are skipped by Install.ps1.
    Copy to <Area>-<Function>.ps1, e.g. Apps-RemoveBloatware.ps1
    Use scripts for changes a .reg file cannot do (services, apps, features, files).

    Install.ps1 runs this elevated. Throw on failure; Install.ps1 reports it
    and continues with the next script.
#>

$ErrorActionPreference = 'Stop'

# Write-Host 'Doing something...'
