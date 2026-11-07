#requires -Version 7.2

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[^@\s]+@[^@\s]+\.[^@\s]+$')]
    [string]$GlobalAdminUpn,

    [ValidateRange(1, 50)]
    [int]$IncidentCount = 50,

    [ValidateRange(1, 50)]
    [int]$StartAt = 1,

    [ValidateRange(500, 30000)]
    [int]$DelayMilliseconds = 1000,

    [int]$RandomSeed = 20261106,

    [string]$CatalogPath = (Join-Path $PSScriptRoot 'catalog\attack-catalog.json'),

    [string]$EndpointRosterPath = (Join-Path $PSScriptRoot 'catalog\endpoint-roster.json'),

    [string]$MailboxRosterPath = (Join-Path $PSScriptRoot 'catalog\mailbox-roster.json'),

    [switch]$Execute,

    [switch]$UseDeviceCode,

    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'artifacts')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProjectVersion = '0.1.0-beta'

function Install-GraphAuthenticationModule {
    $moduleName = 'Microsoft.Graph.Authentication'
    if (Get-Module -ListAvailable -Name $moduleName) {
        return
    }

    Write-Host "Installing required PowerShell module '$moduleName' for the current user..." -ForegroundColor Cyan
    if (Get-Command Install-PSResource -ErrorAction SilentlyContinue) {
        Install-PSResource -Name $moduleName -Repository PSGallery -Scope CurrentUser -TrustRepository -AcceptLicense -Quiet -ErrorAction Stop
    }
    elseif (Get-Command Install-Module -ErrorAction SilentlyContinue) {
        Install-Module -Name $moduleName -Repository PSGallery -Scope CurrentUser -Force -AllowClobber -Confirm:$false -ErrorAction Stop
    }
    else {
        throw "Install PowerShellGet or PSResourceGet, then install '$moduleName'."
    }

    if (-not (Get-Module -ListAvailable -Name $moduleName)) {
        throw "'$moduleName' was installed but is not visible in the current module path. Reopen PowerShell and run the launcher again."
    }
}

function Connect-BulkSeederGraph {
    param([Parameter(Mandatory)][string]$LoginHint, [switch]$DeviceCode)

    Install-GraphAuthenticationModule
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

    $parameters = @{
        Scopes       = @('SecurityAlert.Create.All', 'SecurityIncident.ReadWrite.All', 'User.Read.All')
        ContextScope = 'Process'
        LoginHint    = $LoginHint
        NoWelcome    = $true
    }
    if ($DeviceCode) {
        $parameters.UseDeviceCode = $true
    }

    Connect-MgGraph @parameters | Out-Null
    $context = Get-MgContext
    if ($null -eq $context) {
        throw 'Microsoft Graph authentication did not return a context.'
    }
    return $context
}

function Invoke-GraphRequestWithRetry {
    param(
        [Parameter(Mandatory)][ValidateSet('GET', 'PATCH')][string]$Method,
        [Parameter(Mandatory)][string]$Uri,
        [AllowNull()][System.Collections.IDictionary]$Body,
        [ValidateRange(1, 6)][int]$MaximumAttempts = 4
    )

    for ($attempt = 1; $attempt -le $MaximumAttempts; $attempt++) {
        try {
            $parameters = @{
                Method      = $Method
                Uri         = $Uri
                OutputType  = 'PSObject'
                ErrorAction = 'Stop'
            }
            if ($null -ne $Body) {
                $parameters.Body = ($Body | ConvertTo-Json -Depth 20 -Compress)
                $parameters.ContentType = 'application/json'
            }
            return Invoke-MgGraphRequest @parameters
        }
        catch {
            if ($attempt -eq $MaximumAttempts) {
                throw
            }
            $delaySeconds = [math]::Pow(2, $attempt - 1)
            Write-Warning "Graph request failed on attempt $attempt. Retrying in $delaySeconds second(s). $($_.Exception.Message)"
            Start-Sleep -Seconds $delaySeconds
        }
    }
}

