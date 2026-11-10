# Agent 365 and Security for AI behavior

## Two Agent 365 paths

Version 0.3 retains the original inventory-only path and adds an evaluated-agent lab path. The main
bulk launcher now orchestrates evaluated provisioning explicitly before incident seeding; the
underlying implementations remain separate so a preview or direct incident-seeding run never grants
agent permissions or creates credentials.

### Inventory-only path

For each requested demo agent, the seeder attempts this Microsoft-supported object chain:

```text
Entra agent identity blueprint
        |
        +--> agent identity blueprint principal
        |
        +--> child agent identity
        |
        +--> Agent 365 registry card
```

The objects are dormant governance records. The package does not deploy agent code, invoke a model,
create a runtime, upload a package, generate a client secret, store a user credential, or send test
prompts. Direct Microsoft Graph APIs are used; a ZIP is not needed for this identity-and-registry
path.

Agent APIs and Agent 365 are still rolling out and some are preview APIs. A tenant can support the
blueprint API but reject the child identity or registry call because of licensing, role assignment,
consent, national cloud, or service rollout. Each component result and error is written immediately
to the run manifest. Agent creation failures do not prevent the requested Defender manual proxy
stories from being created.

## Declared authority profiles

The catalog rotates three illustrative profiles:

| Profile | Mode | Declared permissions | Intent |
| --- | --- | --- | --- |
| Low | On behalf of user | `User.Read`, `Files.Read` | Narrow read access bounded by the consenting user. |
| Medium | On behalf of user | `User.Read` plus controlled mail, file, or calendar read/write | Demonstrate a broader delegated agent that deserves stronger review. |
| Elevated | Service to service | `User.Read.All` application permission | Demonstrate autonomous tenant-wide read authority without administrative write access. |

The permissions are declared on the blueprint. The tool does **not** create OAuth consent grants or
app-role assignments. It never grants blocked or dangerous administrative permissions simply to
force a high-risk appearance. In particular, it does not request `Application.ReadWrite.All`,
`RoleManagement.ReadWrite.All`, `User.ReadWrite.All`, or `Directory.AccessAsUser.All` for an agent.

Defender and Agent 365 calculate risk from supported posture, permission, activity, and telemetry
signals. Risk is not a writable field. Dormant agents may remain not evaluated, and the profile name
in this package must not be interpreted as a Microsoft-calculated risk rating.

## Manual AI proxy incidents

Microsoft Graph manual alerts do not expose an AI-agent entity type, and manual alerts cannot be
made to look like native Security for AI detections. Each AI scenario therefore records:

- `associationMode: manualProxy`;
- `agentAssetLinked: false`;
- the agent display name and authority profile;
- blueprint, blueprint application, blueprint-principal, child-identity, and registry IDs when the
  corresponding APIs succeeded; and
- truthful Manual / Defender XDR source attribution controlled by Microsoft.

The alert evidence uses supported `cloudApplication` and `oAuthApplication` entities as references,
alongside the same randomized tenant user, fictional endpoint, and reserved-domain evidence used by
traditional stories. These references are useful for demonstrations and investigation exercises but
do not create a native relationship to the Agent 365 asset record.

No genuine AI incident is required and the script never waits for one. Native Security for AI
alerts require actual supported agent activity and Microsoft telemetry; this project intentionally
does not manufacture that activity.

### Evaluated-agent lab path

`Start-DefenderEvaluatedAgentLab.ps1` delegates provisioning to Microsoft's supported `a365` CLI.
For every requested profile it creates a dedicated working directory, an `a365.config.json`, agent
instructions, the selected risk-profile metadata, and—when requested—a CLI-generated
`ToolingManifest.json`. The CLI then provisions and links:

```text
Agent identity blueprint
        |
        +--> consented blueprint permissions
        +--> child agent identity and identity grants
        +--> Agent 365 registration
        +--> governed MCP server permissions (medium/high profiles)
```

The evaluated path creates real configuration signals that Agent 365 and Defender can inspect. It
does not write a Defender risk field. Microsoft Defender independently combines supported risk
indicators, so a target profile can be assessed differently or remain `Not evaluated` when a
required platform, licensing, ingestion, or runtime signal is unavailable.

The generated instructions are runtime-profile input. The Agent 365 CLI provisions identity,
registration, permissions, and tooling, but doesn't build or host the model/orchestrator. The run
manifest therefore records `runtimeStatus: notDeployedBySeeder` and
`evaluationExpectation: configurationSignalsOnly` instead of claiming that the instructions or
runtime activity have reached Defender.

The provided profiles deliberately avoid directory-role and administrative write permissions:

| Target | Identity mode | Microsoft Graph delegated access | MCP tooling | Instructions |
| --- | --- | --- | --- | --- |
| Low | OBO | `User.Read` | None | Restrictive and human-confirmed. |
| Medium | OBO | User, file, and calendar read | Mail MCP | Read-oriented with confirmation before actions. |
| High | OBO + S2S grants | Broad file, mail, and calendar read/write | Mail MCP | Autonomous only inside the MXDR demo boundary. |

