# Microsoft release directory

| Area | Project | Current version | Source and usage | History and validation |
| --- | --- | --- | --- | --- |
| Intune | Intune Endpoint Readiness Collector | 1.0.5 | [Project folder](Intune/IntuneReadinessCollector/) | [Collector releases](Intune/IntuneReadinessCollector/RELEASES.md) |

The collector's current version is 1.0.5. Its existing version number and
validation scope are retained. No beta, experimental, or stable classification
has been added by this reorganization, and no new collector release or tag has
been created.

## Repository update — October 26, 2026

- Established the top-level README as a directory of Microsoft service areas and tools.
- Added an Intune category index and collector release-history page.
- Kept the collector at `Intune/IntuneReadinessCollector/`.
- Preserved runtime scripts, query manifest, schema, tests, licenses, and automation.
- Added project-prefixed naming guidance for future releases.

These are documentation and navigation changes. They do not change collection
behavior, add live tenant validation, or change the collector's privacy limits.

For future releases, use a tag such as
`intune-readiness-collector/v<version>` and identify the status in the release
title and notes. Beta and experimental versions should be marked as pre-releases.

[Microsoft project directory](README.md) · [Intune projects](Intune/README.md)