function Invoke-CreateManualAlert {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Body)

    # Manual-alert creation is not idempotent. Do not automatically retry a POST
    # because a lost response could result in a duplicate incident.
    Invoke-MgGraphRequest `
        -Method POST `
        -Uri 'https://graph.microsoft.com/beta/security/alerts_v2' `
        -Body ($Body | ConvertTo-Json -Depth 20 -Compress) `
        -ContentType 'application/json' `
        -OutputType PSObject `
        -ErrorAction Stop
}

function Get-TenantIdentities {
    $identities = [System.Collections.Generic.List[object]]::new()
    $uri = 'https://graph.microsoft.com/v1.0/users?$select=id,displayName,userPrincipalName,mail,accountEnabled,userType&$top=999'

    while (-not [string]::IsNullOrWhiteSpace($uri)) {
        $response = Invoke-MgGraphRequest -Method GET -Uri $uri -OutputType PSObject -ErrorAction Stop
        foreach ($user in @($response.value)) {
            if ($user.accountEnabled -eq $true -and
                [string]$user.userType -eq 'Member' -and
                -not [string]::IsNullOrWhiteSpace([string]$user.userPrincipalName)) {
                $identities.Add([pscustomobject]@{
                    id                = [string]$user.id
                    displayName       = [string]$user.displayName
                    userPrincipalName = [string]$user.userPrincipalName
                    mail              = [string]$user.mail
                })
            }
        }

        if ($response -is [System.Collections.IDictionary] -and $response.Contains('@odata.nextLink')) {
            $uri = [string]$response['@odata.nextLink']
        }
        else {
            $nextLinkProperty = $response.PSObject.Properties['@odata.nextLink']
            $uri = if ($null -eq $nextLinkProperty) { $null } else { [string]$nextLinkProperty.Value }
        }
    }

    return @($identities)
}

function Get-ShuffledItems {
    param(
        [Parameter(Mandatory)][object[]]$Items,
        [Parameter(Mandatory)][System.Random]$Random
    )

    $shuffled = @($Items)
    for ($index = $shuffled.Count - 1; $index -gt 0; $index--) {
        $swapIndex = $Random.Next(0, $index + 1)
        $temporary = $shuffled[$index]
        $shuffled[$index] = $shuffled[$swapIndex]
        $shuffled[$swapIndex] = $temporary
    }
    return $shuffled
}

function Get-DeterministicSha256 {
    param([Parameter(Mandatory)][string]$Value)

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    $hashBytes = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return [Convert]::ToHexString($hashBytes).ToLowerInvariant()
}

function Get-RelatedIpAddress {
    param([Parameter(Mandatory)][int]$Index)

    $prefixes = @('192.0.2', '198.51.100', '203.0.113')
    $prefix = $prefixes[($Index - 1) % $prefixes.Count]
    $lastOctet = 10 + (($Index * 7) % 220)
    return "$prefix.$lastOctet"
}

function Get-SafeSlug {
    param([Parameter(Mandatory)][string]$Value)

    $slug = $Value.ToLowerInvariant() -replace '[^a-z0-9]+', '-'
    return $slug.Trim('-')
}

