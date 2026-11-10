# Changelog

All notable changes to Defender XDR Story Seeder are documented here. Versions follow Semantic
Versioning. Tags use the repository convention `defender-xdr-story-seeder/v<version>`.

## 0.3.0-beta — 2026-11-10

- Add a supported evaluated-agent lab path that uses the Microsoft Agent 365 CLI to provision
  linked blueprints, agent identities, registrations, consented profile permissions, and optional
  governed MCP tooling.
- Add low, medium, and high target-risk profiles with explicit instructions, authentication modes,
  delegated Microsoft Graph scopes, MCP servers, and documented expected posture signals.
- Keep the requested profile advisory and state truthfully that Microsoft Defender calculates the
  final risk level asynchronously and might return a different result or `Not evaluated`.
- Store Agent 365 generated configuration and credentials only beneath the current user's local
  application-data folder; write only non-secret IDs and status to the project run manifest.
- Add dedicated manifest-driven cleanup that removes only the recorded Agent 365 instances and
  blueprints, leaves Defender alerts and incidents unchanged, and removes local secret-bearing
  state only after successful tenant cleanup.
- Make evaluated agents the default mode of the main bulk launcher, pass the created agent manifest
  directly into incident seeding, and cycle AI stories through that same agent pool.
- Make the normal bulk cleanup launcher also clean evaluated agents referenced by its run manifests,
  while retaining repeat-safe cleanup markers and strict manifest scoping.
- Reuse the original evaluated-agent manifest automatically when resuming a partial bulk run so a
  timeout cannot silently create a duplicate agent set.
- Add a separate, confirmation-protected current-user Graph authentication cache cleanup script for
  deliberately forcing a fresh sign-in without changing tenant data.
- Preserve the original inventory-only and Defender incident seeding paths for tenants that don't
  meet the Agent 365 CLI, licensing, consent, or service-rollout prerequisites.

## 0.2.4-beta — 2026-11-09

- Rename newly created agent blueprints, principals, identities, and registry cards to use the exact
  `[MXDR Demo]` prefix.
- Persist the Microsoft Graph delegated sign-in in the secure current-user cache and reuse it across
  separate seeding, registration-retry, and cleanup PowerShell processes.
- Verify the cached account and delegated scopes before reuse and stop automatically signing out at
  the end of each run.
- Request cleanup permissions during seeding so a later cleanup can normally reuse the same
  consented session without another interactive sign-in.
- Cycle AI incidents through the selected demo-agent pool while preserving the matching story
  profile when the AI incident count exceeds the agent count.
- Revise the 0.2.4 package in place with schema-3 manifests and deterministic per-alert correlation
  markers for ambiguous Microsoft Graph POST recovery.
- Reconcile `408`, `429`, transport, and server-error POST results against the incident and recent
  alerts before performing at most one controlled retry.
- Resume the existing partial incident at its first unrecorded stage instead of creating a duplicate
  incident; refuse unsafe partial schema-2 manifests that predate correlation markers.

## 0.2.3-beta — 2026-11-09

- Treat the optional `@odata.nextLink` property as absent on the final Agent ID blueprint page.
- Fix agent-only cleanup failing under StrictMode when blueprint discovery fits on one page.
- Preserve the exact `[DXR Demo]` prefix boundary and the existing alert/incident isolation.

## 0.2.2-beta — 2026-11-09

- Add a dedicated agent-only cleanup launcher that leaves Defender alerts and incidents untouched.
- Recursively discover `bulk-seed-run-*.json` manifests beneath a selected folder, deduplicate
  copied manifests by recorded agent object ID, and add blueprint discovery restricted to names
  beginning exactly with `[DXR Demo]`.
- Delete only recorded Agent 365 registrations, blueprints, child identities, and blueprint
  principals through their specialized Microsoft Graph endpoints.
- Treat already-absent objects as successful repeat cleanup and write an incremental
  `agent-cleanup-run-*.json` audit manifest.
