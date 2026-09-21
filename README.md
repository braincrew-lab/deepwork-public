# DeepWork Public

> **기업의 업무망 안으로, AI의 실행력을.**

DeepWork는 문서를 작성하고, 업무 도구를 다루고, 코드를 구현하는
**기업용 AI 데스크톱**입니다. 금융권을 포함한 대기업의 업무 환경과
비개발 일반 사무직 사용자를 우선하며, 일상 업무부터 개발까지 다룹니다.

[제품 소개](https://braincrew-lab.github.io/deepwork-public/) ·
[공식 다운로드](https://braincrew-lab.github.io/deepwork-public/#downloads)

## 제품 메시지와 주요 기능

랜딩페이지와 소개 자료는 다음 순서로 기능과 작업 결과를 설명합니다.

| 기능 | 소개 카피 |
| --- | --- |
| 문서·데이터 | 엑셀을 정리하고, 보고서를 만듭니다. |
| 브라우저·컴퓨터 유즈 | 브라우저에서 찾고, 입력하고, 내려받습니다. 일반 데스크톱 앱 조작은 준비 중으로 표시합니다. |
| 격리 공간 | 필요한 폴더를 연결한 격리 공간에서 파일을 처리하고 코드를 실행합니다. |
| Work / Code | 문서 작업부터 코드 수정과 테스트까지 하나의 앱에서 다룹니다. |
| 플러그인 | 필요한 업무 도구와 기능을 연결합니다. |
| 모델 연결 | 회사에서 사용하는 AI 모델을 연결합니다. |

모델 연결은 **상용 모델 API / 기업용 클라우드 / 사내 모델**로 나눕니다.
Azure·Amazon Bedrock은 기업용 클라우드 범주에 함께 표시합니다. 폐쇄망은
사내 모델과 내부 도구를 사용하는 배포 구성으로 설명합니다.

사용자에게는 **격리 공간**이라는 용어를 씁니다. Work / Code라는 업무 구분이
격리 여부를 결정하지 않으며, 브라우저·플러그인 등 외부 도구의 실행과 접근
권한은 별도입니다. 공개 카피에 모든 모델의 동일 성능, 모든 외부 전송 차단,
미확인 기능·고객 성과를 약속하지 않습니다.

## About This Repository

Public product website and distribution hub for DeepWork features, downloads,
release metadata, update checker files, and public legal pages.

This repository is intentionally public. It gives users, reviewers, enterprise
admins, and update clients a stable unauthenticated place to read public
DeepWork information and fetch official distribution metadata.

## Repository Role

`deepwork-public` owns the public product and distribution surfaces for DeepWork:

- the root product landing page, enterprise contact, and official downloads;
- public privacy policy pages, including Chrome Web Store review pages;
- release-facing metadata used by download pages and update checkers;
- links to official GitHub Release artifacts;
- public notices, asset ownership statements, and distribution policy.

It does not own:

- DeepWork desktop application source code;
- signing keys, certificates, provisioning credentials, or CI secrets;
- internal release notes that are not ready for public disclosure;
- customer data, logs, telemetry exports, support cases, or private screenshots;
- experimental binaries that have not been approved for public distribution.

## Public URLs

When GitHub Pages is enabled for this repository, the default public site URL is:

```text
https://braincrew-lab.github.io/deepwork-public/
```

Planned public paths:

| Path | Purpose |
| --- | --- |
| `/` | Product landing page and official macOS and Windows downloads |
| `/hwpx-form-fill/` | Link-only HWPX form-fill usability fixture; not linked from the root download page |
| `/privacy/deepwork-chrome-bridge/` | Chrome Web Store privacy policy URL |
| `/releases/stable.json` | Public stable release metadata |
| `/updates/` | Update checker metadata contract and channel notes |
| `/windows-first-install-reset.ps1` | Guarded Windows first-install reset script for dedicated test PCs |

If Braincrew later connects a company domain, keep the same path structure and
redirect old GitHub Pages URLs rather than breaking published Web Store or
updater links.

## Landing Page Maintenance

`assets/landing.css` and `assets/landing.js` apply only to the root product page.
The feature panels are illustrative workflow examples, not product screenshots.
Use “격리 공간” in public copy. Keep the download card IDs `primary-download`
and `windows-download` and their metadata markup stable: desktop release scripts
update these sections by matching the HTML. Preserve the `prettier-ignore`
comments and literal `<code>…</code>` tags around the release SHA values.

## Windows First-Install Reset

The public reset script removes the current user's DeepWork package, packaged
service, app data, execution history, VM cache, DeepWork-owned registrations,
and local test certificates. With `-ResetWindowsVirtualization`, it also stops
HCS/HNS, disables `VirtualMachinePlatform`, and requires a reboot. Run it only
on a dedicated disposable Windows test PC from an elevated PowerShell window.

Review the plan without changing the PC:

```powershell
$u='https://braincrew-lab.github.io/deepwork-public/windows-first-install-reset.ps1';$p=Join-Path $env:TEMP 'windows-first-install-reset.ps1';Invoke-WebRequest -UseBasicParsing $u -OutFile $p;if((Get-FileHash $p -Algorithm SHA256).Hash.ToLowerInvariant() -ne '0fef3e3650fd185acda96dfcc338e290fe6ca3716e7629074e95dd9c1d0246a1'){throw 'DeepWork reset script hash mismatch'};& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $p -WhatIf -ResetWindowsVirtualization
```

Perform the reset and reboot:

```powershell
$u='https://braincrew-lab.github.io/deepwork-public/windows-first-install-reset.ps1';$p=Join-Path $env:TEMP 'windows-first-install-reset.ps1';Invoke-WebRequest -UseBasicParsing $u -OutFile $p;if((Get-FileHash $p -Algorithm SHA256).Hash.ToLowerInvariant() -ne '0fef3e3650fd185acda96dfcc338e290fe6ca3716e7629074e95dd9c1d0246a1'){throw 'DeepWork reset script hash mismatch'};& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $p -ConfirmFactoryReset -ResetWindowsVirtualization -Restart
```

Published checksum: [`windows-first-install-reset.ps1.sha256`](windows-first-install-reset.ps1.sha256).

## Release Artifact Policy

Do not commit large installer binaries directly to git. Official downloadable
artifacts should be uploaded to GitHub Releases, then referenced from pages and
metadata in this repository.

Expected artifact classes:

- macOS Apple Silicon DMG/ZIP; Intel Mac is not a supported public target;
- Windows signed MSIX/AppX or installer packages;
- update metadata consumed by DeepWork's updater;
- checksums and release notes approved for public distribution.

## Update Checker Ownership

This repository is the planned public home for update-checker metadata. Update
metadata must be small, reviewable, and deterministic. It should identify:

- release channel, such as `stable`, `preview`, or `internal-demo`;
- semantic version and build number;
- platform and architecture;
- artifact URL;
- checksum;
- minimum supported app version, when needed;
- release notes URL.

Signing, notarization, and artifact production remain owned by the desktop
release pipeline. This repository only publishes public metadata and user-facing
pages.

## Privacy And Legal Pages

Chrome Web Store and similar reviewers require unauthenticated public URLs.
Do not use internal GitHub links or private documentation URLs for those fields.

Current public policy page:

```text
https://braincrew-lab.github.io/deepwork-public/privacy/deepwork-chrome-bridge/
```

Before submitting external review forms, open the URL in a private browser
window where no Braincrew or GitHub account is signed in.

## License And Assets

This repository is public but not open source. Braincrew-owned source files,
web pages, release metadata, graphics, product names, screenshots, installers,
and other assets are proprietary Braincrew assets. See [LICENSE](LICENSE) and
[NOTICE.md](NOTICE.md).

## Repository Layout

```text
.
├── index.html                         # Root download page
├── hwpx-form-fill/                    # Link-only HWPX form-fill usability fixture
├── privacy/deepwork-chrome-bridge/    # Chrome Web Store privacy policy page
├── releases/                          # Public release metadata
├── updates/                           # Update checker contract and channel notes
├── docs/                              # Operator-facing public repo contracts
├── assets/                            # Braincrew-owned public web assets, screenshots, and small test fixtures
├── LICENSE
└── NOTICE.md
```