function New-AlertEntities {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Attack,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Endpoint,
        [Parameter(Mandatory)][string]$UserPrincipalName,
        [AllowEmptyString()][string]$MailboxAddress,
        [AllowEmptyString()][string]$FictionalMailboxAddress,
        [Parameter(Mandatory)][int]$Index,
        [Parameter(Mandatory)][int]$StageNumber
    )

    $entities = [System.Collections.Generic.List[object]]::new()
    $entities.Add([ordered]@{
        entityType = 'device'; entityIdentifier = 'deviceName'; identifierValue = [string]$Endpoint.name; role = 'impacted'
    })
    $entities.Add([ordered]@{
        entityType = 'user'; entityIdentifier = 'userPrincipalName'; identifierValue = $UserPrincipalName; role = 'impacted'
    })

    if ([string]$Attack.workload -eq 'Email') {
        if (-not [string]::IsNullOrWhiteSpace($MailboxAddress)) {
            $entities.Add([ordered]@{
                entityType = 'mailbox'; entityIdentifier = 'mailboxPrimaryAddress'; identifierValue = $MailboxAddress; role = 'impacted'
            })
        }
        if (-not [string]::IsNullOrWhiteSpace($FictionalMailboxAddress) -and $FictionalMailboxAddress -ne $MailboxAddress) {
            $entities.Add([ordered]@{
                entityType = 'mailbox'; entityIdentifier = 'mailboxPrimaryAddress'; identifierValue = $FictionalMailboxAddress; role = 'impacted'
            })
        }
    }
    elseif ([string]$Attack.workload -eq 'CloudApp') {
        $entities.Add([ordered]@{
            entityType = 'cloudApplication'; entityIdentifier = 'name'; identifierValue = 'Microsoft 365'; role = 'impacted'
        })
        if (-not [string]::IsNullOrWhiteSpace($FictionalMailboxAddress)) {
            $entities.Add([ordered]@{
                entityType = 'mailbox'; entityIdentifier = 'mailboxPrimaryAddress'; identifierValue = $FictionalMailboxAddress; role = 'related'
            })
        }
    }
    elseif ([string]$Attack.workload -eq 'DefenderForCloud') {
        $resourceName = ([string]$Endpoint.name).ToLowerInvariant()
        $entities.Add([ordered]@{
            entityType = 'azureResource'
            entityIdentifier = 'resourceId'
            identifierValue = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-security-lab/providers/Microsoft.Compute/virtualMachines/$resourceName"
            role = 'impacted'
        })
    }

    $evidenceIndex = (($Index - 1) * 12) + $StageNumber
    $entities.Add([ordered]@{
        entityType = 'ip'; entityIdentifier = 'address'; identifierValue = Get-RelatedIpAddress -Index $evidenceIndex; role = 'related'
    })

    $slug = Get-SafeSlug -Value ([string]$Attack.title)
    $entities.Add([ordered]@{
        entityType = 'url'; entityIdentifier = 'url'; identifierValue = "https://$slug.security-lab.test/activity/$Index/$StageNumber"; role = 'related'
    })

    if (@('Endpoint', 'Hybrid', 'DefenderForCloud') -contains [string]$Attack.workload) {
        $entities.Add([ordered]@{
            entityType = 'file'; entityIdentifier = 'sha256'; identifierValue = Get-DeterministicSha256 -Value "$Index|$StageNumber|$($Attack.title)|$($Endpoint.name)"; role = 'related'
        })
    }

    return @($entities)
}

function Get-StageSeverity {
    param(
        [Parameter(Mandatory)][string]$IncidentSeverity,
        [Parameter(Mandatory)][int]$StageNumber
    )

    if ($StageNumber -eq 1) {
        return $IncidentSeverity.ToLowerInvariant()
    }

    $stageSeverities = @(
        'low', 'medium', 'medium', 'medium', 'high', 'low',
        'medium', 'medium', 'medium', 'high', 'high'
    )
    return $stageSeverities[$StageNumber - 2]
}

