# Catalog and evidence model

## Attack catalog

`catalog/attack-catalog.json` contains an `attacks` array with exactly 50 objects for version
`0.2.0-beta`.

Each attack defines:

| Field | Meaning |
| --- | --- |
| `id` | Stable one-based catalog identifier. |
| `title` | Incident display name and stage-one alert title. |
| `workload` | Scenario context: `Email`, `Identity`, `Endpoint`, `CloudApp`, `DefenderForCloud`, or `Hybrid`. |
| `category` | MITRE ATT&CK-style alert category accepted by Defender. |
| `severity` | `informational`, `low`, `medium`, or `high`. |
| `mitreTechniques` | Technique identifiers associated with the first alert. |
| `description` | Detailed narrative; supports `{{UserPrincipalName}}` and `{{DeviceName}}` tokens. |
| `summary` | Short incident overview. |
| `recommendedActions` | Analyst response guidance. |

The current workload distribution is:

| Context | Stories |
| --- | ---: |
| Endpoint | 21 |
| Hybrid | 7 |
| Identity | 7 |
| Email | 6 |
| Cloud App | 5 |
| Defender for Cloud | 4 |

The current severity distribution is 28 high, 17 medium, 3 low, and 2 informational stories.

## Shared stages

The first alert uses the catalog title and narrative. The remaining alerts rotate through shared
stages such as authentication anomaly, command execution, persistence, credential access,
discovery, lateral movement, collection, command-and-control, exfiltration, and impact.

The stage count is selected per incident to guarantee 10–12 alerts. Shared titles are also part of
the cleanup allowlist, so changing one requires a corresponding cleanup and test change.

## Entity definitions

Depending on workload and stage, alerts can include:

- tenant user UPNs;
- tenant or fictional mailbox addresses;
- fictional device names;
- documentation-reserved IP addresses and URLs;
- deterministic file hashes and process evidence; and
- fictional Azure resource identifiers for Defender for Cloud context.

Entity definitions are evidence only. They do not create the referenced Microsoft 365 or Azure
resource.

## AI-agent catalog

`ai-agent-catalog.json` contains ten profiles. Each defines a dormant agent name, purpose, authority
profile, execution mode, declared permissions, and a manual AI proxy story. AI stages can also use
`{{AgentName}}`, `{{AuthorityProfile}}`, `{{ExecutionMode}}`, `{{BlueprintId}}`,
`{{AgentIdentityId}}`, and `{{RegistrationId}}` tokens.

An AI scenario adds supported `cloudApplication` evidence and, when creation succeeded,
`oAuthApplication` evidence containing the blueprint application ID. These are references only. The
manifest remains authoritative that `agentAssetLinked` is false.

## Endpoint roster

`endpoint-roster.json` contains an `endpoints` array. Each entry has:

- `name`: fictional hostname;
- `department`: business context; and
- `platform`: device platform narrative.

Keep names fictional and avoid copying hostnames from a real environment.

## Mailbox roster

`mailbox-roster.json` contains a `mailboxes` array. Each entry has:

- `alias`: local part combined with the administrator's tenant domain; and
- `displayName`: narrative display name.

These addresses are not provisioned. Avoid aliases that identify real people.

## Editing rules

1. Use valid JSON encoded as UTF-8.
2. Keep catalog IDs unique and sequential.
3. Use only the supported severity values.
4. Keep `mitreTechniques` as an array even when it has one item.
5. Preserve fictional evidence and documentation-reserved network values.
6. Update cleanup title matching if shared stage titles change.
7. Update the documented totals and changelog if the catalog length or alert formula changes.
8. Run `pwsh -File .\tests\Offline.Tests.ps1` and `pwsh -File .\Build-Release.ps1`.
