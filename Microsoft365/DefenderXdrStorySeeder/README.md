# Defender XDR Story Seeder

Current version: **0.1.0-beta**

Defender XDR Story Seeder creates a disposable, presentation-friendly incident dataset in the
Microsoft Defender portal without Microsoft Sentinel or a fleet of physical or virtual endpoints.
It uses Microsoft Graph to create manual alerts, groups 10–12 alerts into each incident, associates
tenant identities with fictional endpoint and mailbox assets, and records every created object in a
local run manifest.

> This is a security-testing and demonstration utility. Run it only in a tenant where you are
> authorized to create hundreds of Defender alerts and incidents. A default run creates 50
> incidents and 549 alerts.

## Sample output

### Seeded incident queue

The full run produces varied incident names, severities, impacted identities, fictional endpoints,
and 10–12 active alerts per incident in the Microsoft Defender portal.

![Seeded Defender XDR incidents showing varied attack stories, severities, impacted assets, and alert counts](docs/defender-xdr-seeded-incidents.png)

### Incident attack story

Opening a seeded incident shows its linked alert sequence and the relationships among the impacted
identity, fictional endpoint, IP addresses, URLs, and files.

![Defender XDR attack story showing twelve linked alerts and the incident asset graph](docs/defender-xdr-attack-story.png)

## What the tool creates

| Item | Default | Details |
| --- | ---: | --- |
| Incidents | 50 | Unique attack stories with informational, low, medium, and high severities. |
| Alerts | 549 | Deterministic distribution of 10, 11, or 12 linked alerts per incident. |
| Attack stories | 50 | Email, identity, endpoint, cloud-app, Defender for Cloud, and hybrid scenarios. |
| Fictional endpoints | 60 | Rotated through incident evidence; no endpoint is enrolled or created in Entra ID. |
| Fictional mailboxes | 30 | Generated in the signed-in tenant domain; no Exchange object is created. |
| Tenant identities | Read dynamically | Enabled member users are randomized across impacted identity evidence. |

Alert titles do not contain a bracketed synthetic prefix. Created records are classified as
`informationalExpectedActivity` with the `securityTesting` determination. Every fifth incident is
resolved during creation so the resulting dataset includes both active and resolved examples.

## Important platform limitations

- Alert creation uses the Microsoft Graph **beta** manual-alert API. Beta APIs can change without
  notice and are not supported for production applications.
- Microsoft controls `serviceSource`, `detectionSource`, and product attribution. Manual alerts are
  shown truthfully as Microsoft Defender XDR / Manual; the script cannot impersonate Defender for
  Endpoint, Defender for Identity, Defender for Office 365, or Defender for Cloud.
- Fictional devices appear as incident evidence under **Artifacts > Assets**. They do not populate
  the tenant-wide **Assets > Devices** inventory. That inventory requires onboarding or discovery.
- Microsoft Graph does not expose a supported delete method for these alert and incident records.
  Cleanup resolves and classifies them; it does not erase history.

See [Architecture and data flow](docs/ARCHITECTURE.md) for the implementation details.

## Requirements

- PowerShell 7.2 or later (`pwsh`)
- A Microsoft 365 tenant with Microsoft Defender XDR access
- Interactive sign-in by an account allowed to grant or use the delegated permissions below
- A supported Defender role for alert and incident operations; Microsoft documents **Security
  Operator** and **Security Administrator** for the write operations
- Internet access to Microsoft Graph and PowerShell Gallery on first run

The launcher installs `Microsoft.Graph.Authentication` for the current user if it is not already
available. It does not install the full Microsoft Graph PowerShell SDK.

### Delegated Microsoft Graph permissions

| Permission | Seeder | Cleanup | Purpose |
| --- | :---: | :---: | --- |
| `SecurityAlert.Create.All` | Yes | No | Create manual security alerts. |
| `SecurityIncident.ReadWrite.All` | Yes | Yes | Read/update the newly created incidents and close seeded incidents. |
| `User.Read.All` | Yes | No | Read enabled member identities for randomized impacted-user evidence. |
| `SecurityAlert.ReadWrite.All` | No | Yes | Find and resolve active seeded alerts. |