function Get-AttackStages {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Attack,
        [Parameter(Mandatory)][int]$AlertCount
    )

    $stages = @(
        [ordered]@{
            title = [string]$Attack.title
            description = [string]$Attack.description
            category = [string]$Attack.category
            techniques = @($Attack.mitreTechniques)
            recommendedActions = [string]$Attack.recommendedActions
        },
        [ordered]@{
            title = 'Related authentication anomaly detected'
            description = 'An authentication anomaly involving {{UserPrincipalName}} preceded the primary activity associated with {{DeviceName}}.'
            category = 'InitialAccess'
            techniques = @('T1078')
            recommendedActions = 'Review the authentication source, session, and conditional-access result.'
        },
        [ordered]@{
            title = 'Suspicious command execution on endpoint'
            description = 'A command interpreter on {{DeviceName}} executed an unusual sequence under {{UserPrincipalName}}.'
            category = 'Execution'
            techniques = @('T1059.001')
            recommendedActions = 'Inspect command-line arguments, parent processes, and downloaded content.'
        },
        [ordered]@{
            title = 'Remote payload transfer observed'
            description = '{{DeviceName}} retrieved executable content from newly observed infrastructure during the active session.'
            category = 'CommandAndControl'
            techniques = @('T1105')
            recommendedActions = 'Block the source and analyze the transferred artifact.'
        },
        [ordered]@{
            title = 'Persistence mechanism established'
            description = 'A recurring execution mechanism was configured on {{DeviceName}} after the initial compromise.'
            category = 'Persistence'
            techniques = @('T1053.005')
            recommendedActions = 'Remove the persistence mechanism and review its creator and payload.'
        },
        [ordered]@{
            title = 'Credential access behavior detected'
            description = 'A process on {{DeviceName}} accessed credential-related material associated with {{UserPrincipalName}}.'
            category = 'CredentialAccess'
            techniques = @('T1003')
            recommendedActions = 'Isolate the endpoint and rotate potentially exposed credentials.'
        },
        [ordered]@{
            title = 'Internal discovery activity observed'
            description = '{{DeviceName}} enumerated accounts, groups, and reachable systems using {{UserPrincipalName}}.'
            category = 'Discovery'
            techniques = @('T1087.002', 'T1018')
            recommendedActions = 'Review enumeration commands and identify subsequent target systems.'
        },
        [ordered]@{
            title = 'Lateral movement attempt detected'
            description = 'Credentials associated with {{UserPrincipalName}} were used by {{DeviceName}} to access another system remotely.'
            category = 'LateralMovement'
            techniques = @('T1021.002')
            recommendedActions = 'Contain involved systems and review remote authentication and service activity.'
        },
        [ordered]@{
            title = 'Data collection and staging observed'
            description = 'Files accessible from {{DeviceName}} were collected and staged before outbound transfer.'
            category = 'Collection'
            techniques = @('T1074.001', 'T1560.001')
            recommendedActions = 'Preserve the staged content and identify its source and sensitivity.'
        },
        [ordered]@{
            title = 'Periodic outbound beaconing detected'
            description = '{{DeviceName}} contacted external infrastructure at regular intervals during the incident.'
            category = 'CommandAndControl'
            techniques = @('T1071.001')
            recommendedActions = 'Block the destination and identify the process responsible for the traffic.'
        },
        [ordered]@{
            title = 'Data transfer to external host'
            description = '{{DeviceName}} transferred staged data to an external destination after collection activity.'
            category = 'Exfiltration'
            techniques = @('T1041')
            recommendedActions = 'Block the destination and determine the scope of transferred data.'
        },
        [ordered]@{
            title = 'Destructive follow-on activity detected'
            description = '{{DeviceName}} displayed recovery-inhibition or file-impact behavior after data transfer.'
            category = 'Impact'
            techniques = @('T1490', 'T1486')
            recommendedActions = 'Isolate the device, protect backups, and begin recovery procedures.'
        }
    )

    return @($stages | Select-Object -First $AlertCount)
}

function Save-RunManifest {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Manifest, [Parameter(Mandatory)][string]$Path)
    $Manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding utf8
}

$resolvedCatalogPath = (Resolve-Path -LiteralPath $CatalogPath).Path
$resolvedEndpointRosterPath = (Resolve-Path -LiteralPath $EndpointRosterPath).Path
$resolvedMailboxRosterPath = (Resolve-Path -LiteralPath $MailboxRosterPath).Path
$catalog = Get-Content -LiteralPath $resolvedCatalogPath -Raw | ConvertFrom-Json -AsHashtable
$endpointRoster = Get-Content -LiteralPath $resolvedEndpointRosterPath -Raw | ConvertFrom-Json -AsHashtable
$mailboxRoster = Get-Content -LiteralPath $resolvedMailboxRosterPath -Raw | ConvertFrom-Json -AsHashtable
$allAttacks = @($catalog.attacks)
$random = [System.Random]::new($RandomSeed)
$allEndpoints = @(Get-ShuffledItems -Items @($endpointRoster.endpoints) -Random $random)
$allMailboxAliases = @($mailboxRoster.mailboxes)

if ($allAttacks.Count -lt 50) {
    throw "The attack catalog contains only $($allAttacks.Count) entries; 50 are required."
}
if ($allEndpoints.Count -lt 1) {
    throw 'The endpoint roster is empty.'
}
if ($allMailboxAliases.Count -lt 1) {
    throw 'The mailbox roster is empty.'
}
if (($StartAt - 1 + $IncidentCount) -gt $allAttacks.Count) {
    throw "StartAt $StartAt with IncidentCount $IncidentCount exceeds the $($allAttacks.Count)-entry catalog."
}

