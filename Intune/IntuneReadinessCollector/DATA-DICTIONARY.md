# Data dictionary

All counts and percentages are evidence summaries. They are not Microsoft scores and are not RAG decisions. Arrays under `data` retain normalized Graph records; child records include `_collectorParentId`.

## Envelope

| Field | Meaning | Source |
|---|---|---|
| `schemaVersion` | Contract version for downstream consumers. | Collector constant |
| `assessmentType` | Identifies this document as readiness evidence. | Collector constant |
| `scoring` | Always `null`; reserved to make separation explicit. | Collector constant |
| `tenant.*` | Tenant ID, display name, type, creation time, and verified domains. | `GET /v1.0/organization` |
| `collection.*` | Collector/manifest version, times, auth mode, privacy mode, beta flag, and per-query audit trail. | Collector runtime |
| `warnings[]` | Non-fatal omissions, optional endpoint failures, and beta exclusions. | Collector runtime |
| `errors[]` | Failures of manifest entries marked `required`. | Collector runtime |

Every category contains `collectionStatus`, `evidenceSummary`, `data`, `warnings`, and `errors`. Status describes request outcomes rather than security posture. Review warnings as well: a category marked complete can still have beta exclusions or missing parent evidence.

## Managed devices and enrollment

| Field | Meaning | Graph source |
|---|---|---|
| `data.managedDevices[]` | Device OS, ownership, enrollment/management state, sync, compliance, encryption, model, and threat state. Selected identity fields are omitted by default; device IDs remain. | `/v1.0/deviceManagement/managedDevices` |
| `data.enrollmentConfigurations[]` | Enrollment restrictions and configuration objects. | `/v1.0/deviceManagement/deviceEnrollmentConfigurations` |
| `data.enrollmentConfigurationAssignments[]` | Assignment targets for each enrollment configuration. | `/v1.0/deviceManagement/deviceEnrollmentConfigurations/{id}/assignments` |
| `data.autopilotDevices[]` | Windows Autopilot registered identities and enrollment state. | `/v1.0/deviceManagement/windowsAutopilotDeviceIdentities` |
| `evidenceSummary.totalManagedDevices` | Count returned by Intune. | Derived from managed devices |
| `windowsDevices` | Devices whose OS begins with Windows. | Derived |
| `activeWindowsDevices30Days` | Windows devices synced in the last 30 days. | Derived at collection time |
| `syncedWithin7Days`, `staleOver30Days` | Recent and stale device counts. Missing last-sync is stale. | Derived |
| `ownerTypes`, `enrollmentTypes`, `managementAgents` | Count maps preserving Graph enum values. | Derived |

## Compliance

| Field | Meaning | Graph source |
|---|---|---|
| `data.policies[]` | Platform-specific policy objects, including controls exposed on each derived type. | `/v1.0/deviceManagement/deviceCompliancePolicies` |
| `data.assignments[]` | Targets for each policy. | `/v1.0/deviceManagement/deviceCompliancePolicies/{id}/assignments` |
| `data.settingStateSummaries[]` | Setting-level compliant, noncompliant, error, conflict, unknown, not-applicable, and remediated counts. | `/v1.0/deviceManagement/deviceCompliancePolicies/{id}/deviceSettingStateSummaries` |
| `data.deviceStatuses[]` | Per-policy device deployment status records. | `/v1.0/deviceManagement/deviceCompliancePolicies/{id}/deviceStatuses` |
| `data.tenantDeviceStateSummary[]` | Tenant-wide device compliance state counts. | `/v1.0/deviceManagement/deviceCompliancePolicyDeviceStateSummary` |
| `evidenceSummary.*` | Policy/type/assignment/setting counts plus the tenant state object. | Derived |

## Endpoint Security and Settings Catalog

| Field | Meaning | Graph source |
|---|---|---|
| `data.legacyProfiles[]` | Legacy device configuration profiles. | `/v1.0/deviceManagement/deviceConfigurations` |
| `data.legacyAssignments[]` | Legacy profile targets. | `/v1.0/deviceManagement/deviceConfigurations/{id}/assignments` |
| `data.modernPolicies[]` | Modern Settings Catalog and Endpoint Security policy metadata. | `/beta/deviceManagement/configurationPolicies` |
| `data.modernSettings[]` | Setting instances and values, linked by `_collectorParentId`. | `/beta/deviceManagement/configurationPolicies/{id}/settings` |
| `data.modernAssignments[]` | Modern policy targets. | `/beta/deviceManagement/configurationPolicies/{id}/assignments` |
| `data.legacyDeviceStatuses[]` | Legacy per-policy device deployment status. The modern-report identity filter does not apply to these rows. | `/v1.0/deviceManagement/deviceConfigurations/{id}/deviceStatuses` |
| `data.modernDeviceStatuses[]` | Report columns mapped from Schema/Values, with selected identity fields removed by default and `_collectorParentId` added. | `POST /beta/deviceManagement/reports/getConfigurationPolicyDevicesReport` |
| `data.securityIntents[]` | Template-based baseline/Endpoint Security policy objects. | `/beta/deviceManagement/intents` |
| `evidenceSummary.*` | Object, platform, technology, setting, and assignment counts. | Derived |

## BitLocker and encryption

This is a derived evidence view, not an extra API family.

