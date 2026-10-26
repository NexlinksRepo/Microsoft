# Intune Endpoint Readiness Collector release history

**Current collector version: 1.0.5. Query manifest version: 1.0.1.**

[Setup and usage](README.md) · [How the collector works](HOW-IT-WORKS.md) · [Microsoft releases](../../RELEASES.md)

## Version history

| Version | Change |
| --- | --- |
| 1.0.2 | Original baseline collector. |
| 1.0.3 | Replaced unsupported modern status expansion with a reporting action; removed Autopilot `$select`; adjusted empty-parent handling. |
| 1.0.4 | Added opt-in `-CaptureDebug` and a failed-query sidecar. |
| 1.0.5 | Added the live-confirmed `PolicyBaseTypeName` filter. |

The historical version list comes from the existing collector README. It does
not imply that separate downloads for all versions are published here.

## Validation scope

During GitHub preparation on October 25, 2026, ten Pester checks and both
standalone offline suites passed locally on PowerShell 7.6.5 and Windows
PowerShell 5.1.26100.9711. The repository workflow runs offline checks on both
PowerShell editions. See [GitHub Actions](https://github.com/NexlinksRepo/Microsoft/actions)
for hosted results.

No live tenant collection was repeated during that preparation or this
documentation reorganization. Offline results do not establish live API
availability, tenant permissions, or complete evidence coverage. Microsoft Graph
beta dependencies and privacy limits remain documented in the project README.

## October 26, 2026 — Repository organization

Added service-area navigation and this release-history page. Collector source,
manifest, schema, tests, license, and workflow are unchanged. The collector
remains version 1.0.5; no new maturity classification or software release is
introduced.

## Future release naming

Use project-prefixed Git tags such as
`intune-readiness-collector/v<version>`. Record maturity separately from the
version number and mark beta or experimental GitHub Releases as pre-releases.