$selectedAttacks = @($allAttacks | Select-Object -Skip ($StartAt - 1) -First $IncidentCount)
$plan = for ($offset = 0; $offset -lt $selectedAttacks.Count; $offset++) {
    $catalogIndex = $StartAt + $offset
    $attack = $selectedAttacks[$offset]
    $endpoint = $allEndpoints[($catalogIndex - 1) % $allEndpoints.Count]
    [pscustomobject]@{
        Number   = $catalogIndex
        Title    = [string]$attack.title
        Severity = [string]$attack.severity
        Category = [string]$attack.category
        Workload = [string]$attack.workload
        Endpoint = [string]$endpoint.name
        Identity = 'Selected from tenant at run time'
        Alerts   = 10 + (($catalogIndex - 1) % 3)
    }
}

if (-not $Execute) {
    Write-Host 'DRY RUN — no Microsoft 365 data was changed.' -ForegroundColor Cyan
    $plan | Format-Table -AutoSize | Out-Host
    return [pscustomobject]@{
        Mode          = 'DryRun'
        Version       = $ProjectVersion
        IncidentCount = $selectedAttacks.Count
        StartAt       = $StartAt
        Plan          = $plan
    }
}

$totalAlertCount = ($plan | Measure-Object -Property Alerts -Sum).Sum
$target = "Microsoft Defender tenant selected by $GlobalAdminUpn"
if (-not $PSCmdlet.ShouldProcess($target, "Create $($selectedAttacks.Count) incidents containing $totalAlertCount alerts and impacted endpoint assets")) {
    return
}

if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}
$runId = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
$manifestPath = Join-Path $OutputDirectory "bulk-seed-run-$runId.json"
$manifest = [ordered]@{
    schemaVersion     = 1
    projectVersion    = $ProjectVersion
    runId             = $runId
    startedAtUtc      = [DateTime]::UtcNow.ToString('o')
    completedAtUtc    = $null
    succeeded         = $false
    tenantId          = $null
    signedInAccount   = $null
    globalAdminUpn    = $GlobalAdminUpn
    randomSeed        = $RandomSeed
    requestedCount    = $IncidentCount
    requestedAlertCount = $totalAlertCount
    startAt           = $StartAt
    completedCount    = 0
    completedAlertCount = 0
    discoveredIdentityCount = 0
    discoveredMailboxCount = 0
    incidents         = @()
    error             = $null
}
Save-RunManifest -Manifest $manifest -Path $manifestPath