- Add release packaging, offline validation, usage, permission, recovery, and troubleshooting
  documentation for agent-only cleanup.

## 0.2.1-beta — 2026-11-09

- Remove `managedByAppId` from Agent Registry creation requests when `ownerIds` already satisfies
  the API requirement; the blueprint was not the interactive calling application and could trigger
  `403 Forbidden` in enforcing tenants.
- Add a registration-only retry launcher that consumes an existing 0.2 manifest and never recreates
  agent identities, incidents, or alerts.
- Verify `AgentRegistration.ReadWrite.All` is present in the delegated token before retrying.
- Capture HTTP status, exception message, and the complete Graph error response in manifests.
- Stop repeated registry calls after the first tenant-wide 401/403 while continuing to create the
  requested Entra agent identity objects.
- Add offline coverage and troubleshooting documentation for the observed partial-agent outcome.

## 0.2.0-beta — 2026-11-09

- Add interactive incident, agent, and AI-proxy counts with Enter-to-accept defaults and an exact
  final confirmation; `-IncidentCount` remains available for automation.
- Preserve the fixed 10/11/12 alert cadence and the default 50-incident, 549-alert contract in mixed
  traditional and AI-proxy runs.
- Add optional direct Microsoft Graph creation of dormant agent identity blueprints, blueprint
  principals, child agent identities, and Agent 365 registry cards.
- Add low, medium, and elevated declared authority profiles without creating credentials, consent
  grants, runtime workloads, or dangerous administrative access.
- Add ten Security for AI manual proxy stories that include generated agent IDs while explicitly
  recording `manualProxy` and `agentAssetLinked: false`.
- Continue incident creation when an agent capability, license, role, consent, or rollout dependency
  is unavailable; persist per-component capability results and errors.
- Expand incremental manifests with agent objects, capability state, requested totals, and resumable
  plan offsets.
- Extend cleanup to recognize AI alert titles, delete only registry and blueprint IDs recorded by
  this package, and rely on Microsoft's documented blueprint cascade cleanup for child objects.
- Add Agent 365 architecture, limitations, permission-profile, cleanup, and recovery documentation.

### Known beta constraints

- Agent Registration and manual alert creation use Microsoft Graph beta endpoints.
- Dormant agents might not receive a Microsoft-calculated risk rating or appear in every Agent 365
  or Security for AI experience.
- Manual AI proxy incidents are not native Security for AI detections and do not create a native
  agent asset relationship.

## 0.1.0-beta — 2026-11-06

- Add a deterministic 50-incident catalog containing 549 total alerts.
- Guarantee 10–12 linked manual alerts per incident.
- Randomize enabled member identities read from Microsoft Entra ID and prefer mail-enabled users for
  email scenarios.
- Add 60 fictional endpoint names and 30 fictional shared-mailbox aliases.
- Cover Defender for Office 365, Defender for Identity, Defender for Cloud Apps, Defender for Cloud,
  Defender for Endpoint, and cross-domain XDR story contexts while retaining truthful Manual alert
  source attribution.
- Remove bracketed synthetic prefixes from newly created titles.
- Classify created incidents as expected authorized security testing.
- Add polling for eventual consistency before linking alerts to a newly created incident.
- Persist an incremental JSON run manifest after every created alert.
- Add selective cleanup that resolves seeded alerts and protects incidents containing unrelated
  active alerts.
- Add interactive browser and device-code sign-in options with automatic installation of the
  Microsoft Graph authentication module.
- Add offline validation, reproducible release packaging, CI, architecture, catalog, security, and
  troubleshooting documentation.

### Known beta constraints

- Manual alert creation uses Microsoft Graph beta.
- Cleanup resolves records but cannot delete them from Defender history.
- Fictional device evidence does not populate the global Defender device inventory.
- Microsoft-controlled service and detection source fields cannot be overridden.


