# DeepWork Public

Public distribution hub for DeepWork downloads, release metadata, update
checker files, and public legal pages.

This repository is intentionally public. It gives users, reviewers, enterprise
admins, and update clients a stable unauthenticated place to read public
DeepWork information and fetch official distribution metadata.

## Repository Role

`deepwork-public` owns the public surfaces around DeepWork distribution:

- the root download page for current DeepWork releases;
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
| `/` | Download page for official macOS and Windows builds |
| `/hwpx-form-fill/` | Link-only HWPX form-fill usability fixture; not linked from the root download page |
| `/privacy/deepwork-chrome-bridge/` | Chrome Web Store privacy policy URL |
| `/releases/stable.json` | Public stable release metadata |
| `/updates/` | Update checker metadata contract and channel notes |

If Braincrew later connects a company domain, keep the same path structure and
redirect old GitHub Pages URLs rather than breaking published Web Store or
updater links.

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