$context = $null
$executionError = $null
try {
    $context = Connect-BulkSeederGraph -LoginHint $GlobalAdminUpn -DeviceCode:$UseDeviceCode
    $manifest.tenantId = [string]$context.TenantId
    $manifest.signedInAccount = [string]$context.Account

    $tenantIdentities = @(Get-TenantIdentities)
    if ($tenantIdentities.Count -eq 0) {
        $tenantIdentities = @([pscustomobject]@{
            id = $null
            displayName = $GlobalAdminUpn
            userPrincipalName = $GlobalAdminUpn
            mail = $GlobalAdminUpn
        })
    }

    $nonAdminIdentities = @($tenantIdentities | Where-Object { $_.userPrincipalName -ne $GlobalAdminUpn })
    if ($nonAdminIdentities.Count -eq 0) {
        $nonAdminIdentities = $tenantIdentities
    }
    $identityPool = @(Get-ShuffledItems -Items $nonAdminIdentities -Random $random)
    $mailIdentityPool = @($identityPool | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.mail) })
    if ($mailIdentityPool.Count -eq 0) {
        $mailIdentityPool = $identityPool
    }

    $tenantDomain = ($GlobalAdminUpn -split '@', 2)[1]
    $fictionalMailboxes = @(
        foreach ($mailbox in $allMailboxAliases) {
            [pscustomobject]@{
                displayName = [string]$mailbox.displayName
                address = "$([string]$mailbox.alias)@$tenantDomain"
            }
        }
    )
    $fictionalMailboxes = @(Get-ShuffledItems -Items $fictionalMailboxes -Random $random)

    $manifest.discoveredIdentityCount = $identityPool.Count
    $manifest.discoveredMailboxCount = $mailIdentityPool.Count
    Save-RunManifest -Manifest $manifest -Path $manifestPath

    for ($offset = 0; $offset -lt $selectedAttacks.Count; $offset++) {
        $catalogIndex = $StartAt + $offset
        $attack = $selectedAttacks[$offset]
        $endpoint = $allEndpoints[($catalogIndex - 1) % $allEndpoints.Count]
        if ([string]$attack.workload -eq 'Email') {
            $identity = $mailIdentityPool[($catalogIndex - 1) % $mailIdentityPool.Count]
        }
        else {
            $identity = $identityPool[($catalogIndex - 1) % $identityPool.Count]
        }
        $impactedUserPrincipalName = [string]$identity.userPrincipalName
        $impactedMailboxAddress = [string]$identity.mail
        if ([string]::IsNullOrWhiteSpace($impactedMailboxAddress) -and [string]$attack.workload -eq 'Email') {
            $impactedMailboxAddress = $impactedUserPrincipalName
        }
        $fictionalMailbox = $fictionalMailboxes[($catalogIndex - 1) % $fictionalMailboxes.Count]
        $fictionalMailboxAddress = [string]$fictionalMailbox.address
        $alertCount = 10 + (($catalogIndex - 1) % 3)
        $stages = Get-AttackStages -Attack $attack -AlertCount $alertCount
        $incidentId = $null
        $incidentRecord = [ordered]@{
            catalogNumber  = $catalogIndex
            incidentId     = $null
            incidentWebUrl = $null
            title          = [string]$attack.title
            severity       = [string]$attack.severity
            category       = [string]$attack.category
            endpoint       = [string]$endpoint.name
            impactedIdentity = $impactedUserPrincipalName
            impactedMailbox = $impactedMailboxAddress
            fictionalMailbox = $fictionalMailboxAddress
            scenarioContext = switch ([string]$attack.workload) {
                'Email' { 'Defender for Office 365' }
                'Identity' { 'Defender for Identity' }
                'CloudApp' { 'Defender for Cloud Apps' }
                'DefenderForCloud' { 'Defender for Cloud' }
                'Endpoint' { 'Defender for Endpoint' }
                default { 'Microsoft Defender XDR' }
            }
            status         = 'creating'
            alerts         = @()
        }
        $manifest.incidents = @($manifest.incidents) + $incidentRecord
        Save-RunManifest -Manifest $manifest -Path $manifestPath

        for ($stageOffset = 0; $stageOffset -lt $stages.Count; $stageOffset++) {
            $stageNumber = $stageOffset + 1
            $stage = $stages[$stageOffset]
            $entities = New-AlertEntities `
                -Attack $attack `
                -Endpoint $endpoint `
                -UserPrincipalName $impactedUserPrincipalName `
                -MailboxAddress $impactedMailboxAddress `
                -FictionalMailboxAddress $fictionalMailboxAddress `
                -Index $catalogIndex `
                -StageNumber $stageNumber
            $alertBody = [ordered]@{
                '@odata.type'             = '#microsoft.graph.security.manualAlert'
                title                     = [string]$stage.title
                description               = ([string]$stage.description).Replace('{{DeviceName}}', [string]$endpoint.name).Replace('{{UserPrincipalName}}', $impactedUserPrincipalName)
                category                  = [string]$stage.category
                severity                  = Get-StageSeverity -IncidentSeverity ([string]$attack.severity) -StageNumber $stageNumber
                recommendedActions        = [string]$stage.recommendedActions
                mitreTechniques           = @($stage.techniques)
                isExcludedFromCorrelation = $true
                entityDefinitions         = $entities
            }
            if ($stageNumber -gt 1) {
                $alertBody.linkToIncident = [long]$incidentId
            }

            $globalAlertNumber = $manifest.completedAlertCount + 1
            Write-Progress -Activity 'Creating Defender XDR incidents' -Status "Incident $catalogIndex, alert $stageNumber of ${alertCount}: $($stage.title)" -PercentComplete (($globalAlertNumber / $totalAlertCount) * 100)
            $alertResponse = Invoke-CreateManualAlert -Body $alertBody
            if ($stageNumber -eq 1) {
                $incidentId = [string]$alertResponse.incidentId
                if ([string]::IsNullOrWhiteSpace($incidentId)) {
                    throw "Alert '$($attack.title)' was created, but Microsoft Graph did not return an incident ID."
                }
                $incidentRecord.incidentId = $incidentId
                $incidentRecord.incidentWebUrl = [string]$alertResponse.incidentWebUrl

                # A newly created incident can take a few seconds to become
                # addressable by ID. Wait before linking the remaining alerts.
                Invoke-GraphRequestWithRetry `
                    -Method GET `
                    -Uri "https://graph.microsoft.com/beta/security/incidents/$incidentId" `
                    -Body $null `
                    -MaximumAttempts 6 | Out-Null
            }

            $incidentRecord.alerts = @($incidentRecord.alerts) + [ordered]@{
                stage       = $stageNumber
                alertId     = [string]$alertResponse.id
                alertWebUrl = [string]$alertResponse.alertWebUrl
                title       = [string]$stage.title
                severity    = [string]$alertBody.severity
                category    = [string]$stage.category
            }
            $manifest.completedAlertCount++
            Save-RunManifest -Manifest $manifest -Path $manifestPath

            if ($stageNumber -lt $alertCount) {
                Start-Sleep -Milliseconds $DelayMilliseconds
            }
        }

        $resolved = (($catalogIndex % 5) -eq 0)
        $incidentBody = [ordered]@{
            displayName    = [string]$attack.title
            description    = ([string]$attack.description).Replace('{{DeviceName}}', [string]$endpoint.name).Replace('{{UserPrincipalName}}', $impactedUserPrincipalName)
            summary        = [string]$attack.summary
            severity       = ([string]$attack.severity).ToLowerInvariant()
            classification = 'informationalExpectedActivity'
            determination  = 'securityTesting'
            status         = if ($resolved) { 'resolved' } else { 'active' }
        }
        if ($resolved) {
            $incidentBody.resolvingComment = 'Validated during an authorized security-testing exercise.'
        }

        $updatedIncident = Invoke-GraphRequestWithRetry -Method PATCH -Uri "https://graph.microsoft.com/beta/security/incidents/$incidentId" -Body $incidentBody
        $incidentRecord.incidentWebUrl = [string]$updatedIncident.incidentWebUrl
        $incidentRecord.status = if ($resolved) { 'resolved' } else { 'active' }
        $manifest.completedCount++
        Save-RunManifest -Manifest $manifest -Path $manifestPath

        if ($offset -lt ($selectedAttacks.Count - 1)) {
            Start-Sleep -Milliseconds $DelayMilliseconds
        }
    }

    $manifest.succeeded = $true
    $manifest.completedAtUtc = [DateTime]::UtcNow.ToString('o')
}
catch {
    $executionError = $_
    $manifest.error = $_.Exception.Message
    $manifest.completedAtUtc = [DateTime]::UtcNow.ToString('o')
}
finally {
    Write-Progress -Activity 'Creating Defender XDR incidents' -Completed
    Save-RunManifest -Manifest $manifest -Path $manifestPath
    if ($null -ne $context) {
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    }
}

if ($null -ne $executionError) {
    $nextStart = $StartAt + $manifest.completedCount
    $remainingCount = $IncidentCount - $manifest.completedCount
    Write-Warning "Bulk seeding stopped after $($manifest.completedCount) complete incident(s) and $($manifest.completedAlertCount) alert(s). Review the partial incident in the manifest before resuming with -StartAt $nextStart -IncidentCount $remainingCount. Manifest: $manifestPath"
    throw $executionError
}

Write-Host "Created $($manifest.completedCount) Defender XDR incidents containing $($manifest.completedAlertCount) alerts." -ForegroundColor Green
Write-Host "Run manifest: $manifestPath"

[pscustomobject]@{
    Mode           = 'Executed'
    Version        = $ProjectVersion
    IncidentCount  = $manifest.completedCount
    AlertCount     = $manifest.completedAlertCount
    FirstIncident  = if ($manifest.completedCount) { $manifest.incidents[0].incidentWebUrl } else { $null }
    ManifestPath   = $manifestPath
}
