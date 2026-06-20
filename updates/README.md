# Update Checker Metadata

This directory is the planned public home for DeepWork update-checker metadata.

The desktop release pipeline owns build, signing, notarization, and artifact
upload. This public repository owns only unauthenticated metadata and public
links that update clients can fetch safely.

Update metadata should be:

- small enough to review in code review;
- deterministic and machine-readable;
- signed or checksum-linked where the desktop updater requires it;
- separated by release channel;
- free of secrets, credentials, internal paths, and unreleased customer data.

Do not publish update metadata until the corresponding release artifact has
passed the required signing and smoke checks.

