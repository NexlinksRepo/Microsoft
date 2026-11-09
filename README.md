# Microsoft administration tools

Practical Microsoft administration and assessment tools by Phil Kinsley.

## Project directory

| Service area | Project | Version | Purpose |
| --- | --- | --- | --- |
| [Microsoft Intune](Intune/) | [Intune Endpoint Readiness Collector](Intune/IntuneReadinessCollector/) | 1.0.5 | Collect read-only Microsoft Graph evidence for an Intune readiness review. |
| [Microsoft 365](Microsoft365/) | [M365 Sign-in Audit Report](Microsoft365/M365SignInAuditReport/) | 0.0.1-beta | Collect interactive-user sign-ins and create a daily HTML security audit report. |
| [Microsoft 365](Microsoft365/) | [Defender XDR Story Seeder](Microsoft365/DefenderXdrStorySeeder/) | 0.2.4-beta | Populate Defender XDR with demonstration incidents and optional dormant Agent 365 identities. |

## Choose a project

### Intune Endpoint Readiness Collector

Use this project for endpoint-management readiness evidence. It gathers Microsoft Graph data and
creates JSON for a separate scoring and reporting workflow. It does not change tenant configuration
or assign readiness scores.

- [Setup and usage](Intune/IntuneReadinessCollector/README.md)
- [How it works](Intune/IntuneReadinessCollector/HOW-IT-WORKS.md)
- [Evidence data dictionary](Intune/IntuneReadinessCollector/DATA-DICTIONARY.md)
- [Release history](Intune/IntuneReadinessCollector/RELEASES.md)

### M365 Sign-in Audit Report

Use this project for daily Microsoft Entra sign-in review. It collects interactive-user events,
retains raw Graph evidence locally, analyzes failures, Conditional Access, identity risk and location
anomalies, then creates a self-contained Nexlinks-branded HTML report.

- [Setup, operation and security guidance](Microsoft365/M365SignInAuditReport/README.md)
- [Version history](Microsoft365/M365SignInAuditReport/CHANGELOG.md)
- [Project security policy](Microsoft365/M365SignInAuditReport/SECURITY.md)

### Defender XDR Story Seeder

Use this project to populate an authorized lab or demonstration tenant with up to 50 Defender XDR
incident stories and 549 manual alerts. It can also create dormant Entra agent identity blueprints,
agent identities, and Agent 365 registry cards, then associate truthful manual AI proxy stories with
their identifiers. Cleanup protects unrelated active alerts and targets only recorded agent objects.

- [Setup, operation and permissions](Microsoft365/DefenderXdrStorySeeder/README.md)
- [Architecture and data flow](Microsoft365/DefenderXdrStorySeeder/docs/ARCHITECTURE.md)
- [Version history](Microsoft365/DefenderXdrStorySeeder/CHANGELOG.md)
- [Project security guidance](Microsoft365/DefenderXdrStorySeeder/SECURITY.md)

## Repository layout

```text
Microsoft/
  README.md
  RELEASES.md
  LICENSE
  SECURITY.md
  .github/workflows/
    intune-collector.yml
    m365-signin-audit.yml
    defender-xdr-story-seeder.yml
  Intune/
    README.md
    IntuneReadinessCollector/
  Microsoft365/
    README.md
    M365SignInAuditReport/
    DefenderXdrStorySeeder/
```

Each tool has a permanent project folder under its Microsoft service area. Documentation, tests,
assets and source stay with that project. Beta and stable are release statuses rather than separate
source folders.

For GitHub Releases, use project-prefixed tags such as:

- `intune-readiness-collector/v1.0.5`
- `m365-signin-audit/v0.0.1-beta`
- `defender-xdr-story-seeder/v0.2.3-beta`
- `defender-xdr-story-seeder/v0.2.4-beta`

## Scope and privacy

These are independent community tools. Microsoft product names identify the services used; they do
not imply Microsoft affiliation or endorsement.

Never publish generated tenant evidence, reports, local configuration, certificates, keys, tokens or
debug output. Review staged files before every push and use synthetic evidence in issues and pull
requests.

## License

See [LICENSE](LICENSE) for the repository's GNU General Public License, version 3.