The Mail MCP server exposes write-capable tools. The scripts configure the server and consent its
blueprint permissions but do not invoke those tools or send mail. MCP server availability and exact
tool inventory are controlled by the tenant's Agent 365 rollout and policy.

Agent 365 generated configuration can contain a blueprint client secret. The evaluated path stores
that configuration beneath `%LOCALAPPDATA%\MXDRDemoAgentLab`, never in the project or release ZIP.
The audit manifest records paths, non-secret object IDs, statuses, and cleanup instructions only.

`Start-DefenderEvaluatedAgentCleanup.ps1` reads one exact lab manifest, removes the recorded agent
instance and blueprint through the Agent 365 CLI, and deletes the corresponding local state only
after both tenant cleanup operations succeed. It does not call Defender alert or incident APIs.

A hosted agent runtime is still required for runtime- and activity-dependent indicators. The
configuration-only lab can produce posture signals, tools, permissions, identities, and attack
surface relationships, but it does not claim to generate native Security for AI alerts or incident
blast radius without Agent 365 observability data.

## Capability and fallback states

The manifest `capabilities` object records the observed outcome:

- `entraAgentId`: `available`, `unavailable`, `pending`, or `notRequested`;
- `agentRegistry`: `available`, `unavailable`, `pending`, or `notRequested`;
- `agent365License`: `notDirectlyVerified` because there is no reliable license check required for
  this workflow; the API result is authoritative; and
- `defenderSecurityForAi`: `manualProxyOnly` or `notRequested`.

Each agent also carries per-component status and error text. `created` means all four object types
were returned. `partial` means at least one persisted and its ID was recorded. `proxyOnly` means the
incident story uses catalog metadata without claiming a tenant agent asset exists.

## Cleanup and recovery

Cleanup reads agent IDs only from local `bulk-seed-run-*.json` manifests. It first deletes a recorded
Agent 365 registration, then soft-deletes the recorded blueprint through the specialized blueprint
endpoint. Microsoft documents blueprint deletion as the cascade trigger for its child agent
identities, agent users, and blueprint principal. No name search or broad agent inventory deletion is
performed.

The seed manifest is sensitive tenant data and must remain under the ignored `artifacts` directory.
If a POST succeeded but its response was lost, the object ID might not be present in the manifest.
POST calls are not retried for exactly this reason: an automatic retry could create duplicates.
Review the Entra audit log and `[MXDR Demo]` object names before manual recovery.

Agent object deletion is recoverable for the Microsoft retention period because blueprint deletion
is a soft delete. Defender alert and incident cleanup is different: those records are resolved and
classified, not erased.

Version 0.2.2 also provides `Start-DefenderAgentCleanup.ps1` for agent-only removal. Point its
second argument at a parent folder such as Downloads and it recursively reads every
`bulk-seed-run-*.json`, deduplicates copied manifests, and deletes the recorded agent objects. The
launcher also lists blueprints and includes only names beginning exactly with `[MXDR Demo]`, which
catches a missing manifest. It never calls Defender alert or incident endpoints. The underlying
script can be run without `-Execute` to preview one or more manifests before deletion.

## Registration-only recovery

Version 0.2.1 includes `Start-DefenderAgentRegistrationRetry.ps1` for manifests where Entra objects
were created but Agent Registry returned an authorization error. It deliberately omits
`managedByAppId`: `ownerIds` satisfies the API's owner-or-managing-app requirement, while the
blueprint app ID is not the Microsoft Graph PowerShell client making the interactive request.

The retry operates only on agents that have a blueprint ID and no registration ID. It writes each
successful registration ID back to the original manifest. A failure stores the status code and full
Graph response. A persistent 403 after this correction indicates a tenant permission, license, or
service-rollout gate rather than a need to recreate the agent identities.

## Microsoft references

- [Create an agent identity blueprint](https://learn.microsoft.com/graph/api/agentidentityblueprint-post?view=graph-rest-1.0)
- [Create agent identities](https://learn.microsoft.com/entra/agent-id/create-delete-agent-identities)
- [Agent Registration API overview](https://learn.microsoft.com/microsoft-365/copilot/extensibility/api/admin-settings/agent-registration/overview)
- [Delete an agent identity blueprint](https://learn.microsoft.com/graph/api/agentidentityblueprint-delete?view=graph-rest-1.0)
- [Authorization in Microsoft Entra Agent ID](https://learn.microsoft.com/entra/agent-id/authorization-agent-id)
- [Install and use the Agent 365 CLI](https://learn.microsoft.com/microsoft-agent-365/developer/agent-365-cli)
- [Agent 365 CLI setup command](https://learn.microsoft.com/microsoft-agent-365/developer/reference/cli/setup)
- [Agent 365 CLI cleanup command](https://learn.microsoft.com/microsoft-agent-365/developer/reference/cli/cleanup)
- [Add and manage Agent 365 tools](https://learn.microsoft.com/microsoft-agent-365/developer/tooling)
- [AI agent posture risk in Microsoft Defender](https://learn.microsoft.com/defender-xdr/security-for-ai/ai-agent-risk-assessment)

