<#
.SYNOPSIS
  Fixes NVIDIA "Code 43" on an eGPU attached through a PCIe port without hot-plug
  support (for example a laptop M.2 slot -> OCuLink adapter -> OCuLink dock).

.DESCRIPTION
  Writes RM1774520 = 1 (REG_DWORD) to the driver key of every instance of the affected
  NVIDIA GPU model, including instances created by other M.2 slots that are not
  connected right now. This is the same setting egpu.io's nvidia-error43-fixer applies.
  Only built-in Windows cmdlets are used; nothing is downloaded or installed.

  After running it: shut the laptop down completely, power on the dock and GPU first,
  then power on the laptop.

.PARAMETER DeviceId
  Optional hardware id prefix, e.g. 'PCI\VEN_10DE&DEV_2204' (RTX 3090).
  Default: every NVIDIA display device that currently reports Code 43.

.PARAMETER DryRun
  Show what would be changed without writing anything. Does not need admin rights.

.PARAMETER NoPause
  Do not wait for Enter at the end (for use from scripts).

.EXAMPLE
  .\Fix-NvidiaEgpuCode43.ps1 -DryRun
.EXAMPLE
  .\Fix-NvidiaEgpuCode43.ps1 -DeviceId 'PCI\VEN_10DE&DEV_2204'
#>
param(
  [string]$DeviceId,
  [switch]$DryRun,
  [switch]$NoPause
)

$ValueName = 'RM1774520'

function Test-Admin {
  ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Stop-Script([int]$code) {
  if (-not $NoPause -and -not $DryRun) { Read-Host 'Press Enter to exit' | Out-Null }
  exit $code
}

# Writing to HKLM needs admin rights: relaunch elevated (UAC prompt).
if (-not $DryRun -and -not (Test-Admin)) {
  $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
  if ($DeviceId) { $argList += @('-DeviceId', "`"$DeviceId`"") }
  if ($NoPause) { $argList += '-NoPause' }
  Start-Process powershell.exe -Verb RunAs -ArgumentList $argList
  exit
}

# 1. Which GPU model(s) to fix
if ($DeviceId) {
  $models = @($DeviceId.TrimEnd('*'))
} else {
  $broken = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object {
      $_.InstanceId -like 'PCI\VEN_10DE&DEV_*' -and $_.Class -eq 'Display' -and
      (Get-PnpDeviceProperty -InstanceId $_.InstanceId -KeyName DEVPKEY_Device_ProblemCode -ErrorAction SilentlyContinue).Data -eq 43
    })
  $models = @($broken | ForEach-Object {
      if ($_.InstanceId -match '^(PCI\\VEN_10DE&DEV_[0-9A-Fa-f]{4})') { $Matches[1].ToUpper() }
    } | Sort-Object -Unique)
}

if ($models.Count -eq 0) {
  Write-Host 'No NVIDIA GPU reporting Code 43 was found.' -ForegroundColor Yellow
  Write-Host 'Make sure the dock and GPU are powered on BEFORE the laptop boots, and that the'
  Write-Host 'regular NVIDIA desktop driver is installed. Or pass -DeviceId, e.g. ''PCI\VEN_10DE&DEV_2204''.'
  Stop-Script 1
}

# 2. Every instance of those models (each M.2 slot creates its own instance and driver key)
$changed = 0
foreach ($model in $models) {
  Write-Host "GPU model: $model" -ForegroundColor Cyan
  $instances = @(Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -like "$model*" })
  foreach ($dev in $instances) {
    $driverKey = (Get-PnpDeviceProperty -InstanceId $dev.InstanceId -KeyName DEVPKEY_Device_Driver -ErrorAction SilentlyContinue).Data
    if (-not $driverKey) {
      Write-Host "  skipped (no driver installed): $($dev.InstanceId)" -ForegroundColor DarkGray
      continue
    }
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\$driverKey"
    $current = (Get-ItemProperty -Path $regPath -Name $ValueName -ErrorAction SilentlyContinue).$ValueName
    $currentText = if ($null -eq $current) { 'not set' } else { "$current" }
    $state = if ($dev.Present) { 'connected' } else { 'not connected' }

    if ($DryRun) {
      Write-Host ("  [dry-run] {0}  {1}={2}  ({3}, status: {4})" -f $driverKey, $ValueName, $currentText, $state, $dev.Status)
      continue
    }
    New-ItemProperty -Path $regPath -Name $ValueName -PropertyType DWord -Value 1 -Force | Out-Null
    $after = (Get-ItemProperty -Path $regPath -Name $ValueName).$ValueName
    Write-Host ("  OK  {0}  {1}={2}  (was: {3}; {4})" -f $driverKey, $ValueName, $after, $currentText, $state) -ForegroundColor Green
    $changed++
  }
}

Write-Host ''
if ($DryRun) {
  Write-Host 'Dry run: nothing was changed.' -ForegroundColor Yellow
} elseif ($changed -gt 0) {
  Write-Host 'Done. Now SHUT DOWN the laptop completely (not restart).' -ForegroundColor Yellow
  Write-Host 'Power on the dock and GPU first, then the laptop. Code 43 should be gone.' -ForegroundColor Yellow
} else {
  Write-Host 'Nothing was changed (no instance with an installed driver).' -ForegroundColor Yellow
}
Stop-Script 0
