# DeepWork Windows 비공식(self-signed) 빌드 원클릭 설치 스크립트
#
# 이 스크립트는 테스트 인증서로 서명된 "비공식" 빌드를 설치합니다.
# 정식 배포(signed)는 이 스크립트 없이 APPX 다운로드 후 더블클릭으로 설치하세요.
#
# 사용법 — PowerShell(또는 터미널)에 아래 한 줄을 붙여넣고 Enter:
#   irm https://braincrew-lab.github.io/deepwork-public/install-windows.ps1 | iex
#
# 하는 일:
#   1. 최신 비공식(self-signed) APPX와 테스트 인증서(.cer)를 내려받고 SHA-256을 검증합니다.
#   2. 관리자 권한(UAC 승인 필요)으로 인증서를 신뢰 저장소 2곳(TrustedPeople, Root)에 등록합니다.
#   3. APPX를 설치하고 결과를 확인합니다.
#
# 주의: 테스트 인증서를 루트 신뢰 저장소에 등록하므로 사내/테스트 PC에서만 사용하세요.
#       정식 서명 릴리스로 전환되면 이 스크립트 없이 바로 설치할 수 있습니다.

function Save-DeepWorkFile {
  param(
    [Parameter(Mandatory = $true)][string]$Url,
    [Parameter(Mandatory = $true)][string]$Path,
    [string]$ExpectedSha256
  )

  if ($ExpectedSha256 -and (Test-Path -LiteralPath $Path)) {
    if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -eq $ExpectedSha256) {
      Write-Host "    이미 받은 파일 재사용: $(Split-Path -Leaf $Path)"
      return
    }
  }

  $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
  if ($curl) {
    & $curl.Source --location --fail --retry 3 --continue-at - --output $Path $Url
    if ($LASTEXITCODE -ne 0) {
      # 이어받기가 안 되는 경우(범위 미지원/기존 파일 손상)에는 처음부터 다시 받는다.
      Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
      & $curl.Source --location --fail --retry 3 --output $Path $Url
      if ($LASTEXITCODE -ne 0) { throw "다운로드에 실패했습니다: $Url" }
    }
  } else {
    $prevProgress = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue' # Invoke-WebRequest 진행률 표시가 다운로드 속도를 크게 떨어뜨림
    try {
      Invoke-WebRequest -Uri $Url -OutFile $Path -UseBasicParsing
    } finally {
      $ProgressPreference = $prevProgress
    }
  }

  if ($ExpectedSha256) {
    Write-Host "    SHA-256 검증 중: $(Split-Path -Leaf $Path)"
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($actual -ne $ExpectedSha256) {
      Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
      throw "다운로드한 파일의 SHA-256이 릴리스 정보와 다릅니다. 다시 실행해 주세요. (기대 $ExpectedSha256 / 실제 $actual)"
    }
  }
}

