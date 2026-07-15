#requires -Version 5.1

<#
.SYNOPSIS
Resets a Windows test PC so the next DeepWork installation behaves like a first install.

.DESCRIPTION
The default reset removes the current user's DeepWork package, packaged service,
app data, VM cache, execution history, Chrome native-host registration, and local
DeepWork test certificates.

With -ResetWindowsVirtualization, it also stops the Windows HCS/HNS services and
disables VirtualMachinePlatform. That mode requires a reboot and intentionally
returns the PC to the state where DeepWork must enable VMP during first-run setup.

The script does NOT delete the Windows vmcompute/HNS/vfpext components, disable
the full Hyper-V role, clear Windows event logs, or touch unrelated Hyper-V VMs.

.EXAMPLE
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows-first-install-reset.ps1 -WhatIf -ResetWindowsVirtualization

.EXAMPLE
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows-first-install-reset.ps1 -ConfirmFactoryReset -ResetWindowsVirtualization -Restart

.EXAMPLE
# Only when this dedicated test PC has an orphan vmwp process or WSL/Docker is intentionally disposable.
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows-first-install-reset.ps1 -ConfirmFactoryReset -ResetWindowsVirtualization -ForceSharedVirtualizationReset -Restart
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Medium")]
param(
  [string] $PackageName = "Braincrew.DeepWork",

  [string] $ServiceName = "DeepWorkVMService",

  [switch] $ConfirmFactoryReset,

  [switch] $ResetWindowsVirtualization,

  [switch] $ForceSharedVirtualizationReset,

  [switch] $KeepLocalTestCertificates,

  [switch] $Restart,

  [string] $EvidencePath,

  [int] $TimeoutSeconds = 90
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Avoid noisy module alias-registration WhatIf messages. These imports only
# affect this PowerShell process; destructive operations remain under ShouldProcess.
$requestedWhatIf = [bool] $WhatIfPreference
$WhatIfPreference = $false
Import-Module Appx -ErrorAction Stop
Import-Module CimCmdlets -ErrorAction Stop
Import-Module Dism -ErrorAction Stop
$WhatIfPreference = $requestedWhatIf

$DeepWorkChromeNativeHostKey =
  "Registry::HKEY_CURRENT_USER\Software\Google\Chrome\NativeMessagingHosts\com.example.chrome_bridge"
$DeepWorkVsockKey =
  "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Virtualization\GuestCommunicationServices\00004457-FACB-11E6-BD58-64006A7986D3"
$DeepWorkVsockElementName = "DeepWork Windows secure VM bridge"
$LocalTestCertificateFriendlyName = "DeepWork Local MSIX Test Signing"
$script:Actions = [System.Collections.Generic.List[object]]::new()

function Write-ResetStep {
  param([string] $Message)
  Write-Host "[DeepWorkFirstInstallReset] $Message"
}

function Add-ResetAction {
  param(
    [string] $Action,
    [string] $Target,
    [string] $Result,
    [string] $Detail = ""
  )
  $script:Actions.Add([ordered]@{
      action = $Action
      target = $Target
      result = $Result
      detail = $Detail
    })
}

function Test-IsAdministrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-ResetPreconditions {
  if (-not [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
      [System.Runtime.InteropServices.OSPlatform]::Windows
    )) {
    throw "DeepWork Windows first-install reset must run on Windows."
  }
  if (-not $WhatIfPreference -and -not $ConfirmFactoryReset) {
    throw "Destructive reset requires -ConfirmFactoryReset. Run with -WhatIf first."
  }
  if (-not $WhatIfPreference -and -not (Test-IsAdministrator)) {
    throw "Run this script from an elevated PowerShell window (Run as administrator)."
  }
  if ($Restart -and -not $ResetWindowsVirtualization) {
    Write-Warning "-Restart was supplied without -ResetWindowsVirtualization; a reboot is normally unnecessary."
  }
}

function Get-PackageEvidence {
  return @(
    Get-AppxPackage -Name $PackageName -ErrorAction SilentlyContinue |
      Select-Object Name, Version, PackageFullName, InstallLocation
  )
}

function Get-ServiceEvidence {
  param([string] $Name)
  $service = Get-CimInstance Win32_Service -Filter "Name='$Name'" -ErrorAction SilentlyContinue
  if (-not $service) {
    return [ordered]@{ name = $Name; state = "missing" }
  }
  return [ordered]@{
    name = $Name
    state = [string] $service.State
    startMode = [string] $service.StartMode
    startName = [string] $service.StartName
    processId = [int] $service.ProcessId
  }
}

function Get-VmpEvidence {
  try {
    $feature = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -ErrorAction Stop
    return [ordered]@{
      featureName = [string] $feature.FeatureName
      state = [string] $feature.State
      restartNeeded = [string] $feature.RestartNeeded
    }
  } catch {
    return [ordered]@{
      featureName = "VirtualMachinePlatform"
      state = "unknown"
      error = $_.Exception.Message
    }
  }
}

function Get-SharedVirtualizationConsumers {
  $consumerNames = @(
    "Docker Desktop",
    "com.docker.backend",
    "com.docker.build",
    "wsl",
    "wslhost",
    "wslservice"
  )
  return @(
    Get-Process -ErrorAction SilentlyContinue |
      Where-Object { $consumerNames -contains $_.ProcessName } |
      Select-Object -Property ProcessName, Id
  )
}

function Assert-NoSharedVirtualizationConsumers {
  if (-not $ResetWindowsVirtualization -or $ForceSharedVirtualizationReset) {
    return
  }
  $consumers = @(Get-SharedVirtualizationConsumers)
  if ($consumers.Count -gt 0) {
    $summary = ($consumers | ForEach-Object { "$($_.ProcessName)($($_.Id))" }) -join ", "
    throw "VMP reset would interrupt WSL/Docker processes: $summary. Close them or, on a dedicated disposable test PC, pass -ForceSharedVirtualizationReset."
  }
}

function Stop-DeepWorkProcesses {
  $processes = @(Get-Process -Name "DeepWork" -ErrorAction SilentlyContinue)
  foreach ($process in $processes) {
    $target = "$($process.ProcessName) pid=$($process.Id)"
    if ($PSCmdlet.ShouldProcess($target, "Stop DeepWork desktop process")) {
      Stop-Process -Id $process.Id -Force -ErrorAction Stop
      Add-ResetAction -Action "stop-process" -Target $target -Result "completed"
    } else {
      Add-ResetAction -Action "stop-process" -Target $target -Result "planned"
    }
  }
}

function Stop-NamedService {
  param(
    [string] $Name,
    [switch] $AllowMissing
  )
  $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
  if (-not $service) {
    if (-not $AllowMissing) {
      throw "Required Windows service is missing: $Name"
    }
    Add-ResetAction -Action "stop-service" -Target $Name -Result "skipped" -Detail "missing"
    return
  }
  if ($service.Status -eq "Stopped") {
    Add-ResetAction -Action "stop-service" -Target $Name -Result "skipped" -Detail "already stopped"
    return
  }
  if ($PSCmdlet.ShouldProcess($Name, "Stop Windows service")) {
    Stop-Service -Name $Name -Force -ErrorAction Stop
    $service.WaitForStatus("Stopped", [TimeSpan]::FromSeconds([Math]::Max(1, $TimeoutSeconds)))
    Add-ResetAction -Action "stop-service" -Target $Name -Result "completed"
  } else {
    Add-ResetAction -Action "stop-service" -Target $Name -Result "planned"
  }
}

function Remove-DeepWorkPackages {
  $packages = @(Get-AppxPackage -Name $PackageName -ErrorAction SilentlyContinue)
  foreach ($package in $packages) {
    if ($PSCmdlet.ShouldProcess($package.PackageFullName, "Remove installed DeepWork package")) {
      Remove-AppxPackage -Package $package.PackageFullName -ErrorAction Stop
      Add-ResetAction -Action "remove-package" -Target $package.PackageFullName -Result "completed"
    } else {
      Add-ResetAction -Action "remove-package" -Target $package.PackageFullName -Result "planned"
    }
  }
  if ($WhatIfPreference -or $packages.Count -eq 0) {
    return
  }

  $deadline = (Get-Date).AddSeconds([Math]::Max(1, $TimeoutSeconds))
  do {
    if (@(Get-AppxPackage -Name $PackageName -ErrorAction SilentlyContinue).Count -eq 0) {
      return
    }
    Start-Sleep -Milliseconds 500
  } while ((Get-Date) -lt $deadline)
  throw "DeepWork package did not disappear within $TimeoutSeconds seconds."
}

function Get-DeepWorkDataPaths {
  $paths = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
  )
  $candidates = @(
    (Join-Path $env:USERPROFILE ".deepwork")
  )
  foreach ($root in @($env:APPDATA, $env:LOCALAPPDATA)) {
    if (-not $root) {
      continue
    }
    foreach ($name in @("deepwork", "Deepwork", "DeepWork")) {
      $candidates += Join-Path $root $name
    }
  }
  foreach ($candidate in $candidates) {
    if ($candidate) {
      [void] $paths.Add([IO.Path]::GetFullPath($candidate))
    }
  }

  $packageRoot = Join-Path $env:LOCALAPPDATA "Packages"
  if (Test-Path -LiteralPath $packageRoot -PathType Container) {
    Get-ChildItem -LiteralPath $packageRoot -Directory -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -like "$PackageName`_*" } |
      ForEach-Object { [void] $paths.Add($_.FullName) }
  }
  return @($paths)
}

