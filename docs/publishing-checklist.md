# Publishing Checklist

Use this checklist before linking a page or artifact from app stores, browser
stores, updater clients, or customer communications.

## Public Page

- The URL opens in a private browser session without signing in.
- The page does not expose internal issue numbers unless intentionally public.
- The page does not include private repository URLs, local file paths, customer
  names, support tickets, tokens, or screenshots with private content.
- The page matches the current product behavior and public policy.
- macOS download copy names Apple Silicon as the supported Mac target and does
  not imply Intel Mac support.

## Release Artifact

- The artifact was produced by the approved desktop release pipeline.
- Required signing, notarization, or Windows package validation passed.
- Checksums are recorded in release metadata where required.
- Release notes are public-safe.
- The download page points to GitHub Release artifacts, not random local files.

## Update Metadata

- The channel is correct.
- The version matches the uploaded artifact.
- URLs are public and stable.
- Checksums match the downloadable artifact.
- Metadata does not point to a draft, expired, or private artifact.
