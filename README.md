# Microsoft tools

Practical Microsoft administration tools by Phil Kinsley.

## Project directory

| Area | Project | Current version | Purpose |
| --- | --- | --- | --- |
| [Intune](Intune/) | [Intune Endpoint Readiness Collector](Intune/IntuneReadinessCollector/) | 1.0.5 | Collect Microsoft Graph evidence for an Intune readiness review. |

- [Release directory and repository updates](RELEASES.md)
- [Intune project directory](Intune/README.md)
- [Collector requirements, permissions, and usage](Intune/IntuneReadinessCollector/README.md)
- [Collector version history and validation scope](Intune/IntuneReadinessCollector/RELEASES.md)

The collector gathers evidence and creates JSON for a separate scoring and
reporting workflow. It does not change tenant configuration or assign readiness
scores. Version 1.0.5 retains its existing validation scope; this reorganization
does not assign a new maturity label.

## Repository layout

```text
Microsoft/
  README.md                         Project directory
  RELEASES.md                       Version directory and repository updates
  LICENSE                           Repository license
  .github/workflows/                Repository automation
  Intune/
    README.md                       Intune project directory
    IntuneReadinessCollector/
      README.md                     Requirements and usage
      RELEASES.md                   Version history and validation scope
      HOW-IT-WORKS.md                Code walkthrough
      DATA-DICTIONARY.md             Evidence fields
      tests/                        Existing offline tests
      ...                           Collector script, manifest, and schema
```

Group tools by service area, then give each project a permanent folder. Add
other service areas when they contain a project. Keep each project's
documentation and tests with its source. Experimental, beta, and stable are
release statuses rather than separate source folders.

For future GitHub Releases, use project-prefixed tags such as
`intune-readiness-collector/v1.0.5` so versions for different tools remain clear.
That example tag has not been created by this documentation update.

## Scope and privacy

This is an independent community project. Microsoft product names identify the
services used; they do not imply Microsoft affiliation or endorsement.

Keep generated tenant evidence, debug files, and probe output private. Existing
ignore rules remain in place; review files before publishing.

## License

See [LICENSE](LICENSE) for the repository's existing GNU General Public License,
version 3.