The scripts use delegated browser sign-in. They do not accept or store client secrets, certificates,
tokens, or passwords. Microsoft Graph documentation:

- [Create a manual alert (beta)](https://learn.microsoft.com/graph/api/security-alert-post-manualalert?view=graph-rest-beta)
- [Update an alert](https://learn.microsoft.com/graph/api/security-alert-update?view=graph-rest-1.0)
- [Update an incident](https://learn.microsoft.com/graph/api/security-incident-update?view=graph-rest-1.0)
- [List users](https://learn.microsoft.com/graph/api/user-list?view=graph-rest-1.0)

## Install

Download the source archive or a versioned release archive, extract it, and open PowerShell in the
`defender-xdr-story-seeder` directory. Verify the release checksum before running the scripts.

Windows may mark downloaded scripts as originating from the internet. If execution is blocked,
inspect the files and then unblock only this extracted package:

```powershell
Get-ChildItem -LiteralPath . -Filter '*.ps1' | Unblock-File
```

## Quick start

Only the administrator UPN is required:

```powershell
pwsh -File .\Start-DefenderBulkSeed.ps1 'global.admin@contoso.com'
```

The default confirmation must say:

```text
Create 50 incidents containing 549 alerts and impacted endpoint assets
```

If a launcher says `Create 3 synthetic alerts and one incident`, stop it. That message belongs to an
obsolete proof-of-concept package, not this version.

For an environment where the embedded browser cannot be used:

```powershell
pwsh -File .\Start-DefenderBulkSeed.ps1 'global.admin@contoso.com' -UseDeviceCode
```

## Smaller runs and previews

Create ten incidents instead of fifty:

```powershell
pwsh -File .\Start-DefenderBulkSeed.ps1 'global.admin@contoso.com' -IncidentCount 10
```

Preview the deterministic plan without signing in or changing the tenant:

```powershell
pwsh -File .\Invoke-DefenderBulkSeeder.ps1 `
  -GlobalAdminUpn 'global.admin@contoso.com' `
  -IncidentCount 10
```

The preview reports each catalog number, incident title, severity, fictional endpoint, and alert
count.

## Resume a partial run

The seeder writes the manifest after each alert. If a run stops, inspect the latest
`artifacts\bulk-seed-run-*.json` file. The warning printed by the script includes suggested
`-StartAt` and `-IncidentCount` values.

Example: resume at catalog item 18 and create the remaining 33 incidents:

```powershell
pwsh -File .\Invoke-DefenderBulkSeeder.ps1 `
  -GlobalAdminUpn 'global.admin@contoso.com' `
  -StartAt 18 `
  -IncidentCount 33 `
  -Execute
```

Always inspect the partial incident in the manifest before resuming. A network failure after a POST
can create an alert even if the client did not receive the response; POST requests are deliberately
not retried automatically to avoid duplicates.

## Clean up before another run

Resolve only the active alerts that match this package's catalog and close the safe incidents:

```powershell
pwsh -File .\Start-DefenderBulkCleanup.ps1 'global.admin@contoso.com'
```

The cleanup utility:

1. Reads all active Defender alerts available through the tenant retention window.
2. Selects Manual alerts whose normalized title matches the current 50 catalog titles, the shared
   attack-stage titles, or the three legacy proof-of-concept titles.
3. Recognizes and removes the obsolete `[SYNTHETIC]` or `[SYNTHESIZED]` prefix only for matching.
4. Resolves each selected alert as `informationalExpectedActivity` / `securityTesting`.
5. Closes an incident only when it has no unrelated active alert and every selected alert update for
   that incident succeeded.
6. Records successes, failures, and protected incidents in `artifacts\cleanup-run-*.json`.

Preview the cleanup without making changes:

```powershell
pwsh -File .\Invoke-DefenderBulkCleanup.ps1 `
  -GlobalAdminUpn 'global.admin@contoso.com'
```

`-AllManualAlerts` is intentionally available only on the underlying cleanup script. It selects
every active Manual alert, including alerts created by other people or tools, and should normally be
avoided.

## Parameter reference

### `Start-DefenderBulkSeed.ps1`

| Parameter | Default | Description |
| --- | --- | --- |
| `GlobalAdminUpn` | Required | Login hint used for delegated sign-in. |
| `IncidentCount` | `50` | Number of catalog incidents to create, from 1 through 50. |
| `UseDeviceCode` | Off | Use device-code authentication instead of interactive browser sign-in. |

### `Invoke-DefenderBulkSeeder.ps1`

| Parameter | Default | Description |
| --- | --- | --- |
| `GlobalAdminUpn` | Required | Login hint for delegated authentication. |
| `IncidentCount` | `50` | Number of incidents to plan or create. |
| `StartAt` | `1` | One-based catalog item at which to begin. |
| `DelayMilliseconds` | `1000` | Delay between write operations; accepted range is 500–30000. |
| `RandomSeed` | `20261106` | Makes identity, mailbox, and endpoint assignment repeatable. |
| `CatalogPath` | `catalog\attack-catalog.json` | Alternate attack catalog. |
| `EndpointRosterPath` | `catalog\endpoint-roster.json` | Alternate fictional endpoint roster. |
| `MailboxRosterPath` | `catalog\mailbox-roster.json` | Alternate fictional mailbox roster. |
| `Execute` | Off | Make tenant changes; without it the script produces a local preview. |
| `UseDeviceCode` | Off | Use device-code authentication. |
| `OutputDirectory` | `artifacts` | Local directory for run manifests. |

### `Invoke-DefenderBulkCleanup.ps1`

| Parameter | Default | Description |
| --- | --- | --- |
| `GlobalAdminUpn` | Required | Login hint for delegated authentication. |
| `CatalogPath` | `catalog\attack-catalog.json` | Catalog used to recognize seeded alert titles. |
| `DelayMilliseconds` | `500` | Delay between update operations; accepted range is 0–5000. |
| `IncludeLegacyPoc` | `true` | Recognize the three older proof-of-concept alert titles. |
| `AllManualAlerts` | Off | Select all active Manual alerts; potentially destructive to unrelated demos. |
| `Execute` | Off | Apply updates; without it the script is a preview. |
| `UseDeviceCode` | Off | Use device-code authentication. |
| `OutputDirectory` | `artifacts` | Local directory for cleanup manifests. |

## Run manifests and privacy

Manifests can contain tenant IDs, administrator UPNs, discovered user UPNs, mailbox addresses,
incident IDs, alert IDs, and Defender portal URLs. They are deliberately stored beneath
`artifacts\`, which is excluded from source control. Treat manifests as tenant data:

- do not attach them to public issues;
- do not commit them to Git;
- redact tenant and user identifiers before sharing troubleshooting excerpts; and
- delete local copies according to your organization's retention requirements.

The scripts never send manifest data anywhere except Microsoft Graph operations required for the
selected tenant.

## Catalog customization

Catalog and roster files are ordinary JSON:

- `catalog/attack-catalog.json` contains 50 attack definitions.
- `catalog/endpoint-roster.json` contains 60 fictional endpoint identities.
- `catalog/mailbox-roster.json` contains 30 fictional shared-mailbox aliases.

Keep all evidence fictional and use documentation-reserved IP address ranges and domains. Run the
offline validation after any edit:

```powershell
pwsh -File .\tests\Offline.Tests.ps1
```

See [Catalog and evidence model](docs/CATALOG.md) before adding new entity types or changing the
fixed 50-incident release contract.

## Build a versioned release archive

From the project directory:

```powershell
pwsh -File .\Build-Release.ps1
```

The builder validates scripts and catalogs, then writes a ZIP and `SHA256SUMS.txt` under `dist\`.
The version comes from `VERSION`; the committed scripts and changelog must use the same version.

## Documentation

- [Architecture and data flow](docs/ARCHITECTURE.md)
- [Catalog and evidence model](docs/CATALOG.md)
- [Troubleshooting](docs/TROUBLESHOOTING.md)
- [Changelog](CHANGELOG.md)
- [Security guidance](SECURITY.md)

## License and status

This project is licensed under the repository's GNU General Public License, version 3. Microsoft
product names identify the services used and do not imply Microsoft affiliation or endorsement.

Version `0.1.0-beta` is suitable for authorized demonstrations and lab tenants. It is not a
production telemetry simulator or a substitute for real Defender workload onboarding.
