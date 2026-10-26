# Microsoft Intune Endpoint Readiness Collector

**Author:** Phil Kinsley — [phil.kinsley@outlook.com](mailto:phil.kinsley@outlook.com)  
**Collector version:** 1.0.5  
**Query manifest version:** 1.0.1

This package collects Microsoft Graph evidence for an Intune Endpoint Readiness Review. It produces normalized JSON for a separate scoring engine and report workflow. It does not assign readiness scores or Red, Amber, or Green ratings.

This tool lives at `Intune/IntuneReadinessCollector/` in [NexlinksRepo/Microsoft](https://github.com/NexlinksRepo/Microsoft). Check `collection.collectorVersion` in each output to identify the runtime version. The GitHub preparation changes documentation and packaging; collector scripts, manifests, schema, and existing tests retain their original 1.0.5 content.

Read [HOW-IT-WORKS.md](HOW-IT-WORKS.md) for a code walkthrough, evidence limits, privacy details, and the validation scope.

## Quick start: Contoso

Open PowerShell in this folder and run:

    .\Invoke-IntuneReadinessCollection.ps1 -TenantId 'contoso.com' -OutputPath .\runs\contoso-evidence.json

Sign in with an account authorized to read the Contoso tenant. Add -InstallGraphModule if the authentication module is missing.

The command produces:

- runs/contoso-evidence.json — normalized evidence, query results, warnings, and errors.

Add `-CaptureDebug` when investigating failed requests. It also writes `runs/contoso-evidence.debug.json`. Debug capture is off by default.

Use a new filename for each comparison run. Existing files at the selected output paths are overwritten.

## Package layout

    Intune/IntuneReadinessCollector/
      Invoke-IntuneReadinessCollection.ps1
      Test-ModernPolicyReport.ps1
      query-manifest.json
      intune-readiness.schema.json
      DATA-DICTIONARY.md
      README.md
      HOW-IT-WORKS.md
      tests/
        Collector.Tests.ps1
        Report.Offline.Tests.ps1
        Debug.Offline.Tests.ps1

      runs/  [created locally; excluded from Git]
        [new evidence, debug files, and probe results]


This release excludes evidence, debug output, and probe results from prior runs. Only the required query manifest and JSON Schema are included as JSON files.

## Requirements

- PowerShell 7 is recommended. The script is designed to support Windows PowerShell 5.1.
- Microsoft.Graph.Authentication is required for interactive sign-in or an existing SDK session. The full Microsoft.Graph and Microsoft.Graph.Beta.Reports modules are not required.
- Bearer-token runs use the built-in REST client and do not require the authentication module.
- Intune Graph endpoints require an active Intune license.
- Permissions, administrator consent, user roles, and Intune scope tags can affect which evidence is accessible.

Install the authentication module manually:

    Install-Module Microsoft.Graph.Authentication -Scope CurrentUser

Or let the interactive collector install it:

    .\Invoke-IntuneReadinessCollection.ps1 -InstallGraphModule -OutputPath .\runs\tenant-evidence.json

## Authentication

Choose one authentication mode per run.

### Interactive browser

The default mode opens sign-in, requests read-only scopes from the manifest, and keeps the authentication context within the current PowerShell process.

    .\Invoke-IntuneReadinessCollection.ps1 -TenantId '<tenant-id>' -OutputPath .\runs\tenant-evidence.json

Omit -TenantId if a tenant restriction is unnecessary. Use -ClientId for a custom public-client application registration.

### Device code

    .\Invoke-IntuneReadinessCollection.ps1 -UseDeviceCode -TenantId '<tenant-id>' -OutputPath .\runs\tenant-evidence.json

### Existing Graph SDK session

Connect in the same PowerShell process, then reuse the session:

    $manifest = Get-Content .\query-manifest.json -Raw | ConvertFrom-Json
    $scopes = @($manifest.queries.permissions | Sort-Object -Unique)
    Connect-MgGraph -TenantId '<tenant-id>' -Scopes $scopes
    .\Invoke-IntuneReadinessCollection.ps1 -UseGraphSdkSession -OutputPath .\runs\tenant-evidence.json

Verify the account and tenant before collecting:

    Get-MgContext | Select-Object Account, TenantId, Scopes

The collector checks that a context exists; it does not verify that an existing session belongs to the intended tenant. -TenantId belongs to interactive mode.

### Bearer token

    .\Invoke-IntuneReadinessCollection.ps1 -AccessToken $token -OutputPath .\runs\tenant-evidence.json

Supply a token issued for Microsoft Graph with the required permissions. The collector does not acquire or renew the token in this mode.

## Parameters

| Parameter | Purpose / default |
| --- | --- |
| -OutputPath | Evidence destination. Defaults to intune-readiness-evidence.json beside the script. Missing parent folders are created. |
| -ManifestPath | Alternate manifest; defaults to query-manifest.json beside the script. |
| -CaptureDebug | Enables detailed failed-request capture and a .debug.json sidecar. Off by default. |
| -Quiet | Suppresses normal collector progress messages. |
| -ExcludeBeta | Skips beta queries and records reduced-evidence warnings. |
| -IncludeFullDeviceIdentity | Retains selected device identity fields otherwise removed. This is not a full anonymization control. |
| -MaxRetryCount | Retries for HTTP 429, 500, 502, 503, and 504. Default 4; range 0–10. |
| -JsonDepth | Evidence JSON depth. Default 40; range 2–100. Low values can truncate nested evidence. |
| -TenantId | Restricts interactive sign-in to a tenant. |
| -ClientId | Custom public-client application for interactive sign-in. |
| -UseDeviceCode | Device-code sign-in in interactive mode. |
| -InstallGraphModule | Installs a missing authentication module for the current user in interactive mode. |
| -DisconnectWhenComplete | Disconnects an interactive session created by the collector after output is written. |
| -UseGraphSdkSession | Reuses an existing Graph context. |
| -AccessToken | Uses an existing bearer token. |

-TenantId, -ClientId, -UseDeviceCode, -InstallGraphModule, and -DisconnectWhenComplete belong to interactive mode and cannot be combined with -UseGraphSdkSession or -AccessToken.

## Read-only permissions

The full manifest uses:

    Organization.Read.All
    DeviceManagementManagedDevices.Read.All
    DeviceManagementServiceConfig.Read.All
    DeviceManagementConfiguration.Read.All
    DeviceManagementEndpointSecurity.Read.All
    DeviceManagementApps.Read.All
    LicenseAssignment.Read.All
    DeviceManagementRBAC.Read.All
    Policy.Read.All

Some policy inventory, settings, and assignment endpoints accept either configuration or endpoint-security permissions; these entries use permissionMode: any. The modern status reporting query declares DeviceManagementConfiguration.Read.All.

Interactive scope requests exclude beta-only queries when -ExcludeBeta is supplied. OAuth consent alone does not guarantee access to all tenant data.

## Evidence coverage

The collector includes:

- Tenant information, managed devices, enrollment configurations, and Autopilot.
- Compliance policies, assignments, setting summaries, and device status.
- Legacy configuration profiles and modern Settings Catalog / Endpoint Security policies, settings, assignments, and available deployment status.
- BitLocker/encryption evidence derived from device data.
- Windows Update profiles and assignments.
- Conditional Access policies.
- Defender onboarding and related device evidence.
- Mobile apps and assignments.
- Subscribed licensing SKUs.
- Intune role definitions and assignments.
- Managed app protection policies, configurations, and assignments.

See DATA-DICTIONARY.md for normalized fields and query-manifest.json for exact endpoints, versions, permissions, and expansions.

## Modern policy status correction

Modern configuration policies do not expose the legacy deviceStatuses relationship. Version 1.0.5 uses:

    POST https://graph.microsoft.com/beta/deviceManagement/reports/getConfigurationPolicyDevicesReport

Request body:

    {
      "filter": "(PolicyBaseTypeName eq 'DeviceManagementConfigurationPolicy') and (PolicyId eq '<policy-id>')",
      "skip": 0,
      "top": 100
    }

The collector uses skip/top pagination and maps Schema/Values columns to individual objects. It preserves report column names and adds _collectorParentId to link each record to its policy.

Modern rows differ from legacy deviceStatuses records. Downstream consumers must handle report columns. PolicyStatus was numeric in the tested response; the collector does not convert it into readiness ratings.

The supplied 1.0.5 release records prior live validation of this request shape. No live tenant collection was repeated during the October 25, 2026 GitHub preparation. Tenant-specific counts from that earlier run are omitted from this public README.

## Autopilot correction

Autopilot now uses the base v1.0 windowsAutopilotDeviceIdentities endpoint without $select. The original field list is selected locally after retrieval. This avoids the HTTP 500 observed with the previous request.

Returned identity counts depend on the tenant and permissions; no current live count was measured for this preparation.

## Debug capture

    .\Invoke-IntuneReadinessCollection.ps1 -CaptureDebug -OutputPath .\runs\tenant-debug-evidence.json

The sidecar replaces the evidence filename extension with .debug.json:

    runs/tenant-debug-evidence.debug.json

It captures terminal failed Graph queries with:

- Query ID, category, URI, HTTP status, and expected permissions.
- HTTP method and POST request body.
- Raw response body and parsed Graph error when available.
- Available request IDs, response date, and retry headers.
- bodyUnavailable when no response body is exposed.

Detailed diagnostics also appear on the corresponding evidence warning/error. Without -CaptureDebug, detailed capture is off.

This records terminal failures after retries, not every transient attempt, successful response, or full network trace. An empty failedQueries array means no terminal HTTP query failures were recorded. Exclusions and missing parent evidence still need review in the evidence warnings.

Authentication headers and access tokens are not captured. Error responses and query parameters can contain tenant or policy details.

## Interpreting results

Review:

1. collection.queryRuns — attempted URIs, status, record counts, and timestamps.
2. warnings — optional query failures, beta exclusions, and unavailable parent evidence.
3. errors — required query failures.

An empty errors array does not mean every query succeeded. Optional failures are warnings.

Category collectionStatus records successful versus failed request outcomes as complete, partial, failed, or not collected. Read warnings too: a category can be labelled complete while beta exclusions or unavailable parent evidence reduce coverage. Successful empty inventories skip child queries without NoParentResults. Unavailable parent evidence still generates a warning.

Empty status data following a failed query means status was not collected. It does not establish that no devices received the policy.

The scoring field stays null. Use separately versioned scoring rules after reviewing completeness.

## Reliability and beta dependencies

- Collection endpoints follow @odata.nextLink.
- Modern status reports use skip/top paging.
- HTTP 429 and selected 5xx responses use bounded exponential retries.
- HTTP 400 is not automatically retried.
- Query-level failures are recorded and collection continues.
- Authentication, invalid inputs, and output-writing failures can stop the run.
- Child records retain _collectorParentId.

Beta is used for modern policies and reports, security intents, Windows Update profiles/assignments, and Defender onboarding summary. Beta payloads can change. -ExcludeBeta reduces coverage and records warnings.

## Privacy defaults

Normalized managed-device records omit deviceName, userPrincipalName, userId, and azureADDeviceId by default.

Modern report rows omit DeviceName, UserName, UPN, UserPrincipalName, UserId, and AzureADDeviceId by default. -IncludeFullDeviceIdentity retains those fields.

The evidence still contains tenant/account metadata, device identifiers, policy/app names, and selected Autopilot fields such as serial numbers. Legacy status records and other Graph payloads can retain device/user details. These defaults remove selected fields; they do not fully anonymize the evidence.

Keep real output private. The repository ignores `runs/` and JSON files except the manifest and schema, but already tracked or force-added files can still be committed. Review staged files before publishing. Use an output path outside the checkout when practical.

## One-policy diagnostic

    .\Test-ModernPolicyReport.ps1 -TenantId 'contoso.com' -PolicyId '<modern-policy-id>'

The probe uses contoso.com as the example tenant. Supply your tenant and a modern policy ID. It compares four request bodies, requests the first five rows only, and writes results incrementally to runs/modern-policy-probe.json.

Successful results retain schemas and counts rather than device/user rows. Failure results retain available Graph error responses.

| Probe parameter | Purpose |
| --- | --- |
| -TenantId | Sign-in tenant; defaults to contoso.com. |
| -PolicyId | Modern policy ID; required from your tenant. |
| -UseGraphSdkSession | Reuses the current session and compares its tenant GUID directly to -TenantId. Supply the GUID in this mode. |
| -UseDeviceCode | Device-code sign-in. |
| -OutputPath | Probe result destination. |

The probe requires Microsoft.Graph.Authentication to be installed; it does not install the module.

## Offline verification

    Import-Module Pester -RequiredVersion 3.4.0
    $result = Invoke-Pester -Script .\tests\Collector.Tests.ps1 -PassThru
    if ($result.FailedCount -gt 0) { throw 'Collector checks failed.' }
    .\tests\Report.Offline.Tests.ps1
    .\tests\Debug.Offline.Tests.ps1

Checks cover package invariants and syntax, report request construction, paging, column mapping, privacy, empty/malformed responses, and diagnostic extraction.

The existing Pester suite uses Pester 3 syntax. It was run with Pester 3.4.0 during preparation; install that version separately if needed. Both standalone suites run without Pester or Microsoft Graph.

On October 25, 2026, all ten Pester checks and both standalone offline suites passed locally on PowerShell 7.6.5 and Windows PowerShell 5.1.26100.9711. The prepared GitHub workflow runs these checks on PowerShell 7 and Windows PowerShell 5.1. Hosted workflow execution remains unverified until the files are uploaded and Actions runs. Offline checks do not establish live API availability, permissions, or complete tenant coverage.

## Repository license

This package is prepared for the existing [GNU GPL v3 repository license](../../LICENSE). Phil Kinsley's author attribution is retained. No different license has been added.

## Version history

| Version | Change |
| --- | --- |
| 1.0.2 | Original baseline collector. |
| 1.0.3 | Replaced unsupported modern status expansion with reporting action; removed Autopilot $select; adjusted empty-parent handling. |
| 1.0.4 | Added opt-in -CaptureDebug and failed-query sidecar. |
| 1.0.5 | Added the live-confirmed PolicyBaseTypeName filter. |

## Microsoft references

- [Modern policy resource](https://learn.microsoft.com/en-us/graph/api/resources/intune-deviceconfigv2-devicemanagementconfigurationpolicy?view=graph-rest-beta)
- [Configuration policy device report](https://learn.microsoft.com/en-us/powershell/module/microsoft.graph.beta.reports/get-mgbetadevicemanagementreportconfigurationpolicydevicereport?view=graph-powershell-beta)
- [Report fields and filters](https://learn.microsoft.com/en-us/intune/device-management/reports/ref-graph-available-reports#devicestatusesbyconfigurationprofile)
- [Autopilot list endpoint](https://learn.microsoft.com/en-us/graph/api/intune-enrollment-windowsautopilotdeviceidentity-list)
- [Microsoft Q&A reproduction of Autopilot $select failure](https://learn.microsoft.com/en-us/answers/questions/2238154/select-queryparameter-not-working-on-windowsautopi)
- [Managed devices endpoint](https://learn.microsoft.com/en-us/graph/api/intune-devices-manageddevice-list?view=graph-rest-1.0)
- [Mobile app assignments](https://learn.microsoft.com/en-us/graph/api/intune-apps-mobileappassignment-list?view=graph-rest-1.0)

