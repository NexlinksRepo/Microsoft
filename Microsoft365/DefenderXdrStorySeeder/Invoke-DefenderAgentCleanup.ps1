#requires -Version 7.2

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[^@\s]+@[^@\s]+\.[^@\s]+$')]
    [string]$GlobalAdminUpn,

    [string]$SearchRoot = (Join-Path $PSScriptRoot 'artifacts'),

    [string[]]$ManifestPath,

    [switch]$DiscoverByPrefix,

    [ValidateNotNullOrEmpty()]
    [string]$NamePrefix = '[MXDR Demo]',

    [ValidateRange(0, 5000)]
    [int]$DelayMilliseconds = 250,

    [switch]$Execute,

    [switch]$UseDeviceCode,

    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'artifacts')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProjectVersion = '0.2.4-beta'

. (Join-Path $PSScriptRoot 'DefenderXdrStorySeeder.Authentication.ps1')

function Get-GraphStatusCode {
    param([Parameter(Mandatory)]$ErrorRecord)
    try {
        if ($null -ne $ErrorRecord.Exception.Response.StatusCode) {
            return [int]$ErrorRecord.Exception.Response.StatusCode
        }
    }
    catch {
        return $null
    }
    return $null
}

function Invoke-AgentDelete {
    param(
        [Parameter(Mandatory)][string]$Type,
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Uri,
        [ValidateRange(1, 5)][int]$MaximumAttempts = 3
    )

    for ($attempt = 1; $attempt -le $MaximumAttempts; $attempt++) {
        try {
            Invoke-MgGraphRequest -Method DELETE -Uri $Uri -ErrorAction Stop | Out-Null
            return [ordered]@{ type = $Type; id = $Id; result = 'deleted'; statusCode = 204; error = $null }
        }
        catch {
            $statusCode = Get-GraphStatusCode -ErrorRecord $_
            if ($statusCode -eq 404) {
                return [ordered]@{ type = $Type; id = $Id; result = 'alreadyAbsent'; statusCode = 404; error = $null }
            }
            $retryable = $statusCode -eq 429 -or $statusCode -ge 500
            if ($retryable -and $attempt -lt $MaximumAttempts) {
                $delaySeconds = [math]::Pow(2, $attempt - 1)
                Write-Warning "$Type $Id deletion returned HTTP $statusCode. Retrying in $delaySeconds second(s)."
                Start-Sleep -Seconds $delaySeconds
                continue
            }
            $responseBody = [string]$_.ErrorDetails.Message
            if ([string]::IsNullOrWhiteSpace($responseBody)) {
                $responseBody = [string]$_.Exception.Message
            }
            return [ordered]@{ type = $Type; id = $Id; result = 'failed'; statusCode = $statusCode; error = $responseBody }
        }
    }
}

function Get-PrefixedAgentBlueprintRecords {
    param([Parameter(Mandatory)][string]$Prefix)

    $records = [System.Collections.Generic.List[object]]::new()
    $uri = 'https://graph.microsoft.com/v1.0/applications/microsoft.graph.agentIdentityBlueprint?$select=id,appId,displayName'
    do {
        $response = Invoke-MgGraphRequest -Method GET -Uri $uri -ErrorAction Stop
        foreach ($blueprint in @($response.value)) {
            $displayName = [string]$blueprint.displayName
            if (-not $displayName.StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }
            $records.Add([pscustomobject][ordered]@{
                displayName = $displayName
                blueprintId = [string]$blueprint.id
                blueprintPrincipalId = ''
                agentIdentityId = ''
                agentRegistrationId = ''
                sourceManifests = @()
                discoverySource = "namePrefix:$Prefix"
            })
        }
        $nextLinkProperty = $response.PSObject.Properties['@odata.nextLink']
        $uri = if ($null -ne $nextLinkProperty) {
            [string]$nextLinkProperty.Value
        }
        else {
            $null
        }
    } while (-not [string]::IsNullOrWhiteSpace($uri))
    return @($records)
}

