<#
.SYNOPSIS
    Master script: applies all Windows 11 customizations in this repo.

.DESCRIPTION
    1. Backs up every registry key touched by registry\*.reg into backups\<timestamp>\
    2. Imports every registry\*.reg file (alphabetical order)
    3. Runs every scripts\*.ps1 file (alphabetical order)
    4. Restarts Explorer so the changes take effect

    Files whose name starts with "_" are skipped (templates, disabled tweaks).
    Each run writes a log to logs\.

.PARAMETER NoRestartExplorer
    Do not restart Explorer at the end.

.PARAMETER NoPause
    Do not wait for a key press at the end (for unattended runs).

.EXAMPLE
    .\Customize.ps1 -WhatIf
    Shows what would be done without changing anything.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$NoRestartExplorer,
    [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
$Root      = $PSScriptRoot
$Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'

# --- Elevation ---------------------------------------------------------------
# Some tweaks write to HKLM, so relaunch as admin if needed.
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'Requesting administrator rights...'
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    if ($NoRestartExplorer) { $argList += '-NoRestartExplorer' }
    if ($NoPause)           { $argList += '-NoPause' }
    if ($WhatIfPreference)  { $argList += '-WhatIf' }
    Start-Process -FilePath powershell.exe -Verb RunAs -ArgumentList $argList
    return
}

# --- Logging -----------------------------------------------------------------
$logDir = Join-Path $Root 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
Start-Transcript -Path (Join-Path $logDir "customize-$Timestamp.log") | Out-Null

$failures = New-Object System.Collections.Generic.List[string]

function Write-Step([string]$Text) {
    Write-Host ''
    Write-Host "=== $Text ===" -ForegroundColor Cyan
}

function Get-ActiveFiles([string]$Folder, [string]$Filter) {
    $path = Join-Path $Root $Folder
    if (-not (Test-Path $path)) { return @() }
    Get-ChildItem -Path $path -Filter $Filter -File |
        Where-Object { -not $_.Name.StartsWith('_') } |
        Sort-Object Name
}

# Runs reg.exe without letting its stderr chatter turn into PowerShell errors.
function Invoke-Reg([string[]]$Arguments) {
    $p = Start-Process -FilePath reg.exe -ArgumentList $Arguments -Wait -PassThru -WindowStyle Hidden
    return $p.ExitCode
}

# Some keys (e.g. Windows Search) are writable only by SYSTEM, not by admins.
# Imports the file through a one-off scheduled task running as SYSTEM.
function Invoke-RegImportAsSystem([IO.FileInfo]$RegFile) {
    $taskName = "WinCustAdp-RegImport-$Timestamp"
    $action    = New-ScheduledTaskAction -Execute 'reg.exe' -Argument "import `"$($RegFile.FullName)`""
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Force | Out-Null
    try {
        Start-ScheduledTask -TaskName $taskName
        $deadline = (Get-Date).AddSeconds(30)
        do {
            Start-Sleep -Milliseconds 500
            $state = (Get-ScheduledTask -TaskName $taskName).State
            $info  = Get-ScheduledTaskInfo -TaskName $taskName
            # 267011 = task has not run yet
        } while (($state -eq 'Running' -or $info.LastTaskResult -eq 267011) -and (Get-Date) -lt $deadline)
        return $info.LastTaskResult
    } finally {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    }
}

function Test-RunAsSystem([IO.FileInfo]$RegFile) {
    return [bool](Select-String -Path $RegFile.FullName -Pattern '^;\s*RunAs:\s*SYSTEM' -Quiet)
}

function Backup-RegFileKeys([IO.FileInfo]$RegFile, [string]$BackupDir) {
    # Key lines look like [HKEY_...]; deletions look like [-HKEY_...]
    $keys = Select-String -Path $RegFile.FullName -Pattern '^\[-?(HKEY_[^\]]+)\]' |
        ForEach-Object { $_.Matches[0].Groups[1].Value } |
        Select-Object -Unique

    foreach ($key in $keys) {
        $safeName = $key -replace '[\\/:*?"<>| ]', '_'
        $target   = Join-Path $BackupDir "$safeName.reg"
        if (Test-Path $target) { continue }
        # Exit code 1 means the key does not exist yet - nothing to back up.
        Invoke-Reg @('export', "`"$key`"", "`"$target`"", '/y') | Out-Null
    }
}

# --- 1+2: Registry -----------------------------------------------------------
$regFiles = @(Get-ActiveFiles 'registry' '*.reg')
Write-Step "Registry ($($regFiles.Count) files)"

if ($regFiles.Count -gt 0) {
    $backupDir = Join-Path $Root "backups\$Timestamp"
    if ($PSCmdlet.ShouldProcess($backupDir, 'Back up registry keys')) {
        New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
        foreach ($file in $regFiles) { Backup-RegFileKeys $file $backupDir }
        Write-Host "Backup: $backupDir"
    }

    foreach ($file in $regFiles) {
        if (-not $PSCmdlet.ShouldProcess($file.Name, 'Import registry file')) { continue }
        $asSystem = Test-RunAsSystem $file
        if ($asSystem) {
            $exit = Invoke-RegImportAsSystem $file
        } else {
            $exit = Invoke-Reg @('import', "`"$($file.FullName)`"")
        }
        if ($exit -eq 0) {
            Write-Host "  [OK]   $($file.Name)$(if ($asSystem) { ' (as SYSTEM)' })" -ForegroundColor Green
        } else {
            Write-Host "  [FAIL] $($file.Name) (exit code $exit)" -ForegroundColor Red
            $failures.Add("registry\$($file.Name)")
        }
    }
}

# --- 3: Scripts --------------------------------------------------------------
$scriptFiles = @(Get-ActiveFiles 'scripts' '*.ps1')
Write-Step "Scripts ($($scriptFiles.Count) files)"

foreach ($file in $scriptFiles) {
    if (-not $PSCmdlet.ShouldProcess($file.Name, 'Run script')) { continue }
    try {
        & $file.FullName
        Write-Host "  [OK]   $($file.Name)" -ForegroundColor Green
    } catch {
        Write-Host "  [FAIL] $($file.Name): $($_.Exception.Message)" -ForegroundColor Red
        $failures.Add("scripts\$($file.Name)")
    }
}

# --- 4: Restart Explorer -----------------------------------------------------
if (-not $NoRestartExplorer -and $PSCmdlet.ShouldProcess('explorer.exe', 'Restart')) {
    Write-Step 'Restarting Explorer'
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    # Windows normally restarts the shell by itself; start it if it did not.
    if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) {
        Start-Process explorer.exe
    }
}

# --- Summary -----------------------------------------------------------------
Write-Step 'Done'
if ($failures.Count -eq 0) {
    Write-Host 'All customizations applied.' -ForegroundColor Green
} else {
    Write-Host "$($failures.Count) item(s) failed:" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
}

Stop-Transcript | Out-Null

if (-not $NoPause) {
    Write-Host ''
    Read-Host 'Press Enter to close'
}
