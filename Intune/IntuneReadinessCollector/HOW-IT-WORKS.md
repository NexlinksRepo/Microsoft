# How the collector works

**Author:** Phil Kinsley  
**Collector:** 1.0.5  
**Walkthrough prepared:** October 25, 2026

The collector takes a point-in-time snapshot of Intune and related Entra configuration through Microsoft Graph. It organizes the results into one evidence file that a separate tool can score or turn into a report.

## Execution flow

1. **Load the query manifest.** `query-manifest.json` defines 35 query templates, their API versions, permissions, parent relationships, and output names. Three templates are marked required: tenant organization, managed devices, and compliance policies. A template can generate many requests when it expands one request per policy or app.
2. **Authenticate.** The default opens Microsoft Graph sign-in. Device code, an existing Graph SDK session, or a supplied bearer token are alternatives. Interactive sign-in requests the distinct permissions declared by the selected manifest entries. Only the authentication module is needed for SDK modes.
3. **Collect parent inventories.** It reads devices, policies, apps, enrollment objects, role information, and licenses. Collection requests follow `@odata.nextLink` until there are no more pages.
4. **Expand child evidence.** Each policy or app ID supplies the `{id}` in assignment, settings, or status requests. Child rows receive `_collectorParentId` so downstream tools can join them to their parent.
5. **Read modern policy reports.** Modern configuration status uses a report-reading POST action. The collector requests 100 rows at a time, filters by policy type and policy ID, maps the report's `Schema` and `Values` into objects, and advances `skip` until the report is exhausted. This POST retrieves report data; it does not update a policy.
6. **Handle failures.** HTTP 429, 500, 502, 503, and 504 receive up to four retries by default, with delays of 2, 4, 8, and 16 seconds. Required query failures become errors; optional failures become warnings. Collection continues after individual query failures.
7. **Normalize and summarize.** The collector groups evidence into 11 categories and calculates counts, state distributions, sync-age observations, and encryption percentages. These calculations are observations, not readiness scores.
8. **Write local output.** The evidence file contains metadata, normalized records, query outcomes, warnings, and errors. `-CaptureDebug` also creates a `.debug.json` sidecar containing terminal failed-request details. Existing destination files are overwritten.

## What each category contains

| Category | Evidence and observations |
| --- | --- |
| Managed devices and enrollment | Device inventory, ownership, enrollment, last sync, enrollment restrictions, Autopilot records, and enrollment assignments. |
| Compliance | Compliance policies, assignments, setting summaries, device status, and tenant compliance summary. |
| Endpoint Security / Settings Catalog | Legacy profiles, modern policies, settings, assignments, status reports, and security intents. |
| BitLocker / encryption | Windows device encryption flags and policy objects containing encryption-related terms. |
| Windows Update | Legacy update rings, feature/quality update profiles, assignments, and paused-ring counts. |
| Conditional Access | Policy states and counts of policies using selected device/app grant controls. |
| Defender | Related policy objects, device threat-state counts, and available onboarding summary. |
| Mobile apps | App inventory, types, publishing states, assignments, and assignment intents. |
| Licensing | Subscribed SKUs, consumed units, and Intune-related service plans. |
| Intune RBAC | Role definitions, custom-role counts, assignments, and member-reference counts. |
| App protection | iOS/Android app protection policies, targeted configurations, and assignments. |

## Files and responsibilities

| File | Role |
| --- | --- |
| `Invoke-IntuneReadinessCollection.ps1` | Authentication, requests, retries, pagination, normalization, and output writing. |
| `query-manifest.json` | The query plan: endpoints, permissions, expansions, and result keys. |
| `intune-readiness.schema.json` | A JSON Schema describing the evidence envelope. The collector does not automatically validate its output against this schema. |
| `DATA-DICTIONARY.md` | The meaning and origin of output fields. |
| `Test-ModernPolicyReport.ps1` | An optional signed-in diagnostic that compares four request bodies for one policy; it is not part of a normal collection run. |
| `tests/` | Offline package, report-mapping, pagination, privacy-filter, and error-extraction checks. |

## What the output can establish

The file shows what Graph returned to the selected identity at collection time. It does not inspect endpoints directly, simulate Conditional Access, prove that every assigned device received a policy, or establish effective enforcement. Policy discovery for BitLocker and Defender uses keyword matching across policy objects, so it needs practitioner review.

`scoring` is always null. No scoring engine, readiness thresholds, Word generator, or PDF generator is included in this package.

Review `collection.queryRuns`, `warnings`, and `errors` together. An empty error list can coexist with optional failures. Category `complete` is based on successful versus failed requests; beta exclusions and unavailable child evidence can still appear as warnings. A low count after a failed query is missing evidence, not proof of a healthy tenant.

## Privacy and local effects

The default manifest requests read-only Graph permissions. The supplied scripts use GET requests and the report-reading POST action. They do not create, assign, delete, or remediate tenant policies or devices.

The script writes local files, can create their parent folders, and can install `Microsoft.Graph.Authentication` for the current user when `-InstallGraphModule` is explicitly supplied. Sign-in can display browser or device-code prompts. `-DisconnectWhenComplete` disconnects a session the collector created after a successful output write; it is not a cleanup guarantee after an earlier terminating error.

Selected managed-device and modern-report identity fields are removed by default. Other evidence can retain device/user information, tenant and signed-in account details, IDs, policy/app names, assignments, and Autopilot serial numbers. Legacy status rows are not passed through the modern-report identity filter. Debug responses can contain tenant information. Treat all real output as sensitive.

The repository ignores JSON except the two required source JSON files, and ignores `runs/`. Those rules reduce accidental commits; files already tracked or force-added can still be published. Keep custom output paths outside a public checkout and review staged files before upload.

## Current limitations

- The default Graph host and authentication environment target the global Microsoft cloud. Sovereign-cloud support has not been verified.
- Beta queries can change or become unavailable. `-ExcludeBeta` reduces coverage and records warnings.
- Existing SDK-session mode checks that a session exists, but does not enforce an intended tenant. Verify `Get-MgContext` first. Supplied bearer tokens are not acquired or refreshed by the collector.
- The one-policy probe compares `Get-MgContext().TenantId` directly to `-TenantId` in existing-session mode. Use the tenant GUID for that mode rather than a domain name.
- The JSON Schema describes a general envelope, not a detailed contract for every Graph payload or category field.
- A collection run can write output and finish successfully while recording query errors. Automation must inspect the output, not just the process exit code.

## Validation for this preparation

The original package's ten Pester checks and both standalone offline suites passed locally on PowerShell 7.6.5 and Windows PowerShell 5.1.26100.9711 with Pester 4.10.1. These are offline checks; no tenant sign-in or live collection was performed for this GitHub preparation. The supplied README's older live-validation counts are not included as current or universal results.

Microsoft documents the [configuration policy device report action](https://learn.microsoft.com/en-us/powershell/module/microsoft.graph.beta.reports/get-mgbetadevicemanagementreportconfigurationpolicydevicereport?view=graph-powershell-beta) and the [Autopilot inventory endpoint](https://learn.microsoft.com/en-us/graph/api/intune-enrollment-windowsautopilotdeviceidentity-list?view=graph-rest-1.0). Documentation confirms the interfaces; offline tests do not prove current tenant access or live response behavior.