function Get-AgentRecordsFromManifests {
    param([Parameter(Mandatory)][string[]]$Paths)

    $records = @{}
    foreach ($path in $Paths) {
        try {
            $manifest = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -AsHashtable
            if (-not $manifest.ContainsKey('agents')) {
                continue
            }
            foreach ($agent in @($manifest.agents)) {
                $blueprintId = [string]$agent.blueprintId
                $registrationId = [string]$agent.agentRegistrationId
                $identityId = [string]$agent.agentIdentityId
                $principalId = [string]$agent.blueprintPrincipalId
                if ([string]::IsNullOrWhiteSpace($blueprintId) -and
                    [string]::IsNullOrWhiteSpace($registrationId) -and
                    [string]::IsNullOrWhiteSpace($identityId) -and
                    [string]::IsNullOrWhiteSpace($principalId)) {
                    continue
                }
                $key = if (-not [string]::IsNullOrWhiteSpace($blueprintId)) {
                    "blueprint:$blueprintId"
                }
                elseif (-not [string]::IsNullOrWhiteSpace($identityId)) {
                    "identity:$identityId"
                }
                elseif (-not [string]::IsNullOrWhiteSpace($principalId)) {
                    "principal:$principalId"
                }
                else {
                    "registration:$registrationId"
                }
                if (-not $records.ContainsKey($key)) {
                    $records[$key] = [pscustomobject][ordered]@{
                        displayName = [string]$agent.displayName
                        blueprintId = $blueprintId
                        blueprintPrincipalId = $principalId
                        agentIdentityId = $identityId
                        agentRegistrationId = $registrationId
                        sourceManifests = @($path)
                    }
                }
                elseif ($path -notin @($records[$key].sourceManifests)) {
                    $records[$key].sourceManifests = @($records[$key].sourceManifests) + $path
                }
            }
        }
        catch {
            Write-Warning "Skipping unreadable manifest '$path': $($_.Exception.Message)"
        }
    }
    return @($records.Values)
}

function Save-AgentCleanupManifest {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Manifest, [Parameter(Mandatory)][string]$Path)
    $Manifest | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $Path -Encoding utf8
}

$manifestPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($path in @($ManifestPath)) {
    if (-not [string]::IsNullOrWhiteSpace([string]$path)) {
        [void]$manifestPaths.Add((Resolve-Path -LiteralPath $path -ErrorAction Stop).Path)
    }
}
if (-not [string]::IsNullOrWhiteSpace($SearchRoot)) {
    if (Test-Path -LiteralPath $SearchRoot -PathType Leaf) {
        [void]$manifestPaths.Add((Resolve-Path -LiteralPath $SearchRoot).Path)
    }
    elseif (Test-Path -LiteralPath $SearchRoot -PathType Container) {
        foreach ($file in @(Get-ChildItem -LiteralPath $SearchRoot -Filter 'bulk-seed-run-*.json' -File -Recurse -ErrorAction SilentlyContinue)) {
            [void]$manifestPaths.Add($file.FullName)
        }
    }
    elseif (@($ManifestPath).Count -eq 0 -and -not $DiscoverByPrefix) {
        throw "SearchRoot does not exist: $SearchRoot"
    }
}

$resolvedManifestPaths = @($manifestPaths | Sort-Object)
if ($resolvedManifestPaths.Count -eq 0 -and -not $DiscoverByPrefix) {
    throw 'No seed manifests were found. Supply -ManifestPath or point -SearchRoot at a folder containing bulk-seed-run-*.json files.'
}

$agentRecords = if ($resolvedManifestPaths.Count -gt 0) {
    @(Get-AgentRecordsFromManifests -Paths $resolvedManifestPaths)
}
else {
    @()
}
$connectParameters = @{
    Scopes = @(
        'AgentRegistration.ReadWrite.All'
        'AgentIdentityBlueprint.Read.All'
        'AgentIdentityBlueprint.DeleteRestore.All'
        'AgentIdentity.DeleteRestore.All'
        'AgentIdentityBlueprintPrincipal.DeleteRestore.All'
    )
}

