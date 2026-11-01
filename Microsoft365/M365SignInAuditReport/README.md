# M365 Sign-in Audit Report — beta v0.0.1

A daily Microsoft Entra / Microsoft 365 sign-in collector and analyst report written in PowerShell. It collects interactive-user sign-ins, preserves the raw Graph responses, and produces a self-contained HTML review. Non-interactive users, managed identities, and service principals are excluded from collection and analysis.

The HTML report embeds the Nexlinks website logo from `assets/nexlinks-logo.png` and links to [nexlinks.net](https://www.nexlinks.net/) in the header and footer. The report header also displays the Microsoft 365 tenant name and tenant ID.

## At a glance

- **Input:** Microsoft Graph sign-in logs or a controlled offline JSON/JSONL export.
- **Scope:** Interactive-user sign-ins only; workload identities and non-interactive users are excluded.
- **Default window:** The previous 48 hours, with optional local From/To prompts.
- **Output:** A self-contained HTML report, metadata, exact API pages, raw JSONL, and local baseline cache.
- **Authentication:** Delegated browser/device code, certificate, managed identity, or an existing Graph session.
- **Data handling:** Tenant evidence stays on the workstation; the script does not call third-party enrichment services.

## What the beta reports

- Successful and failed sign-ins, failure codes, reasons, and additional details.
- Applied Conditional Access policy results, including the enforced policy that denied a sign-in and report-only failures.
- Entra ID Protection risk levels and detections when the tenant is licensed for them.
- New user countries/cities, potential impossible travel, concentrated failure bursts, possible password spraying, and successful legacy authentication.
- Exact API response pages, a deduplicated raw JSONL stream, collection metadata, and a rolling local analysis cache.

Every detector produces an analyst lead, not an automatic incident verdict. VPNs, proxies, mobile networks, shared NAT, and token behavior can create false positives.

## How it works

1. Loads command-line values and optional `config.json` settings.
2. Prompts for a local From/To time window unless dates were supplied or the run is non-interactive.
3. Confirms the Graph authentication module is available and asks before installing it when needed.
4. Authenticates to Microsoft Graph and resolves the tenant name and ID.
5. Requests only `interactiveUser` events and writes every response page plus a raw JSONL stream.
6. Normalizes and deduplicates the events, updates a tenant-isolated daily cache, and applies the
   interactive-user-only safety filter again.
7. Compares the report window with retained history and runs the configured analytic checks.
8. Builds the branded HTML report and metadata, updates `latest-report.html`, and opens a new browser
   window unless automatic launch was disabled.

The console prints timestamped stage updates and a line for every Graph page so long-running
collections do not appear idle.

## Analytic checks

| Check | What creates a finding | Important caveats |
| --- | --- | --- |
| Sign-in failure | Nonzero Entra error code | Expected user mistakes and expired sessions can be noisy. |
| Conditional Access | Enforced failure or report-only failure in applied policy results | Policy detail depends on Graph permissions, Entra role, and returned event data. |
| Identity risk | Medium/high aggregate or in-session risk, or an at-risk/compromised state | Licensing and permissions can hide risk fields or named detections. |
| New location | A user signs in from a country/city absent from the retained baseline | VPN, mobile, proxy, and cloud egress can change apparent location. |
| Impossible travel | Consecutive successful sign-ins exceed configured distance and speed thresholds | Shared egress and geo-IP inaccuracies commonly cause false positives. |
| Failure burst | Failures from a source exceed the configured threshold in the analysis window | Shared NAT and security-testing infrastructure can concentrate traffic. |
| Password spray | One source fails against the configured number of distinct users | Confirm source ownership and timing before escalation. |
| Legacy authentication | A legacy client successfully authenticates | Client classification comes from the Entra sign-in record. |

## Prerequisites

- Windows PowerShell 5.1 or PowerShell 7+.
- Microsoft Entra ID P1 or P2 to download sign-in logs through Microsoft Graph.
- `Microsoft.Graph.Authentication`. If it is missing, the script **asks before installing it** for the current user. It never silently installs a module.
- Microsoft Graph delegated scopes `User.Read`, `AuditLog.Read.All`, and `Policy.Read.ConditionalAccess` for the default interactive run. Admin consent is normally required for the audit and policy scopes.
- The signed-in analyst needs an Entra role that can read the tenant sign-in logs. Conditional Access detail additionally requires a role that can read CA data, such as Global Reader, Security Reader, Security Administrator, or Conditional Access Administrator.

For unattended certificate or managed-identity runs, assign the application/identity the `AuditLog.Read.All` and `Policy.Read.ConditionalAccess` application permissions (or a documented higher CA-read permission) and grant admin consent.

Microsoft references:

- [List sign-ins and required permissions](https://learn.microsoft.com/graph/api/signin-list?view=graph-rest-1.0)
- [Sign-in resource fields](https://learn.microsoft.com/graph/api/resources/signin?view=graph-rest-1.0)
- [Microsoft Graph PowerShell authentication](https://learn.microsoft.com/powershell/microsoftgraph/authentication-commands)
- [Entra data retention](https://learn.microsoft.com/entra/identity/monitoring-health/reference-reports-data-retention)

## First run: interactive sign-in

Copy the example configuration, optionally fill in a tenant ID and name, then run the script:

```powershell
Set-Location 'C:\path\to\M365-SignIn-Report'
Copy-Item .\config.example.json .\config.json
.\Invoke-M365SignInReport.ps1
```

Delegated interactive-browser authentication is the default, matching the Intune Endpoint Readiness Collector in `NexlinksRepo/Microsoft`. The script passes the requested scopes plus optional `TenantId` and `ClientId` directly to `Connect-MgGraph`, with the authentication context limited to the current PowerShell process. It does not ask for a UPN or launch a browser itself. Passwords, MFA responses, authentication credentials, and tokens are handled by Microsoft's authentication library and are not written to the report or config file.

For delegated runs, the tenant display name is resolved from Microsoft Graph using the least-privileged `User.Read` scope. App-only or offline runs can supply `TenantName` in `config.json` or with `-TenantName`; the tenant ID is taken from the authenticated Graph context or `-TenantId`.

Before sign-in, an interactive run asks for a local `From` and `To` value in `yyyy-MM-dd HH:mm` format. Press Enter at both prompts to collect only the previous 48 hours. If only `From` is supplied, `To` defaults to now. If only `To` is supplied, `From` defaults to 48 hours earlier. The same window controls the Graph query, raw log archive, and HTML report.

The console prints timestamped status updates while it authenticates, retrieves each Graph page, updates the cache, analyzes the records, builds the HTML, and saves metadata. When an interactive run completes, the report opens in a new window of the configured Windows default browser. Use `-NoOpenReport` when automatic launch is not wanted.

For command-line or scheduled selection, bypass the prompts with explicit ISO 8601 values:

```powershell
.\Invoke-M365SignInReport.ps1 -StartTime '2026-11-01T00:00:00-04:00' -EndTime '2026-11-02T00:00:00-05:00'
```

Device-code authentication remains an explicit alternative:

```powershell
.\Invoke-M365SignInReport.ps1 -UseDeviceCode
```

To target a tenant without editing the config:

```powershell
.\Invoke-M365SignInReport.ps1 -TenantId '00000000-0000-0000-0000-000000000000'
```

## Output and retention

Each run creates an immutable timestamped folder:

```text
output/
  latest-report.html
  _state/
    tenant-guid/
      state.json
      events/YYYY-MM-DD.jsonl
  20261101T170000Z/
    report.html
    metadata.json
    raw/
      signins.jsonl
      api-pages/
        interactiveUser-page-00001.json
        ...
```

The `raw/api-pages` files are the exact response bodies returned by Graph. `raw/signins.jsonl` contains the events returned for the selected collection window. The `_state` folder contains tenant-isolated, normalized daily buckets used to build historical location baselines across runs. Removing `_state` is safe, but anomaly detection will have less history until the cache is rebuilt. Raw run folders are never automatically deleted.

Every normal run requests only the selected `From`/`To` window—48 hours by default. Use `-ForceBaselineBackfill` to request the configured historical baseline as well (14 days by default), for example after clearing the cache. Baseline events are retained for anomaly analysis but do not inflate the 48-hour report totals.

> Precise `interactiveUser` filtering currently uses the Microsoft Graph `/beta` endpoint. Microsoft
> does not support beta APIs for production applications and can change them. Setting
> `Collection.GraphApiVersion` to `v1.0` uses the supported endpoint and applies the local
> interactive-user filter after collection.

## Command-line reference

| Parameter | Purpose |
| --- | --- |
| `-ConfigPath` | Use a JSON configuration file other than `config.json`. |
| `-AuthMode` | Select `Delegated`, `Certificate`, `ManagedIdentity`, or `ExistingSession`. |
| `-TenantId` / `-TenantName` | Target or label the tenant; live delegated runs resolve the name automatically. |
| `-ClientId` | Supply an application ID or user-assigned managed-identity client ID. |
| `-CertificateThumbprint` | Select the certificate used by certificate authentication. |
| `-UseDeviceCode` | Use device-code authentication instead of the interactive browser. |
| `-StartTime` / `-EndTime` | Bypass date prompts with explicit values; ISO 8601 with an offset is recommended. |
| `-ReportHours` | Set the default duration when StartTime is omitted; default is 48. |
| `-BaselineDays` | Set retained history for location/travel analysis; default is 14. |
| `-ForceBaselineBackfill` | Request the full configured baseline window from Graph. |
| `-InputFile` | Run analysis and rendering against JSON/JSONL without Graph access. |
| `-OutputDirectory` | Change where reports, raw data, and state are written. |
| `-NoOpenReport` | Do not launch the finished HTML report. |
| `-NonInteractive` | Disable prompts and browser launch for automation. |

PowerShell also exposes this reference locally:

```powershell
Get-Help .\Invoke-M365SignInReport.ps1 -Full
```

## Configuration

Copy `config.example.json` to `config.json` for local customization. The local file is ignored by
Git because it may contain tenant-specific values.

| Section | Settings |
| --- | --- |
| Root | Tenant name, display time zone, and output directory. |
| `Authentication` | Mode, tenant/client IDs, certificate thumbprint, and device-code preference. |
| `Collection` | Graph version, event types, 48-hour default, baseline retention, and page size. |
| `Analysis` | Location baseline, password-spray, burst, and impossible-travel thresholds. |
| `Report` | Detail-row limit and automatic browser launch. |

The entry script enforces interactive-user-only reporting even if an old configuration or cache
still contains excluded event types.

## Unattended daily run

For Task Scheduler, prefer certificate authentication instead of saving a user secret:

```json
"Authentication": {
  "Mode": "Certificate",
  "TenantId": "tenant-guid",
  "ClientId": "app-registration-guid",
  "CertificateThumbprint": "certificate-thumbprint",
  "UseDeviceCode": false
}
```

Then schedule:

```powershell
pwsh.exe -NoProfile -File "C:\path\to\M365-SignIn-Report\Invoke-M365SignInReport.ps1" -NonInteractive -NoOpenReport
```

`-NonInteractive` prevents module-install prompts and fails with the exact prerequisite command if a module is missing.

## Offline development and sample report

No tenant connection is needed to exercise the analysis and HTML renderer:

```powershell
.\Invoke-M365SignInReport.ps1 -InputFile .\samples\sample-signins.json -NoOpenReport
```

The sample contains synthetic `contoso.example` identities and documentation-range IP addresses.
It is safe to use in tests and demonstrations.

## Repository layout

```text
.
├── assets/nexlinks-logo.png
├── samples/sample-signins.json
├── src/M365SignInReport.psd1
├── src/M365SignInReport.psm1
├── tests/SmokeTest.ps1
├── config.example.json
├── Invoke-M365SignInReport.ps1
├── CHANGELOG.md
├── SECURITY.md
└── README.md
```

## Testing

The smoke test validates normalization, exclusion rules, anomaly detection, Conditional Access
detail, risk wording, caching, tenant identity rendering, and the embedded logo:

```powershell
.\tests\SmokeTest.ps1
```

It is compatible with Windows PowerShell 5.1 and PowerShell 7. GitHub Actions runs it on
`windows-latest` for pushes and pull requests.

## Security and publishing

- Never commit `output/`, `config.json`, raw Graph exports, certificates, keys, tokens, or tenant screenshots.
- Review `git status` and the staged diff before every push.
- Treat generated HTML as sensitive: it contains the same identity and security context as the raw logs.
- Use synthetic data for issues, examples, and pull requests.
- See [SECURITY.md](SECURITY.md) for disclosure and evidence-handling guidance.

## Current beta boundaries

- The report is a local daily triage artifact, not a SIEM replacement.
- IP reputation, ASN ownership, TOR lists, and threat-intelligence enrichment are deliberately not queried in v0.0.1; no sign-in data is sent to third-party services.
- A very large tenant should stream Entra logs to Log Analytics, Event Hub, Storage, or a SIEM instead of using a workstation collector as its primary archive.
- Raw sign-in logs contain personal and security-sensitive data. Protect the output directory with appropriate ACLs and retention controls.