function Remove-DeepWorkData {
  $allowedPaths = @(Get-DeepWorkDataPaths)
  foreach ($path in $allowedPaths) {
    if (-not (Test-Path -LiteralPath $path)) {
      continue
    }
    $resolved = [IO.Path]::GetFullPath($path)
    if ($allowedPaths -notcontains $resolved) {
      throw "Refusing to remove path outside the exact DeepWork reset allowlist: $resolved"
    }
    if ($PSCmdlet.ShouldProcess($resolved, "Recursively remove DeepWork app data, history, and VM cache")) {
      $item = Get-Item -LiteralPath $resolved -Force
      if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        Remove-Item -LiteralPath $resolved -Force
      } else {
        Remove-Item -LiteralPath $resolved -Recurse -Force
      }
      Add-ResetAction -Action "remove-data" -Target $resolved -Result "completed"
    } else {
      Add-ResetAction -Action "remove-data" -Target $resolved -Result "planned"
    }
  }
}

function Remove-DeepWorkRegistryState {
  if (Test-Path -LiteralPath $DeepWorkChromeNativeHostKey) {
    if ($PSCmdlet.ShouldProcess($DeepWorkChromeNativeHostKey, "Remove DeepWork Chrome native-host registration")) {
      Remove-Item -LiteralPath $DeepWorkChromeNativeHostKey -Recurse -Force
      Add-ResetAction -Action "remove-registry-key" -Target $DeepWorkChromeNativeHostKey -Result "completed"
    } else {
      Add-ResetAction -Action "remove-registry-key" -Target $DeepWorkChromeNativeHostKey -Result "planned"
    }
  }

  if ($ResetWindowsVirtualization -and (Test-Path -LiteralPath $DeepWorkVsockKey)) {
    $registryKey = Get-Item -LiteralPath $DeepWorkVsockKey -ErrorAction Stop
    $elementName = $registryKey.GetValue("ElementName", $null)
    if ($elementName -eq $DeepWorkVsockElementName) {
      if ($PSCmdlet.ShouldProcess($DeepWorkVsockKey, "Remove DeepWork-owned HVSock registration")) {
        Remove-Item -LiteralPath $DeepWorkVsockKey -Recurse -Force
        Add-ResetAction -Action "remove-registry-key" -Target $DeepWorkVsockKey -Result "completed"
      } else {
        Add-ResetAction -Action "remove-registry-key" -Target $DeepWorkVsockKey -Result "planned"
      }
    } else {
      Add-ResetAction -Action "remove-registry-key" -Target $DeepWorkVsockKey -Result "skipped" -Detail "ElementName is not DeepWork-owned"
    }
  }
}