$context = $null
if ($DiscoverByPrefix) {
    $context = Connect-DefenderGraphSession -LoginHint $GlobalAdminUpn -Scopes $connectParameters.Scopes -UseDeviceCode:$UseDeviceCode

    $blueprintIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($agent in $agentRecords) {
        if (-not [string]::IsNullOrWhiteSpace([string]$agent.blueprintId)) {
            [void]$blueprintIds.Add([string]$agent.blueprintId)
        }
    }
    foreach ($discoveredAgent in @(Get-PrefixedAgentBlueprintRecords -Prefix $NamePrefix)) {
        if ($blueprintIds.Add([string]$discoveredAgent.blueprintId)) {
            $agentRecords = @($agentRecords) + $discoveredAgent
        }
    }
}

if ($agentRecords.Count -eq 0) {
    Write-Host "No agent blueprints beginning with '$NamePrefix' or recorded demo agents were found." -ForegroundColor Green
    return [pscustomobject]@{ Mode = if ($Execute) { 'Executed' } else { 'DryRun' }; Version = $ProjectVersion; AgentCount = 0; DeletedObjects = 0; FailedObjects = 0 }
}

if (-not $Execute) {
    Write-Host 'DRY RUN — no Agent 365 or Entra objects were changed.' -ForegroundColor Cyan
    $agentRecords | Select-Object displayName, blueprintId, agentIdentityId, blueprintPrincipalId, agentRegistrationId | Format-Table -AutoSize | Out-Host
    return [pscustomobject]@{
        Mode = 'DryRun'
        Version = $ProjectVersion
        ManifestCount = $resolvedManifestPaths.Count
        AgentCount = $agentRecords.Count
        NamePrefix = if ($DiscoverByPrefix) { $NamePrefix } else { $null }
    }
}

$objectCount = @($agentRecords | ForEach-Object {
    @($_.agentRegistrationId, $_.blueprintId, $_.agentIdentityId, $_.blueprintPrincipalId) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
}).Count
if (-not $PSCmdlet.ShouldProcess(
    "Microsoft Entra and Agent 365 tenant selected by $GlobalAdminUpn",
    "Soft-delete $($agentRecords.Count) demo agent set(s) recorded in manifests or beginning with '$NamePrefix', covering up to $objectCount object IDs; do not change Defender alerts or incidents"
)) {
    return
}

if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}
$cleanupManifestPath = Join-Path $OutputDirectory "agent-cleanup-run-$([DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')).json"
$cleanupManifest = [ordered]@{
    schemaVersion = 1
    projectVersion = $ProjectVersion
    startedAtUtc = [DateTime]::UtcNow.ToString('o')
    completedAtUtc = $null
    tenantId = $null
    account = $null
    sourceManifests = $resolvedManifestPaths
    discoverByPrefix = [bool]$DiscoverByPrefix
    namePrefix = if ($DiscoverByPrefix) { $NamePrefix } else { $null }
    requestedAgentCount = $agentRecords.Count
    operations = @()
}
Save-AgentCleanupManifest -Manifest $cleanupManifest -Path $cleanupManifestPath

