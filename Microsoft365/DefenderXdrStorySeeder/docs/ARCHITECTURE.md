# Architecture and data flow

## Evaluated-agent lab boundary

Version 0.3 adds an independent Agent 365 provisioning boundary alongside the Defender incident
seeder. `Invoke-DefenderEvaluatedAgentLab.ps1` builds a deterministic profile plan, writes
per-agent configuration beneath the current user's local application-data directory, and delegates
tenant mutation to Microsoft's `a365` CLI. It does not reuse the inventory-only Graph construction
functions because the CLI is the supported source for linked registrations, identity grants,
blueprint consent, and tooling metadata.

```text
agent-risk-profiles.json
          |
          v
evaluated-agent planner
          |
          +--> local a365 config + instructions + ToolingManifest
          |
          +--> a365 setup all
          +--> a365 setup permissions custom
          +--> a365 setup permissions mcp
          |
          v
non-secret evaluated-agent-lab-run manifest
          |
          v
a365 cleanup instance + cleanup blueprint
```

The project manifest is incremental and contains no client secret or token. Secret-bearing CLI
state remains beneath `%LOCALAPPDATA%\MXDRDemoAgentLab\<runId>`. Cleanup deletes local state only
after both recorded tenant cleanup operations succeed. Defender incident and alert APIs are outside
this boundary.

The low/medium/high profile value is an input to configuration, not an output from Defender.
Defender independently evaluates the resulting supported signals and can assign a different rating.

## Components

| Component | Responsibility |
| --- | --- |
| `Start-DefenderBulkSeed.ps1` | Minimal executing launcher that requires only a UPN. |
| `Invoke-DefenderBulkSeeder.ps1` | Planning, authentication, identity discovery, alert creation, incident updates, retries, and manifests. |
| `DefenderXdrStorySeeder.Authentication.ps1` | Current-user Graph session caching, account validation, and delegated-scope validation. |
| `DefenderXdrStorySeeder.Agent365.ps1` | Dormant blueprint, principal, child identity, and registry-card creation. |
| `Start-DefenderAgentRegistrationRetry.ps1` | UPN-first launcher for retrying only missing registry cards from a manifest. |
| `Invoke-DefenderAgentRegistrationRetry.ps1` | Scope validation, registration-only recovery, detailed error capture, and incremental manifest updates. |
| `Start-DefenderAgentCleanup.ps1` | UPN-first launcher for deleting only recorded demo agents. |
| `Invoke-DefenderAgentCleanup.ps1` | Recursive manifest discovery, ID deduplication, specialized agent-object deletion, and cleanup manifests. |
| `Start-DefenderBulkCleanup.ps1` | Minimal executing cleanup launcher. |
| `Invoke-DefenderBulkCleanup.ps1` | Active-alert discovery, safe selection, resolution, incident protection, and cleanup manifests. |
| `catalog/attack-catalog.json` | Fifty primary incident stories and their first alert. |
| `catalog/endpoint-roster.json` | Sixty fictional endpoint identities. |
| `catalog/mailbox-roster.json` | Thirty fictional mailbox aliases. |
| `catalog/ai-agent-catalog.json` | Ten AI profiles and manual proxy story definitions. |

## Seeder flow

```text
Catalog + rosters
       |
       v
Build deterministic plan ----> preview and stop when -Execute is absent
       |
       v
Delegated Graph sign-in or cached-session reuse (verified UPN and scopes)
       |
       +----> GET /v1.0/users (enabled member identities)
       |
       +----> optional Agent ID blueprint/principal/identity POSTs
       |
       +----> optional POST /beta/copilot/agentRegistrations
       |
       v
POST /beta/security/alerts_v2 (first manual alert)
       |
       +----> Defender creates a new incident
       |
       v
Poll incident until addressable
       |
       v
POST 9-11 more manual alerts with linkToIncident
       |
       v
PATCH incident metadata, classification, determination, and status
       |
       v
Persist artifacts/bulk-seed-run-*.json after every alert
```

Before each alert POST, schema-3 manifests persist a deterministic marker derived from the run,
catalog item, and stage. An ambiguous `408`, `429`, transport, or server-error result triggers a
read-back through the incident-alert relationship and the recent-alert collection. A recovered
marker is treated as the successful response. Only when no matching alert appears during the
reconciliation window is the POST retried once. GET and PATCH requests use bounded exponential
retries.