function Remove-DeepWorkLocalTestCertificates {
  if ($KeepLocalTestCertificates) {
    Add-ResetAction -Action "remove-test-certificate" -Target $LocalTestCertificateFriendlyName -Result "skipped" -Detail "KeepLocalTestCertificates"
    return
  }
  foreach ($store in @("Cert:\CurrentUser\My", "Cert:\CurrentUser\TrustedPeople", "Cert:\LocalMachine\My", "Cert:\LocalMachine\TrustedPeople")) {
    if (-not (Test-Path -LiteralPath $store)) {
      continue
    }
    $certificates = @(
      Get-ChildItem -LiteralPath $store -ErrorAction SilentlyContinue |
        Where-Object {
          $_.FriendlyName -eq $LocalTestCertificateFriendlyName -and
          $_.Issuer -eq $_.Subject
        }
    )
    foreach ($certificate in $certificates) {
      $target = "$store\$($certificate.Thumbprint)"
      if ($PSCmdlet.ShouldProcess($target, "Remove DeepWork self-signed local test certificate")) {
        Remove-Item -LiteralPath $certificate.PSPath -Force
        Add-ResetAction -Action "remove-test-certificate" -Target $target -Result "completed"
      } else {
        Add-ResetAction -Action "remove-test-certificate" -Target $target -Result "planned"
      }
    }
  }
}

