# DeepCode CLI installer for Windows (Windows PowerShell 5.1+ or PowerShell 7).
#
#   irm https://braincrew-lab.github.io/deepwork-public/deepcode/install.ps1 | iex
#
# Offline / closed network: download the Windows archive and run
#   powershell -ExecutionPolicy Bypass -File install.ps1 -Archive .\deepcode-<version>-win32-x64.zip
#
# Environment:
#   DEEPCODE_UPDATE_URL    release manifest (default: the public latest.json);
#                          point it at an internal mirror, `deepcode update` uses it too
#   DEEPCODE_INSTALL_ROOT  install root (default: %LOCALAPPDATA%\DeepCode)
#
# Layout (shared with `deepcode update`, scripts/deepcode-cli-updater.cjs):
#   <root>\versions\<version>\{node,app}  <root>\current  <root>\bin\deepcode.cmd

param([string]$Archive = "")

# A function scope keeps these preferences out of the caller's session under `irm | iex`.
function Install-DeepCode([string]$Archive) {
$ErrorActionPreference = "Stop"
# The progress bar slows Invoke-WebRequest down by an order of magnitude on 5.1.
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$manifestUrl = if ($env:DEEPCODE_UPDATE_URL) { $env:DEEPCODE_UPDATE_URL } else { "https://braincrew-lab.github.io/deepwork-public/deepcode/latest.json" }
$root = if ($env:DEEPCODE_INSTALL_ROOT) { $env:DEEPCODE_INSTALL_ROOT } else { Join-Path $env:LOCALAPPDATA "DeepCode" }
$binDir = Join-Path $root "bin"
$versionsDir = Join-Path $root "versions"
# Built-in bsdtar (Windows 10 1803+); a Git for Windows tar earlier on PATH cannot read zip.
$tar = Join-Path $env:SystemRoot "System32\tar.exe"

function Fail([string]$message) {
  Write-Host "deepcode install: $message" -ForegroundColor Red
  throw $message
}

$tempDir = Join-Path ([IO.Path]::GetTempPath()) ("deepcode-install-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
try {
  if (-not $Archive) {
    # Windows on Arm runs the x64 build under emulation.
    $platform = "win32-x64"
    Write-Host "Fetching the latest DeepCode release for $platform..."
    $manifest = Invoke-RestMethod -UseBasicParsing -Uri $manifestUrl
    $asset = $manifest.platforms.$platform
    if (-not $asset) { Fail "the release has no build for $platform" }
    # Asset URLs may be relative to the manifest (internal mirrors).
    $url = ([Uri]::new([Uri]$manifestUrl, [string]$asset.url)).AbsoluteUri
    $Archive = Join-Path $tempDir "deepcode.zip"
    Write-Host "Downloading DeepCode $($manifest.version)..."
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $Archive
    $actual = (Get-FileHash -Algorithm SHA256 -Path $Archive).Hash.ToLowerInvariant()
    if ($actual -ne ([string]$asset.sha256).ToLowerInvariant()) { Fail "checksum mismatch for $url" }
  }
  if (-not (Test-Path -LiteralPath $Archive -PathType Leaf)) { Fail "archive not found: $Archive" }
  $Archive = (Resolve-Path -LiteralPath $Archive).Path

  New-Item -ItemType Directory -Force -Path $versionsDir, $binDir | Out-Null
  $stage = Join-Path $versionsDir (".staging-" + $PID)
  if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $stage | Out-Null
  if (Test-Path -LiteralPath $tar) {
    & $tar -xf $Archive -C $stage
    if ($LASTEXITCODE -ne 0) { Fail "could not extract $Archive" }
  } else {
    Expand-Archive -LiteralPath $Archive -DestinationPath $stage -Force
  }
  $packageJson = Join-Path $stage "app\package.json"
  if (-not (Test-Path (Join-Path $stage "node\node.exe")) -or -not (Test-Path $packageJson)) {
    Fail "$Archive is not a DeepCode standalone build"
  }
  $version = (Get-Content -Raw -LiteralPath $packageJson | ConvertFrom-Json).version
  if (-not $version) { Fail "could not read the version from $Archive" }

  $target = Join-Path $versionsDir $version
  if (Test-Path -LiteralPath $target) {
    try {
      Remove-Item -LiteralPath $target -Recurse -Force
    } catch {
      # That version is running right now; its files are already in place.
      Remove-Item -LiteralPath $stage -Recurse -Force
      $stage = $null
    }
  }
  if ($stage) { Move-Item -LiteralPath $stage -Destination $target }

  $pointer = Join-Path $root "current.tmp"
  [IO.File]::WriteAllText($pointer, $version)
  Move-Item -LiteralPath $pointer -Destination (Join-Path $root "current") -Force

  # The shim resolves the active version on every launch, so `deepcode update`
  # only swaps <root>\current and never rewrites this file.
  $shim = @'
@echo off
setlocal
for %%I in ("%~dp0..") do set "DEEPCODE_INSTALL_ROOT=%%~fI"
set /p DEEPCODE_ACTIVE_VERSION=<"%DEEPCODE_INSTALL_ROOT%\current"
"%DEEPCODE_INSTALL_ROOT%\versions\%DEEPCODE_ACTIVE_VERSION%\node\node.exe" "%DEEPCODE_INSTALL_ROOT%\versions\%DEEPCODE_ACTIVE_VERSION%\app\bin\deepcode.cjs" %*
exit /b %ERRORLEVEL%
'@
  [IO.File]::WriteAllText((Join-Path $binDir "deepcode.cmd"), $shim.Replace("`r`n", "`n").Replace("`n", "`r`n"))

  Get-ChildItem -LiteralPath $versionsDir -Directory | Where-Object { $_.Name -ne $version } | ForEach-Object {
    try { Remove-Item -LiteralPath $_.FullName -Recurse -Force } catch { }
  }

  $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
  $entries = @($userPath -split ";" | Where-Object { $_ })
  if ($entries -notcontains $binDir) {
    [Environment]::SetEnvironmentVariable("Path", (($entries + $binDir) -join ";"), "User")
  }
  if (@($env:Path -split ";") -notcontains $binDir) { $env:Path = "$env:Path;$binDir" }

  Write-Host "DeepCode $version installed: $binDir\deepcode.cmd" -ForegroundColor Green
  Write-Host "Run: deepcode   (other terminals that were already open need a restart)"
} finally {
  Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
}

Install-DeepCode -Archive $Archive
