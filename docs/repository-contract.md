# Repository Contract

`braincrew-lab/deepwork-public` is the public distribution and policy surface
for DeepWork.

## Source Of Truth Boundaries

This repository is authoritative for:

- public download pages;
- public privacy and legal pages;
- public release metadata;
- update checker metadata after release approval;
- links to official release artifacts hosted through GitHub Releases;
- public proprietary asset notices.

This repository is not authoritative for:

- product implementation;
- issue tracking;
- signing or notarization configuration;
- CI secrets or certificate material;
- internal release decisions before public approval;
- support cases, logs, telemetry, or customer data.

## Artifact Rule

Large binaries belong in GitHub Releases. Git stores only pages, policies,
metadata, and small web assets.

## Visibility Rule

Any URL used in an app store, browser store, updater, or customer-facing
document must be tested in a private browser session with no Braincrew or GitHub
login. If it does not load anonymously, it is not public enough for this repo's
purpose.

## Asset Ownership

Braincrew-owned logos, icons, screenshots, copy, HTML/CSS, metadata, installers,
and release artifacts are proprietary Braincrew assets. Public access does not
grant redistribution or derivative-work rights.