function Reset-WindowsVirtualizationPlatform {
  if (-not $ResetWindowsVirtualization) {
    return
  }

  # After DeepWorkVMService has stopped, any remaining vmwp process belongs to
  # an orphaned compute system or another VM product. Never clear it implicitly.
  $vmWorkers = @(Get-Process -Name "vmwp" -ErrorAction SilentlyContinue)
  if ($vmWorkers.Count -gt 0 -and -not $ForceSharedVirtualizationReset) {
    $summary = ($vmWorkers | ForEach-Object { "vmwp($($_.Id))" }) -join ", "
    if ($WhatIfPreference) {
      Add-ResetAction -Action "verify-no-shared-vm" -Target $summary -Result "planned" -Detail "Recheck after DeepWork stops during the real reset"
    } else {
      throw "VM worker processes remain after DeepWork stopped: $summary. Refusing to reset shared HCS state. On a dedicated disposable test PC only, pass -ForceSharedVirtualizationReset."
    }
  }

  Stop-NamedService -Name "vmcompute" -AllowMissing
  Stop-NamedService -Name "hns" -AllowMissing

  try {
    $feature = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -ErrorAction Stop
  } catch {
    if ($WhatIfPreference) {
      Add-ResetAction `
        -Action "disable-feature" `
        -Target "VirtualMachinePlatform" `
        -Result "planned" `
        -Detail "Current state requires an elevated query: $($_.Exception.Message)"
      return
    }
    throw
  }
  if ([string] $feature.State -match "^Disabled") {
    Add-ResetAction -Action "disable-feature" -Target "VirtualMachinePlatform" -Result "skipped" -Detail ([string] $feature.State)
    return
  }
  if ($PSCmdlet.ShouldProcess("VirtualMachinePlatform", "Disable Windows optional feature; reboot required")) {
    $result = Disable-WindowsOptionalFeature `
      -Online `
      -FeatureName VirtualMachinePlatform `
      -NoRestart `
      -ErrorAction Stop
    Add-ResetAction `
      -Action "disable-feature" `
      -Target "VirtualMachinePlatform" `
      -Result "completed" `
      -Detail "RestartNeeded=$($result.RestartNeeded)"
  } else {
    Add-ResetAction -Action "disable-feature" -Target "VirtualMachinePlatform" -Result "planned"
  }
}

function Assert-PostResetState {
  if ($WhatIfPreference) {
    return
  }
  $remainingPackages = @(Get-AppxPackage -Name $PackageName -ErrorAction SilentlyContinue)
  if ($remainingPackages.Count -gt 0) {
    throw "Post-reset verification failed: DeepWork package is still installed."
  }
  if (Get-Service -Name $ServiceName -ErrorAction SilentlyContinue) {
    throw "Post-reset verification failed: $ServiceName is still registered."
  }
  $remainingPaths = @(Get-DeepWorkDataPaths | Where-Object { Test-Path -LiteralPath $_ })
  if ($remainingPaths.Count -gt 0) {
    throw "Post-reset verification failed: DeepWork data remains: $($remainingPaths -join ', ')"
  }
}