function Install-DeepWork {
  $ErrorActionPreference = 'Stop'
  try {
    [Net.ServicePointManager]::SecurityProtocol =
      [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
  } catch {}

  $baseUrl = 'https://braincrew-lab.github.io/deepwork-public'
  $packageName = 'Braincrew.DeepWork'

  if ($env:PROCESSOR_ARCHITECTURE -ne 'AMD64') {
    throw "이 설치 스크립트는 x64 Windows 전용입니다. (현재 아키텍처: $env:PROCESSOR_ARCHITECTURE)"
  }

  Write-Host ''
  Write-Host '==> 최신 릴리스 정보를 확인합니다...' -ForegroundColor Cyan
  $stable = Invoke-RestMethod -Uri "$baseUrl/releases/stable.json" -UseBasicParsing
  $win = $stable.downloads.windows
  if (-not $win -or -not $win.packageUrl -or -not $win.certificateUrl) {
    throw 'stable.json에서 Windows 다운로드 정보를 찾지 못했습니다. 페이지 관리자에게 문의해 주세요.'
  }
  $version = [string]$stable.windowsRelease.version
  $sizeGb = [math]::Round([double]$win.bytes / 1GB, 2)
  Write-Host ("    버전 v{0} - {1} ({2} GB)" -f $version, $win.artifactName, $sizeGb)
  Write-Host '    비공식(self-signed) 빌드입니다 — 정식 배포는 다운로드 페이지의 Windows 카드를 이용하세요.' -ForegroundColor Yellow

  $existing = Get-AppxPackage -Name $packageName -ErrorAction SilentlyContinue
  if ($existing -and [version]$existing.Version -ge [version]"$version.0") {
    Write-Host ''
    Write-Host ("이미 v{0} 이상이 설치되어 있습니다. 시작 메뉴에서 DeepWork를 실행하세요." -f $existing.Version) -ForegroundColor Green
    return
  }

  $workDir = Join-Path $env:TEMP 'deepwork-install'
  New-Item -ItemType Directory -Path $workDir -Force | Out-Null
  $appxPath = Join-Path $workDir $win.artifactName
  $cerPath = Join-Path $workDir 'DeepWork-test-signing.cer'

  Write-Host ''
  Write-Host "==> 설치 파일을 내려받습니다 (약 $sizeGb GB — 네트워크에 따라 수 분 걸릴 수 있습니다)..." -ForegroundColor Cyan
  Save-DeepWorkFile -Url $win.certificateUrl -Path $cerPath
  Save-DeepWorkFile -Url $win.packageUrl -Path $appxPath -ExpectedSha256 $win.sha256

  Write-Host ''
  Write-Host '==> 인증서 신뢰 등록과 앱 설치를 시작합니다.' -ForegroundColor Cyan
  Write-Host '    파란 "사용자 계정 컨트롤" 창이 뜨면 [예]를 눌러 주세요.' -ForegroundColor Yellow

  $logPath = Join-Path $workDir 'install.log'
  $innerPath = Join-Path $workDir 'deepwork-install-elevated.ps1'
  $inner = @"
`$ErrorActionPreference = 'Stop'
Start-Transcript -Path '$logPath' -Force | Out-Null
try {
  Import-Certificate -FilePath '$cerPath' -CertStoreLocation Cert:\LocalMachine\TrustedPeople | Out-Null
  Import-Certificate -FilePath '$cerPath' -CertStoreLocation Cert:\LocalMachine\Root | Out-Null
  Add-AppxPackage -Path '$appxPath'
  Get-AppxPackage -Name '$packageName' | Select-Object Name, Version, PackageFullName | Format-List
} finally {
  Stop-Transcript | Out-Null
}
"@
  [System.IO.File]::WriteAllText($innerPath, $inner, (New-Object System.Text.UTF8Encoding($true)))

  try {
    $proc = Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -PassThru -WindowStyle Hidden -ArgumentList @(
      '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $innerPath
    )
  } catch {
    throw '관리자 권한 승인이 취소되어 설치를 중단했습니다. 다시 실행한 뒤 UAC 창에서 [예]를 눌러 주세요.'
  }

  if ($proc.ExitCode -ne 0) {
    if (Test-Path -LiteralPath $logPath) {
      Write-Host ''
      Write-Host '--- 설치 로그 (마지막 40줄) ---' -ForegroundColor Yellow
      Get-Content -LiteralPath $logPath -Tail 40 | ForEach-Object { Write-Host "    $_" }
    }
    throw "설치에 실패했습니다 (exit code $($proc.ExitCode)). 전체 로그: $logPath"
  }

  $installed = Get-AppxPackage -Name $packageName -ErrorAction SilentlyContinue
  if (-not $installed) {
    throw "설치 명령은 끝났지만 설치된 패키지를 찾지 못했습니다. 로그를 확인해 주세요: $logPath"
  }

  Remove-Item -LiteralPath $appxPath -Force -ErrorAction SilentlyContinue

  Write-Host ''
  Write-Host ("설치 완료 — DeepWork v{0}" -f $installed.Version) -ForegroundColor Green
  Write-Host '시작 메뉴에서 DeepWork를 검색해 실행하세요.'
}

Install-DeepWork
