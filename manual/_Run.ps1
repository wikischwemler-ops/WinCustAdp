<#
    Starter for the manual scripts: runs one script as administrator in its
    own window and keeps the window open so the output stays readable.
    Called by the .cmd files in this folder, e.g. Edge-Remove.cmd.

    _Run.ps1 -Script <path to .ps1> [-WhatIf]
#>
param(
    [Parameter(Mandatory)][string]$Script,
    [switch]$WhatIf
)

$Script = (Resolve-Path $Script).Path
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())

if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Script', "`"$Script`"")
    if ($WhatIf) { $argList += '-WhatIf' }
    Start-Process -FilePath powershell.exe -Verb RunAs -ArgumentList $argList
    return
}

$name = Split-Path $Script -Leaf
$host.UI.RawUI.WindowTitle = "WinCustAdp - $name"
Write-Host "=== $name ===" -ForegroundColor Cyan
try {
    & $Script -WhatIf:$WhatIf
    Write-Host 'Done.' -ForegroundColor Green
} catch {
    Write-Host "[FAIL] $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ''
Read-Host 'Press Enter to close'