function Resolve-EvidencePath {
  if ($EvidencePath) {
    return [IO.Path]::GetFullPath($EvidencePath)
  }
  $root = if ($env:PUBLIC) { Join-Path $env:PUBLIC "Documents" } else { $env:TEMP }
  return Join-Path $root ("DeepWork-first-install-reset-{0}.json" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
}

function Write-ResetEvidence {
  param(
    [hashtable] $Report,
    [string] $Path
  )
  $parent = Split-Path -Parent $Path
  if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }
  $Report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
  Write-ResetStep "Evidence written: $Path"
}

Assert-ResetPreconditions
Assert-NoSharedVirtualizationConsumers

$resolvedEvidencePath = Resolve-EvidencePath
$report = [ordered]@{
  schemaVersion = 1
  startedAt = (Get-Date).ToUniversalTime().ToString("o")
  computerName = $env:COMPUTERNAME
  userName = [Security.Principal.WindowsIdentity]::GetCurrent().Name
  options = [ordered]@{
    whatIf = [bool] $WhatIfPreference
    resetWindowsVirtualization = [bool] $ResetWindowsVirtualization
    forceSharedVirtualizationReset = [bool] $ForceSharedVirtualizationReset
    keepLocalTestCertificates = [bool] $KeepLocalTestCertificates
    restart = [bool] $Restart
  }
  before = [ordered]@{
    packages = @(Get-PackageEvidence)
    deepWorkService = Get-ServiceEvidence -Name $ServiceName
    vmcompute = Get-ServiceEvidence -Name "vmcompute"
    hns = Get-ServiceEvidence -Name "hns"
    virtualMachinePlatform = Get-VmpEvidence
    sharedVirtualizationConsumers = @(Get-SharedVirtualizationConsumers)
    dataPaths = @(Get-DeepWorkDataPaths | Where-Object { Test-Path -LiteralPath $_ })
  }
  actions = $script:Actions
  status = "running"
}

try {
  Stop-DeepWorkProcesses
  Stop-NamedService -Name $ServiceName -AllowMissing
  Remove-DeepWorkPackages
  Remove-DeepWorkRegistryState
  Remove-DeepWorkLocalTestCertificates
  Remove-DeepWorkData
  Reset-WindowsVirtualizationPlatform
  Assert-PostResetState

  $report.status = if ($WhatIfPreference) { "planned" } else { "completed" }
} catch {
  $report.status = "failed"
  $report.error = $_.Exception.Message
  throw
} finally {
  $report.completedAt = (Get-Date).ToUniversalTime().ToString("o")
  $report.after = [ordered]@{
    packages = @(Get-PackageEvidence)
    deepWorkService = Get-ServiceEvidence -Name $ServiceName
    vmcompute = Get-ServiceEvidence -Name "vmcompute"
    hns = Get-ServiceEvidence -Name "hns"
    virtualMachinePlatform = Get-VmpEvidence
    dataPaths = @(Get-DeepWorkDataPaths | Where-Object { Test-Path -LiteralPath $_ })
  }
  if (-not $WhatIfPreference) {
    Write-ResetEvidence -Report $report -Path $resolvedEvidencePath
  }
}

if ($WhatIfPreference) {
  Write-ResetStep "WhatIf completed. No reset evidence file was written and no state should have changed."
  $report | ConvertTo-Json -Depth 8
  return
}

Write-ResetStep "Reset completed. Install DeepWork 0.6.5 after the requested reboot."
if ($ResetWindowsVirtualization -and -not $Restart) {
  Write-Warning "VirtualMachinePlatform was disabled with -NoRestart. Reboot Windows before installing/running 0.6.5."
}
if ($Restart) {
  if ($PSCmdlet.ShouldProcess($env:COMPUTERNAME, "Restart Windows now")) {
    Restart-Computer -Force
  }
}
