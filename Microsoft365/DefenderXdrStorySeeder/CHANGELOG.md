# Changelog

All notable changes to Defender XDR Story Seeder are documented here. Versions follow Semantic
Versioning. Tags use the repository convention `defender-xdr-story-seeder/v<version>`.

## 0.1.0-beta — 2026-11-06

- Add a deterministic 50-incident catalog containing 549 total alerts.
- Guarantee 10–12 linked manual alerts per incident.
- Randomize enabled member identities read from Microsoft Entra ID and prefer mail-enabled users for
  email scenarios.
- Add 60 fictional endpoint names and 30 fictional shared-mailbox aliases.
- Cover Defender for Office 365, Defender for Identity, Defender for Cloud Apps, Defender for Cloud,
  Defender for Endpoint, and cross-domain XDR story contexts while retaining truthful Manual alert
  source attribution.
- Remove bracketed synthetic prefixes from newly created titles.
- Classify created incidents as expected authorized security testing.
- Add polling for eventual consistency before linking alerts to a newly created incident.
- Persist an incremental JSON run manifest after every created alert.
- Add selective cleanup that resolves seeded alerts and protects incidents containing unrelated
  active alerts.
- Add interactive browser and device-code sign-in options with automatic installation of the
  Microsoft Graph authentication module.
- Add offline validation, reproducible release packaging, CI, architecture, catalog, security, and
  troubleshooting documentation.

### Known beta constraints

- Manual alert creation uses Microsoft Graph beta.
- Cleanup resolves records but cannot delete them from Defender history.
- Fictional device evidence does not populate the global Defender device inventory.
- Microsoft-controlled service and detection source fields cannot be overridden.
