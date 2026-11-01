# Changelog

All notable project changes are documented here.

## 0.0.1-beta

- Collect interactive-user sign-ins from Microsoft Graph for a prompted or explicit time window.
- Default to the previous 48 hours and exclude non-interactive users, service principals, and
  managed identities.
- Preserve exact Graph pages, raw JSONL, collection metadata, and a tenant-scoped analysis cache.
- Summarize failures, failure reasons, Conditional Access outcomes, identity risk, location changes,
  impossible travel, authentication bursts, possible password spraying, and legacy authentication.
- Generate a self-contained Nexlinks-branded HTML report with tenant name and tenant ID.
- Support delegated browser/device-code, certificate, managed-identity, existing-session, and offline
  input modes.
- Prompt before installing a missing Microsoft Graph authentication module.
- Provide timestamped collection/analysis status and open completed reports in a new browser window.
