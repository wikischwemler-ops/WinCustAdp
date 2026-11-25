<#
    Uninstalls the Microsoft Edge browser and keeps it from coming back.

    Safety: only runs if another browser is installed (Chrome, Firefox,
    Opera, ...). On a fresh Windows, Edge is the only way to download another
    browser - then this script skips and says so. Install a browser, then run
    Customize.cmd again.

    - Edge WebView2 Runtime stays: Windows and many apps need it.
    - Removes the Edge autostart ("MicrosoftEdgeAutoLaunch_*" Run values)
      and leftover shortcuts.
    - Blocks reinstall through Edge Update (policy). A Windows feature update
      may still bring Edge back; then simply run Customize.cmd again.

    Undo: delete the value "Install{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}" in
    HKLM\SOFTWARE\Policies\Microsoft\EdgeUpdate and "DoNotUpdateToEdgeWithChromium"
    in HKLM\SOFTWARE\Microsoft\EdgeUpdate, then install Edge from
    https://www.microsoft.com/edge

    Manual script: not run by Customize.cmd. Start it with Edge-Remove.cmd
    (double-click, asks for admin rights) once another browser is installed.
    Preview: .\manual\Edge-Remove.ps1 -WhatIf (as admin)
#>
[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Edge-Remove.ps1 needs administrator rights.'
}

$EdgeAppId   = '{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}'   # Edge Stable in Edge Update
$EdgeExe     = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
$UninstallKey = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge'

# --- Another browser installed? -----------------------------------------------
# Browsers register themselves under Clients\StartMenuInternet.
function Get-OtherBrowsers {
    $roots = 'HKLM:\SOFTWARE\Clients\StartMenuInternet',
             'HKLM:\SOFTWARE\WOW6432Node\Clients\StartMenuInternet',
             'HKCU:\SOFTWARE\Clients\StartMenuInternet'
    foreach ($root in $roots) {
        foreach ($key in @(Get-ChildItem $root -ErrorAction SilentlyContinue)) {
            if ($key.PSChildName -match '^(Microsoft Edge|IEXPLORE\.EXE)$') { continue }
            $cmd = (Get-ItemProperty "$($key.PSPath)\shell\open\command" -ErrorAction SilentlyContinue).'(default)'
            if (-not $cmd) { continue }
            $exe = if ($cmd -match '^"([^"]+)"') { $Matches[1] } else { ($cmd -split ' ')[0] }
            if (Test-Path $exe) { $key.PSChildName }
        }
    }
}

$others = @(Get-OtherBrowsers | Select-Object -Unique)
if ($others.Count -eq 0) {
    Write-Host '    [SKIP] No other browser installed - Edge stays for now.' -ForegroundColor Yellow
    Write-Host '           Install a browser (e.g. Firefox, Chrome), then run Customize.cmd again.' -ForegroundColor Yellow
    return
}
Write-Host "    Other browsers: $($others -join ', ')"

# --- Uninstall ---------------------------------------------------------------
$setup = $null
$uninstall = (Get-ItemProperty $UninstallKey -ErrorAction SilentlyContinue).UninstallString
if ($uninstall -match '^"([^"]+setup\.exe)"') { $setup = $Matches[1] }

if (-not $setup -or -not (Test-Path $setup)) {
    Write-Host '    [--]   Microsoft Edge (not installed)' -ForegroundColor DarkGray
} elseif ($PSCmdlet.ShouldProcess('Microsoft Edge', 'Uninstall')) {
    Get-Process msedge -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    # Edge setup allows uninstalling only in the EEA (device region at Windows
    # setup) - elsewhere it exits with 93. It does allow it while the old
    # (legacy) Edge exists, so an empty placeholder file for it is created
    # for the uninstall and removed again right after.
    $dev       = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdateDev'
    $legacyDir = "$env:SystemRoot\SystemApps\Microsoft.MicrosoftEdge_8wekyb3d8bbwe"
    $legacyExe = Join-Path $legacyDir 'MicrosoftEdge.exe'
    $madeDir   = -not (Test-Path $legacyDir)
    $madeExe   = -not (Test-Path $legacyExe)
    New-Item -Path $dev -Force | Out-Null
    New-ItemProperty -Path $dev -Name AllowUninstall -Value '' -PropertyType String -Force | Out-Null
    try {
        if ($madeExe) {
            New-Item -ItemType Directory -Path $legacyDir -Force | Out-Null
            New-Item -ItemType File -Path $legacyExe -Force | Out-Null
        }
        $setupArgs = '--uninstall --msedge --channel=stable --system-level --verbose-logging --force-uninstall'
        $p = Start-Process -FilePath $setup -ArgumentList $setupArgs -Wait -PassThru -WindowStyle Hidden
    } finally {
        if ($madeExe) { Remove-Item -LiteralPath $legacyExe -Force -ErrorAction SilentlyContinue }
        if ($madeDir) { Remove-Item -LiteralPath $legacyDir -Force -Recurse -ErrorAction SilentlyContinue }
        Remove-ItemProperty -Path $dev -Name AllowUninstall -ErrorAction SilentlyContinue
    }

    # Exit code 19 = uninstalled; check the result anyway.
    if (Test-Path $EdgeExe) {
        throw "Edge is still installed (setup exit code $($p.ExitCode)). Log: msedge_installer.log in $env:SystemRoot\SystemTemp"
    }
    Write-Host '    [OK]   Microsoft Edge uninstalled (WebView2 kept)' -ForegroundColor Green
}

# --- Keep it from coming back --------------------------------------------------
if ($PSCmdlet.ShouldProcess('Edge Update', 'Block Edge reinstall')) {
    $pol = 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate'
    New-Item -Path $pol -Force | Out-Null
    New-ItemProperty -Path $pol -Name "Install$EdgeAppId" -Value 0 -PropertyType DWord -Force | Out-Null

    $eu = 'HKLM:\SOFTWARE\Microsoft\EdgeUpdate'
    New-Item -Path $eu -Force | Out-Null
    New-ItemProperty -Path $eu -Name DoNotUpdateToEdgeWithChromium -Value 1 -PropertyType DWord -Force | Out-Null
    Write-Host '    [OK]   Edge reinstall blocked'
}

# --- Leftovers: autostart and shortcuts -----------------------------------------
$run = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$autoLaunch = @((Get-Item $run).Property | Where-Object { $_ -like 'MicrosoftEdgeAutoLaunch_*' })
foreach ($name in $autoLaunch) {
    if ($PSCmdlet.ShouldProcess("$run\$name", 'Remove Edge autostart')) {
        Remove-ItemProperty -Path $run -Name $name
        Write-Host "    [OK]   Autostart $name removed"
    }
}

$links = @("$env:PUBLIC\Desktop", "$env:USERPROFILE\Desktop",
           "$env:ProgramData\Microsoft\Windows\Start Menu\Programs",
           "$env:APPDATA\Microsoft\Windows\Start Menu\Programs",
           "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar") |
    ForEach-Object { Get-ChildItem -Path $_ -Filter 'Microsoft Edge*.lnk' -ErrorAction SilentlyContinue }
foreach ($link in $links) {
    if ($PSCmdlet.ShouldProcess($link.FullName, 'Remove shortcut')) {
        Remove-Item -LiteralPath $link.FullName -Force
    }
}