If the process stops, resume reuses the trailing partial incident record, reconciles any pending
marker, and starts at the first unrecorded stage. Partial schema-2 manifests are rejected because
they cannot distinguish an absent alert from a successful POST whose response was lost.

Agent and registry POSTs are also not retried. Their results are persisted after every requested
agent. Unsupported components fall back independently to a manual proxy record, allowing the
incident plan to finish without claiming a native asset association.

## Determinism

The release catalog is ordered from 1 through 50. Incident `n` receives:

- `10 + ((n - 1) mod 3)` alerts;
- a repeatable endpoint, identity, and mailbox selection derived from `RandomSeed`;
- the catalog story as stage 1; and
- enough shared attack stages to reach the required alert count.

For catalog items 1–50, the distribution is 17 incidents with 10 alerts, 17 with 11 alerts, and 16
with 12 alerts, totaling 549.

AI incidents replace the final `AiIncidentCount` slots in the selected plan. They do not increase
the incident total. Therefore the default mixed plan still contains exactly 50 incidents and 549
alerts. When `AiIncidentCount` exceeds `DemoAgentCount`, incident associations cycle through the
selected agent pool and each incident uses the story definition belonging to that agent position.

Authentication uses the Microsoft Graph SDK's `CurrentUser` context. A successful delegated sign-in
is securely cached and can be reused by a later `pwsh -File` seeding, retry, or cleanup process. Each
script verifies the requested UPN and all required scopes before use. The package deliberately does
not call `Disconnect-MgGraph`; the operator can run that command to explicitly end the session.

Changing `RandomSeed` changes the shuffle but not the number or titles of incidents and alerts.

## Identity and mailbox behavior

The seeder reads `id`, `displayName`, `userPrincipalName`, `mail`, `accountEnabled`, and `userType`
from Microsoft Graph. It keeps enabled member users with a UPN. The supplied administrator is
excluded when at least one other eligible identity exists. Email scenarios prefer identities with a
populated `mail` value.

Fictional mailbox aliases are combined with the domain portion of the supplied UPN. This produces
evidence identifiers only; Exchange Online objects are not created.

## Endpoint evidence

Endpoint records are entity definitions attached to manual alerts. They use realistic but fictional
device names and platform context. No call creates, joins, registers, enrolls, or onboards a device.
Consequently, devices can appear in incident evidence but not in the global Defender device
inventory.

## Workload context and attribution

Attack definitions carry a workload context. Entity combinations and narrative text are selected to
look appropriate for email, identity, endpoint, cloud-application, Azure-resource, and hybrid
stories. The API, however, creates `manualAlert` objects. Defender sets the detection and service
source. The project does not attempt to spoof a first-party detection product.

AI proxy stories follow the same rule. Supported cloud-application and OAuth-application evidence
can reference a generated agent's IDs, but the manifest explicitly records `manualProxy` and
`agentAssetLinked: false`. See [Agent 365 and Security for AI behavior](AGENT365.md).

## Cleanup flow

```text
GET active /v1.0/security/alerts_v2 pages
       |
       v
Keep detectionSource=manual and known normalized titles
       |
       v
Identify incidents containing any unmatched active alert
       |
       +----> protect those incidents from closure
       |
       v
PATCH matched alerts to resolved / expected security testing
       |
       v
PATCH only safe, fully successful incidents to resolved
       |
       +----> DELETE recorded Agent 365 registrations
       |
       +----> soft-delete recorded blueprints (Microsoft cascade cleanup)
       |
       v
Persist artifacts/cleanup-run-*.json after every operation
```

The cleanup manifest supports repeatable recovery: a subsequent run selects only alerts still
active. Failures do not cause already completed updates to be reversed.

Agent-only cleanup is a separate path. It reads `bulk-seed-run-*.json` files and supplements them
with a blueprint list filtered client-side to names beginning exactly with `[MXDR Demo]`. It calls
only the specialized registration, blueprint, child-identity, and blueprint-principal delete
endpoints and does not read or update Defender alerts or incidents. Blueprint cascade cleanup can
make later child-object deletes return 404; that result is recorded as `alreadyAbsent` and is
considered successful.

## Trust boundaries

- Microsoft Graph and the Defender backend are authoritative for alert and incident state.
- Tenant identity values are trusted only as identifiers returned by Graph and are written to local
  manifests; they are not executed.
- Catalog JSON is local code-adjacent configuration. Review changes through source control.
- Generated manifests are sensitive tenant data and must stay outside the repository.