| Field | Meaning | Source |
|---|---|---|
| `data.deviceEncryptionEvidence[]` | Windows device ID, encryption flag, last sync, and compliance state. | Managed devices |
| `data.policyEvidence[]` | Policy objects containing BitLocker/encryption terms. This is discovery evidence, not proof of effective enforcement. | Compliance and configuration policy payloads |
| `activeWindowsDevices30Days` | Denominator used for the encryption observation. | Derived |
| `encryptedActiveWindowsDevices` | Active Windows devices where `isEncrypted` is true. | Derived |
| `encryptedActiveWindowsPercent` | Percentage to two decimals; null when denominator is zero. | Derived |

## Windows Update

| Field | Meaning | Graph source |
|---|---|---|
| `data.updateRings[]` | Legacy configuration objects typed `windowsUpdateForBusinessConfiguration`. | `/v1.0/deviceManagement/deviceConfigurations` |
| `data.featureUpdateProfiles[]` | Feature update profiles. | `/beta/deviceManagement/windowsFeatureUpdateProfiles` |
| `data.qualityUpdateProfiles[]` | Expedited quality update profiles. | `/beta/deviceManagement/windowsQualityUpdateProfiles` |
| `data.featureUpdateAssignments[]`, `data.qualityUpdateAssignments[]` | Assignment targets for update profiles. | Corresponding beta `/{id}/assignments` endpoint |
| `evidenceSummary.pausedUpdateRingCount` | Rings with feature or quality updates paused. | Derived |

## Conditional Access

| Field | Meaning | Graph source |
|---|---|---|
| `data.policies[]` | Policy state, conditions, exclusions, session controls, and grant controls. | `/v1.0/identity/conditionalAccess/policies` |
| `states` | Counts by policy state. | Derived |
| `policiesUsingCompliantDeviceGrant` | Policies containing `compliantDevice`. | Derived from `grantControls.builtInControls` |
| `policiesUsingApprovedAppGrant` | Policies containing `approvedApplication`. | Derived |
| `policiesUsingAppProtectionGrant` | Policies containing `compliantApplication`. | Derived |

## Defender-related evidence

| Field | Meaning | Source |
|---|---|---|
| `data.onboardingStateSummary[]` | Tenant Defender for Endpoint onboarding device-state counts, when exposed/licensed. | `/beta/deviceManagement/advancedThreatProtectionOnboardingStateSummary` |
| `data.policyEvidence[]` | Configuration objects containing Defender, antivirus, firewall, ASR, EDR, or tamper terms. Keyword discovery is intentionally not scoring. | Shared configuration evidence |
| `data.deviceThreatStateCounts` | Counts by `partnerReportedThreatState`. | Managed devices |

## Mobile apps and assignments

| Field | Meaning | Graph source |
|---|---|---|
| `data.apps[]` | App identity, publisher, dates, owner/developer, type, and publishing state. | `/v1.0/deviceAppManagement/mobileApps` |
| `data.assignments[]` | Intent, target, and settings for each app. | `/v1.0/deviceAppManagement/mobileApps/{id}/assignments` |
| `evidenceSummary.*` | Counts by publishing state, app type, and assignment intent. | Derived |

## Licensing

| Field | Meaning | Graph source |
|---|---|---|
| `data.subscribedSkus[]` | SKU IDs/part numbers, capability, consumed/prepaid units, and service plans. | `/v1.0/subscribedSkus` |
| `intuneRelatedServicePlans[]` | Service plans whose names contain Intune, MDM, or endpoint. This is discovery only and is not an entitlement conclusion. | Derived |

## Intune RBAC

| Field | Meaning | Graph source |
|---|---|---|
| `data.roleDefinitions[]` | Built-in/custom role definitions and allowed actions. | `/v1.0/deviceManagement/roleDefinitions` |
| `data.roleAssignments[]` | Assignment names, member references, and resource scopes. | `/v1.0/deviceManagement/roleAssignments` |
| `evidenceSummary.*` | Definition, custom-role, assignment, and member-reference counts. | Derived |

## MAM / app protection

| Field | Meaning | Graph source |
|---|---|---|
| `data.iosPolicies[]` | iOS/iPadOS app protection policies. | `/v1.0/deviceAppManagement/iosManagedAppProtections` |
| `data.androidPolicies[]` | Android app protection policies. | `/v1.0/deviceAppManagement/androidManagedAppProtections` |
| `data.targetedConfigurations[]` | Targeted managed app configuration policies. | `/v1.0/deviceAppManagement/targetedManagedAppConfigurations` |
| `data.*Assignments[]` | Assignment targets linked to parent policy/configuration. | Corresponding `/{id}/assignments` endpoints |
| `personalManagedDeviceCount` | Managed devices marked personal; does not represent unenrolled MAM-only users/devices. | Derived from managed devices |

### Version 1.0.3 source correction
data.modernDeviceStatuses now contains Schema/Values rows from POST /beta/deviceManagement/reports/getConfigurationPolicyDevicesReport filtered by PolicyId. Report column names are retained, and _collectorParentId identifies the policy. These records have a different field layout from legacy deviceStatuses; downstream consumers must handle report columns accordingly.
Autopilot retrieves the collection without query options and retains the previously selected fields locally.

Version 1.0.5 modern status report filter: (PolicyBaseTypeName eq 'DeviceManagementConfigurationPolicy') and (PolicyId eq '{id}'). The supplied release records earlier live validation in a test tenant; no live collection was repeated for the October 25, 2026 GitHub preparation.

