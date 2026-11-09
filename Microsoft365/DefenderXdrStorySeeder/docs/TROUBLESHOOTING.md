# Troubleshooting

## The confirmation says “Create 3 synthetic alerts and one incident”

You launched an obsolete proof-of-concept package. Enter `N`, extract the current release into a new
directory, and run `Start-DefenderBulkSeed.ps1`. The current default prompt says it will create 50
incidents, exactly 549 alerts, and the optional dormant AI-agent totals.

## `Microsoft.Graph.Authentication` was not found

The script normally installs the module for the current user. If installation is blocked by policy,
install it from an approved PowerShell Gallery source and retry:

```powershell
Install-PSResource Microsoft.Graph.Authentication -Scope CurrentUser -TrustRepository
```

For systems using PowerShellGet:

```powershell
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser -Repository PSGallery
```

Reopen PowerShell if the newly installed module is not visible in `$env:PSModulePath`.

## The browser sign-in window is hidden

Windows Web Account Manager can place the interactive window behind another application. Check the
taskbar or use device-code authentication:

```powershell
pwsh -File .\Start-DefenderBulkSeed.ps1 'global.admin@contoso.com' -UseDeviceCode
```

## The script signed in as the wrong administrator

The package will stop before tenant operations if the cached Microsoft Graph account does not match
the supplied UPN. End the old session, then rerun the launcher:

```powershell
Disconnect-MgGraph
```

Seeding and cleanup otherwise reuse the secure current-user Graph cache across separate PowerShell
processes. Do not run `Disconnect-MgGraph` between them unless you intentionally want to sign out.

## Consent or authorization failure

Confirm that the account can consent to or has already been granted the delegated permissions in the
README. Microsoft documents Security Operator and Security Administrator as supported Defender roles
for the write APIs. A role activation delay can require a new sign-in.

## `400 Bad Request` while updating an incident

Use the current version. Earlier packages could serialize a one-item `customTags` collection as a
scalar. Version `0.2.4-beta` does not depend on a synthetic custom tag and sends only supported
incident fields.

## `404 Not Found` after creating the first alert

A new incident can be eventually consistent. The seeder polls the incident before linking the next
alert. Temporary GET/PATCH failures are retried with exponential backoff. If the run ultimately
stops, inspect the partial manifest before resuming.

## A run stopped after creating some alerts

Use the latest `artifacts\bulk-seed-run-*.json` with the same incident, agent, and AI-incident counts
plus `-ResumeManifestPath`. A schema-3 manifest reuses the existing partial incident, checks its
pending correlation marker, and continues at the first unrecorded stage. Do not resume a partial
schema-2 manifest created by the earlier 0.2.4 package; the revised script rejects it because that
manifest cannot prove whether the timed-out POST created an alert. Clean up that old run and start a
fresh one instead.

## Agent creation is partial or unavailable

This can mean the tenant lacks an Agent 365 license, the preview API has not reached the tenant, the
signed-in account lacks an Agent ID role, or consent was not granted for an optional agent scope.
The manifest records each blueprint, principal, identity, and registration result separately. The
incident run continues with `manualProxy` stories and does not claim that a native agent asset was
linked.

If blueprints, principals, and identities show `created` but registration shows `unavailable`, run
the 0.2.1 registration-only retry against the original manifest. Do not rerun the bulk seeder:

```powershell
pwsh -File .\Start-DefenderAgentRegistrationRetry.ps1 `
  'global.admin@contoso.com' `
  'C:\path\to\bulk-seed-run-20261109-170925.json'
```

If the corrected request still returns 403, inspect `registrationRetries[].failed[].responseBody`
in the manifest. That response distinguishes missing consent from an Agent 365 license or rollout
gate.

## Dormant agents have no Defender risk rating

This is expected. The script cannot write a risk value and intentionally creates no runtime or
telemetry. Agent 365 and Defender determine posture and risk from supported tenant signals. Review
the declared authority profile and the IDs in the manifest rather than treating the profile label as
a Microsoft-calculated risk.

## I need to remove only the demo agents

Do not use the bulk cleanup if the alerts and incidents should remain. Run the dedicated launcher
and point it at the parent folder that contains the downloaded seeder packages:

```powershell
pwsh -File .\Start-DefenderAgentCleanup.ps1 `
  'global.admin@contoso.com' `
  "$env:USERPROFILE\Downloads"
```

It recursively finds seed manifests, deduplicates their recorded object IDs, and includes only
additional blueprint names beginning with `[MXDR Demo]`. A 404 means cascade cleanup or an earlier
run already removed that object and is safe to ignore.

## Cleanup found zero alerts

Possible explanations:

- alerts are already resolved;
- Defender retention no longer exposes them through Graph;
- they were created with titles not present in this release or the legacy POC allowlist;
- they are not Manual alerts; or
- the signed-in account cannot read Defender alerts.

Run the underlying cleanup script without `-Execute` to preview safely. Avoid `-AllManualAlerts`
unless you intend to select unrelated manual alerts too.

## Cleanup protected an incident

The incident contains at least one other active alert that does not match the seeder. Matching seeded
alerts can still be resolved, but the incident is intentionally left open. Review that incident in
Defender and close it manually only when appropriate.

## Fictional endpoints are missing from Assets > Devices

This is expected. The script creates device evidence attached to alerts; it does not onboard or
discover devices. Look inside the incident's **Artifacts > Assets** view.

## All alerts show Manual / Microsoft Defender XDR

This is expected and required by the platform. Microsoft sets service and detection source fields on
manual alerts. Scenario narratives and evidence vary by workload, but source attribution cannot be
overridden.

## Rate limiting or repeated transient failures

Increase `-DelayMilliseconds` on the underlying script. Seeder delays must remain between 500 and
30000 milliseconds. Cleanup accepts 0 through 5000, but values below 500 are more likely to be
throttled during a large cleanup.

## Collecting a safe diagnostic

Share the project version, PowerShell version, operation, HTTP status, and redacted error text. Do
not publish manifests, tenant IDs, UPNs, alert IDs, incident IDs, portal URLs, access tokens, or Graph
response bodies containing tenant evidence.