try {
    if ($null -eq $context) {
        $context = Connect-DefenderGraphSession -LoginHint $GlobalAdminUpn -Scopes $connectParameters.Scopes -UseDeviceCode:$UseDeviceCode
    }
    $cleanupManifest.tenantId = [string]$context.TenantId
    $cleanupManifest.account = [string]$context.Account
    Save-AgentCleanupManifest -Manifest $cleanupManifest -Path $cleanupManifestPath

    $agentNumber = 0
    foreach ($agent in $agentRecords) {
        $agentNumber++
        Write-Progress -Activity 'Deleting recorded demo AI agents' -Status "$agentNumber of $($agentRecords.Count): $($agent.displayName)" -PercentComplete (($agentNumber / $agentRecords.Count) * 100)
        $targets = @(
            if (-not [string]::IsNullOrWhiteSpace([string]$agent.agentRegistrationId)) {
                [pscustomobject][ordered]@{ type = 'agentRegistration'; id = [string]$agent.agentRegistrationId; uri = "https://graph.microsoft.com/beta/copilot/agentRegistrations/$([uri]::EscapeDataString([string]$agent.agentRegistrationId))" }
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$agent.blueprintId)) {
                [pscustomobject][ordered]@{ type = 'agentIdentityBlueprint'; id = [string]$agent.blueprintId; uri = "https://graph.microsoft.com/v1.0/applications/$([uri]::EscapeDataString([string]$agent.blueprintId))/microsoft.graph.agentIdentityBlueprint" }
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$agent.agentIdentityId)) {
                [pscustomobject][ordered]@{ type = 'agentIdentity'; id = [string]$agent.agentIdentityId; uri = "https://graph.microsoft.com/v1.0/servicePrincipals/$([uri]::EscapeDataString([string]$agent.agentIdentityId))/microsoft.graph.agentIdentity" }
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$agent.blueprintPrincipalId)) {
                [pscustomobject][ordered]@{ type = 'agentIdentityBlueprintPrincipal'; id = [string]$agent.blueprintPrincipalId; uri = "https://graph.microsoft.com/v1.0/servicePrincipals/$([uri]::EscapeDataString([string]$agent.blueprintPrincipalId))/microsoft.graph.agentIdentityBlueprintPrincipal" }
            }
        )

        foreach ($target in $targets) {
            $operation = Invoke-AgentDelete -Type ([string]$target.type) -Id ([string]$target.id) -Uri ([string]$target.uri)
            $operation['displayName'] = [string]$agent.displayName
            $cleanupManifest.operations = @($cleanupManifest.operations) + $operation
            Save-AgentCleanupManifest -Manifest $cleanupManifest -Path $cleanupManifestPath
            if ([string]$operation.result -eq 'failed') {
                Write-Warning "$($target.type) '$($agent.displayName)' could not be deleted. HTTP $($operation.statusCode): $($operation.error)"
            }
            if ($DelayMilliseconds -gt 0) {
                Start-Sleep -Milliseconds $DelayMilliseconds
            }
        }
    }
    Write-Progress -Activity 'Deleting recorded demo AI agents' -Completed
    $cleanupManifest.completedAtUtc = [DateTime]::UtcNow.ToString('o')
    Save-AgentCleanupManifest -Manifest $cleanupManifest -Path $cleanupManifestPath
}
finally {
    Write-Progress -Activity 'Deleting recorded demo AI agents' -Completed
}

$deletedCount = @($cleanupManifest.operations | Where-Object { $_.result -eq 'deleted' }).Count
$alreadyAbsentCount = @($cleanupManifest.operations | Where-Object { $_.result -eq 'alreadyAbsent' }).Count
$failedCount = @($cleanupManifest.operations | Where-Object { $_.result -eq 'failed' }).Count
if ($failedCount -eq 0) {
    Write-Host "Agent cleanup completed: $deletedCount object(s) deleted and $alreadyAbsentCount already absent." -ForegroundColor Green
}
else {
    Write-Warning "Agent cleanup completed with $failedCount failed object deletion(s). Review $cleanupManifestPath"
}

[pscustomobject]@{
    Mode = 'Executed'
    Version = $ProjectVersion
    AgentCount = $agentRecords.Count
    DeletedObjects = $deletedCount
    AlreadyAbsentObjects = $alreadyAbsentCount
    FailedObjects = $failedCount
    ManifestPath = $cleanupManifestPath
}


