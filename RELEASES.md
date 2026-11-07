# Microsoft release directory

| Service area | Project | Current version | Source and usage | History |
| --- | --- | --- | --- | --- |
| Intune | Intune Endpoint Readiness Collector | 1.0.5 | [Project folder](Intune/IntuneReadinessCollector/) | [Collector releases](Intune/IntuneReadinessCollector/RELEASES.md) |
| Microsoft 365 | M365 Sign-in Audit Report | 0.0.1-beta | [Project folder](Microsoft365/M365SignInAuditReport/) | [Audit report changelog](Microsoft365/M365SignInAuditReport/CHANGELOG.md) |
| Microsoft 365 | Defender XDR Story Seeder | 0.1.0-beta | [Project folder](Microsoft365/DefenderXdrStorySeeder/) | [Seeder changelog](Microsoft365/DefenderXdrStorySeeder/CHANGELOG.md) |

## Defender XDR Story Seeder 0.1.0-beta — November 6, 2026

- Added a documented 50-incident, 549-alert Defender XDR demonstration dataset.
- Added tenant identity discovery, fictional endpoint and mailbox evidence, and six workload-story contexts.
- Added safe selective cleanup, incremental manifests, offline validation, and reproducible release packaging.
- Added a project-specific CI workflow and security guidance.

## Repository update — November 1, 2026

- Preserved the Intune collector at `Intune/IntuneReadinessCollector/`.
- Added `Microsoft365/M365SignInAuditReport/` as an independent project.
- Added separate navigation, documentation, tests and GitHub Actions validation for the M365 tool.
- Expanded repository-wide ignore rules for sign-in evidence, reports, state, configuration and credentials.
- Kept generated tenant data out of source control.

These organization changes do not modify the Intune collector's runtime behavior or version.

For future releases, use project-prefixed tags. Mark beta and experimental versions as GitHub
pre-releases.

[Microsoft project directory](README.md) · [Intune projects](Intune/README.md) · [Microsoft 365 projects](Microsoft365/README.md)
