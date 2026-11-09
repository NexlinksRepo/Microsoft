#requires -Version 7.2

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[^@\s]+@[^@\s]+\.[^@\s]+$')]
    [string]$GlobalAdminUpn,

    [string]$CatalogPath = (Join-Path $PSScriptRoot 'catalog\attack-catalog.json'),

    [string]$AiAgentCatalogPath = (Join-Path $PSScriptRoot 'catalog\ai-agent-catalog.json'),

    [string]$SeedManifestPath,

    [switch]$SkipDemoAgentCleanup,

    [ValidateRange(0, 5000)]
    [int]$DelayMilliseconds = 500,

    [bool]$IncludeLegacyPoc = $true,

    [switch]$AllManualAlerts,

    [switch]$Execute,

    [switch]$UseDeviceCode,

    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'artifacts')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProjectVersion = '0.2.1-beta'

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

function Connect-CleanupGraph {
    param([Parameter(Mandatory)][string]$LoginHint, [switch]$DeviceCode)

    Install-GraphAuthenticationModule
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

    $parameters = @{
        Scopes       = @(
            'SecurityAlert.ReadWrite.All'
            'SecurityIncident.ReadWrite.All'
            'AgentRegistration.ReadWrite.All'
            'AgentIdentityBlueprint.DeleteRestore.All'
        )
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
        [Parameter(Mandatory)][ValidateSet('GET', 'PATCH', 'DELETE')][string]$Method,
        [Parameter(Mandatory)][string]$Uri,
        [AllowNull()][System.Collections.IDictionary]$Body,
        [ValidateRange(1, 7)][int]$MaximumAttempts = 5
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

function Get-ResponseValues {
    param([Parameter(Mandatory)]$Response)

    if ($Response -is [System.Collections.IDictionary]) {
        return @($Response['value'])
    }
    return @($Response.value)
}

function Get-ResponseNextLink {
    param([Parameter(Mandatory)]$Response)

    if ($Response -is [System.Collections.IDictionary]) {
        if ($Response.Contains('@odata.nextLink')) {
            return [string]$Response['@odata.nextLink']
        }
        return $null
    }

    $property = $Response.PSObject.Properties['@odata.nextLink']
    if ($null -eq $property) {
        return $null
    }
    return [string]$property.Value
}

function Get-ActiveAlerts {
    $alerts = [System.Collections.Generic.List[object]]::new()
    $uri = 'https://graph.microsoft.com/v1.0/security/alerts_v2?$filter=status%20ne%20%27resolved%27&$top=100'

    while (-not [string]::IsNullOrWhiteSpace($uri)) {
        $response = Invoke-GraphRequestWithRetry -Method GET -Uri $uri -Body $null
        foreach ($alert in @(Get-ResponseValues -Response $response)) {
            $alerts.Add($alert)
        }
        $uri = Get-ResponseNextLink -Response $response
    }

    return @($alerts)
}

function Get-SeededAlertTitles {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$AiPath,
        [bool]$AddLegacyPoc
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Attack catalog was not found: $Path"
    }

    $catalog = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -Depth 20
    if ($null -eq $catalog.attacks -or @($catalog.attacks).Count -eq 0) {
        throw "Attack catalog does not contain an 'attacks' collection: $Path"
    }

    $titles = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($attack in @($catalog.attacks)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$attack.title)) {
            [void]$titles.Add(([string]$attack.title).Trim())
        }
    }

    if (Test-Path -LiteralPath $AiPath -PathType Leaf) {
        $aiCatalog = Get-Content -LiteralPath $AiPath -Raw -ErrorAction Stop | ConvertFrom-Json -Depth 20
        foreach ($agent in @($aiCatalog.agents)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$agent.title)) {
                [void]$titles.Add(([string]$agent.title).Trim())
            }
        }
    }

    $stageTitles = @(
        'Related authentication anomaly detected'
        'Suspicious command execution on endpoint'
        'Remote payload transfer observed'
        'Persistence mechanism established'
        'Credential access behavior detected'
        'Internal discovery activity observed'
        'Lateral movement attempt detected'
        'Data collection and staging observed'
        'Periodic outbound beaconing detected'
        'Data transfer to external host'
        'Destructive follow-on activity detected'
        'AI agent identity observed in unexpected context'
        'AI agent delegated access boundary exceeded'
        'AI agent queried sensitive data source'
        'AI agent accessed untrusted external content'
        'AI agent permission use anomaly detected'
        'AI agent enumerated tenant resources'
        'AI agent collected cross-context information'
        'AI agent staged generated output'
        'AI agent contacted external service'
        'AI agent transferred collected content'
        'AI agent governance response recommended'
    )
    foreach ($title in $stageTitles) {
        [void]$titles.Add($title)
    }

    if ($AddLegacyPoc) {
        foreach ($title in @(
            'Phishing link delivered to test mailbox'
            'Suspicious PowerShell behavior on fictional endpoint'
            'Credential access followed by outbound staging'
        )) {
            [void]$titles.Add($title)
        }
    }

    # Prevent PowerShell from unrolling the HashSet into individual strings.
    return ,$titles
}

function Get-GeneratedAgentRecords {
    param(
        [Parameter(Mandatory)][string]$Directory,
        [AllowEmptyString()][string]$ManifestPath
    )

    $paths = if (-not [string]::IsNullOrWhiteSpace($ManifestPath)) {
        @((Resolve-Path -LiteralPath $ManifestPath).Path)
    }
    elseif (Test-Path -LiteralPath $Directory -PathType Container) {
        @(Get-ChildItem -LiteralPath $Directory -Filter 'bulk-seed-run-*.json' -File | Select-Object -ExpandProperty FullName)
    }
    else {
        @()
    }

    $recordsByBlueprint = @{}
    foreach ($path in $paths) {
        try {
            $seedManifest = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable
            if (-not $seedManifest.ContainsKey('agents')) {
                continue
            }
            foreach ($agent in @($seedManifest.agents)) {
                $key = if (-not [string]::IsNullOrWhiteSpace([string]$agent.blueprintId)) {
                    [string]$agent.blueprintId
                }
                elseif (-not [string]::IsNullOrWhiteSpace([string]$agent.agentRegistrationId)) {
                    "registration:$([string]$agent.agentRegistrationId)"
                }
                else {
                    continue
                }
                $recordsByBlueprint[$key] = [pscustomobject]@{
                    manifestPath = $path
                    displayName = [string]$agent.displayName
                    blueprintId = [string]$agent.blueprintId
                    blueprintPrincipalId = [string]$agent.blueprintPrincipalId
                    agentIdentityId = [string]$agent.agentIdentityId
                    agentRegistrationId = [string]$agent.agentRegistrationId
                }
            }
        }
        catch {
            Write-Warning "Could not read agent records from '$path': $($_.Exception.Message)"
        }
    }
    return @($recordsByBlueprint.Values)
}

function Get-NormalizedAlertTitle {
    param([AllowEmptyString()][string]$Title)

    if ([string]::IsNullOrWhiteSpace($Title)) {
        return ''
    }
    return ($Title -replace '^\s*\[(?:SYNTHETIC|SYNTHESIZED)\]\s*', '').Trim()
}

function Test-IsSeederAlert {
    param(
        [Parameter(Mandatory)]$Alert,
        [Parameter(Mandatory)][System.Collections.Generic.HashSet[string]]$KnownTitles,
        [switch]$IncludeAllManual
    )

    if ([string]$Alert.detectionSource -ine 'manual') {
        return $false
    }
    if ($IncludeAllManual) {
        return $true
    }
    return $KnownTitles.Contains((Get-NormalizedAlertTitle -Title ([string]$Alert.title)))
}

function Save-CleanupManifest {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Manifest,
        [Parameter(Mandatory)][string]$Path
    )

    $Manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding utf8
}

if ($AllManualAlerts) {
    Write-Warning 'AllManualAlerts is enabled. Every active manual alert will be selected, including manual alerts not created by this package.'
}

$context = $null
$manifestPath = $null
$manifest = $null
$fatalError = $null

try {
    $context = Connect-CleanupGraph -LoginHint $GlobalAdminUpn -DeviceCode:$UseDeviceCode
    $knownTitles = Get-SeededAlertTitles -Path $CatalogPath -AiPath $AiAgentCatalogPath -AddLegacyPoc $IncludeLegacyPoc
    $generatedAgentRecords = if ($SkipDemoAgentCleanup) { @() } else { @(Get-GeneratedAgentRecords -Directory $OutputDirectory -ManifestPath $SeedManifestPath) }

    Write-Host 'Reading active Defender XDR alerts...' -ForegroundColor Cyan
    $activeAlerts = @(Get-ActiveAlerts)
    $matchedAlerts = @($activeAlerts | Where-Object {
        Test-IsSeederAlert -Alert $_ -KnownTitles $knownTitles -IncludeAllManual:$AllManualAlerts
    })

    $matchedAlertIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $targetIncidentIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($alert in $matchedAlerts) {
        [void]$matchedAlertIds.Add([string]$alert.id)
        if (-not [string]::IsNullOrWhiteSpace([string]$alert.incidentId)) {
            [void]$targetIncidentIds.Add([string]$alert.incidentId)
        }
    }

    $protectedIncidentIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($alert in $activeAlerts) {
        $incidentId = [string]$alert.incidentId
        if (-not [string]::IsNullOrWhiteSpace($incidentId) -and
            $targetIncidentIds.Contains($incidentId) -and
            -not $matchedAlertIds.Contains([string]$alert.id)) {
            [void]$protectedIncidentIds.Add($incidentId)
        }
    }

    $closableIncidentIds = @($targetIncidentIds | Where-Object { -not $protectedIncidentIds.Contains($_) } | Sort-Object)
    $protectedIncidentIdList = @($protectedIncidentIds | Sort-Object)

    if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    }
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $manifestPath = Join-Path $OutputDirectory "cleanup-run-$timestamp.json"
    $manifest = [ordered]@{
        schemaVersion              = 1
        projectVersion             = $ProjectVersion
        mode                       = if ($Execute) { 'Execute' } else { 'Preview' }
        startedAtUtc               = [DateTime]::UtcNow.ToString('o')
        completedAtUtc             = $null
        tenantId                   = [string]$context.TenantId
        account                    = [string]$context.Account
        allManualAlerts            = [bool]$AllManualAlerts
        executionStarted           = $false
        activeAlertsScanned        = $activeAlerts.Count
        matchedAlertCount          = $matchedAlerts.Count
        closableIncidentCount      = $closableIncidentIds.Count
        protectedIncidentIds       = $protectedIncidentIdList
        resolvedAlertIds           = @()
        failedAlerts               = @()
        resolvedIncidentIds        = @()
        failedIncidents            = @()
        skippedIncidentIds         = @()
        generatedAgentRecordCount  = $generatedAgentRecords.Count
        deletedAgentRegistrationIds = @()
        deletedBlueprintIds        = @()
        failedAgentObjects         = @()
    }
    Save-CleanupManifest -Manifest $manifest -Path $manifestPath

    Write-Host "Found $($matchedAlerts.Count) active seeded alert(s) in $($targetIncidentIds.Count) incident(s)." -ForegroundColor Cyan
    if ($protectedIncidentIdList.Count -gt 0) {
        Write-Warning "$($protectedIncidentIdList.Count) incident(s) contain other active alerts and will not be closed. Matching alerts in those incidents can still be resolved safely."
    }

    $hasCleanupWork = $matchedAlerts.Count -gt 0 -or $generatedAgentRecords.Count -gt 0
    if (-not $hasCleanupWork) {
        Write-Host 'No active seeded alerts or recorded demo-agent objects were found. Nothing needs cleanup.' -ForegroundColor Green
    }
    elseif (-not $Execute) {
        Write-Host 'Preview only. Re-run with -Execute to resolve the matched alerts and incidents.' -ForegroundColor Yellow
    }
    elseif ($PSCmdlet.ShouldProcess(
        "Microsoft Defender tenant $($context.TenantId) selected by $GlobalAdminUpn",
        "Resolve $($matchedAlerts.Count) seeded alerts and $($closableIncidentIds.Count) safe incidents; remove $($generatedAgentRecords.Count) recorded demo-agent identity set(s)"
    )) {
        $manifest.executionStarted = $true
        Save-CleanupManifest -Manifest $manifest -Path $manifestPath
        $failedIncidentIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $alertNumber = 0
        foreach ($alert in $matchedAlerts) {
            $alertNumber++
            Write-Progress -Activity 'Resolving seeded Defender XDR alerts' -Status "$alertNumber of $($matchedAlerts.Count): $($alert.title)" -PercentComplete (($alertNumber / $matchedAlerts.Count) * 100)
            try {
                $escapedAlertId = [uri]::EscapeDataString([string]$alert.id)
                $alertBody = [ordered]@{
                    status         = 'resolved'
                    classification = 'informationalExpectedActivity'
                    determination  = 'securityTesting'
                }
                Invoke-GraphRequestWithRetry -Method PATCH -Uri "https://graph.microsoft.com/v1.0/security/alerts_v2/$escapedAlertId" -Body $alertBody | Out-Null
                $manifest.resolvedAlertIds = @($manifest.resolvedAlertIds) + [string]$alert.id
            }
            catch {
                $manifest.failedAlerts = @($manifest.failedAlerts) + [ordered]@{
                    alertId   = [string]$alert.id
                    incidentId = [string]$alert.incidentId
                    title     = [string]$alert.title
                    error     = $_.Exception.Message
                }
                if (-not [string]::IsNullOrWhiteSpace([string]$alert.incidentId)) {
                    [void]$failedIncidentIds.Add([string]$alert.incidentId)
                }
                Write-Warning "Could not resolve alert '$($alert.title)' ($($alert.id)): $($_.Exception.Message)"
            }
            Save-CleanupManifest -Manifest $manifest -Path $manifestPath
            if ($DelayMilliseconds -gt 0 -and $alertNumber -lt $matchedAlerts.Count) {
                Start-Sleep -Milliseconds $DelayMilliseconds
            }
        }
        Write-Progress -Activity 'Resolving seeded Defender XDR alerts' -Completed

        foreach ($incidentId in $protectedIncidentIdList) {
            $manifest.skippedIncidentIds = @($manifest.skippedIncidentIds) + [ordered]@{
                incidentId = $incidentId
                reason     = 'Incident contains other active alerts.'
            }
        }

        $incidentNumber = 0
        foreach ($incidentId in $closableIncidentIds) {
            $incidentNumber++
            if ($failedIncidentIds.Contains($incidentId)) {
                $manifest.skippedIncidentIds = @($manifest.skippedIncidentIds) + [ordered]@{
                    incidentId = $incidentId
                    reason     = 'One or more matching alerts failed to resolve.'
                }
                continue
            }

            Write-Progress -Activity 'Closing seeded Defender XDR incidents' -Status "$incidentNumber of $($closableIncidentIds.Count): incident $incidentId" -PercentComplete (($incidentNumber / $closableIncidentIds.Count) * 100)
            try {
                $escapedIncidentId = [uri]::EscapeDataString($incidentId)
                $incidentBody = [ordered]@{
                    status           = 'resolved'
                    classification   = 'informationalExpectedActivity'
                    determination    = 'securityTesting'
                    resolvingComment = 'Closed before regenerating the authorized security-testing dataset.'
                }
                Invoke-GraphRequestWithRetry -Method PATCH -Uri "https://graph.microsoft.com/v1.0/security/incidents/$escapedIncidentId" -Body $incidentBody | Out-Null
                $manifest.resolvedIncidentIds = @($manifest.resolvedIncidentIds) + $incidentId
            }
            catch {
                $manifest.failedIncidents = @($manifest.failedIncidents) + [ordered]@{
                    incidentId = $incidentId
                    error      = $_.Exception.Message
                }
                Write-Warning "Could not close incident $incidentId`: $($_.Exception.Message)"
            }
            Save-CleanupManifest -Manifest $manifest -Path $manifestPath
            if ($DelayMilliseconds -gt 0 -and $incidentNumber -lt $closableIncidentIds.Count) {
                Start-Sleep -Milliseconds $DelayMilliseconds
            }
        }
        Write-Progress -Activity 'Closing seeded Defender XDR incidents' -Completed

        $agentNumber = 0
        foreach ($agent in $generatedAgentRecords) {
            $agentNumber++
            Write-Progress -Activity 'Removing recorded demo AI agents' -Status "$agentNumber of $($generatedAgentRecords.Count): $($agent.displayName)" -PercentComplete (($agentNumber / $generatedAgentRecords.Count) * 100)
            if (-not [string]::IsNullOrWhiteSpace([string]$agent.agentRegistrationId)) {
                try {
                    $registrationId = [uri]::EscapeDataString([string]$agent.agentRegistrationId)
                    Invoke-GraphRequestWithRetry -Method DELETE -Uri "https://graph.microsoft.com/beta/copilot/agentRegistrations/$registrationId" -Body $null | Out-Null
                    $manifest.deletedAgentRegistrationIds = @($manifest.deletedAgentRegistrationIds) + [string]$agent.agentRegistrationId
                }
                catch {
                    $manifest.failedAgentObjects = @($manifest.failedAgentObjects) + [ordered]@{ type = 'agentRegistration'; id = [string]$agent.agentRegistrationId; displayName = [string]$agent.displayName; error = $_.Exception.Message }
                    Write-Warning "Could not remove agent registration '$($agent.displayName)': $($_.Exception.Message)"
                }
            }
            if (-not [string]::IsNullOrWhiteSpace([string]$agent.blueprintId)) {
                try {
                    $blueprintId = [uri]::EscapeDataString([string]$agent.blueprintId)
                    Invoke-GraphRequestWithRetry -Method DELETE -Uri "https://graph.microsoft.com/v1.0/applications/$blueprintId/microsoft.graph.agentIdentityBlueprint" -Body $null | Out-Null
                    $manifest.deletedBlueprintIds = @($manifest.deletedBlueprintIds) + [string]$agent.blueprintId
                }
                catch {
                    $manifest.failedAgentObjects = @($manifest.failedAgentObjects) + [ordered]@{ type = 'agentIdentityBlueprint'; id = [string]$agent.blueprintId; displayName = [string]$agent.displayName; error = $_.Exception.Message }
                    Write-Warning "Could not remove agent blueprint '$($agent.displayName)': $($_.Exception.Message)"
                }
            }
            Save-CleanupManifest -Manifest $manifest -Path $manifestPath
        }
        Write-Progress -Activity 'Removing recorded demo AI agents' -Completed
    }

    $manifest.completedAtUtc = [DateTime]::UtcNow.ToString('o')
    Save-CleanupManifest -Manifest $manifest -Path $manifestPath
}
catch {
    $fatalError = $_
    if ($null -ne $manifest -and $null -ne $manifestPath) {
        $manifest.completedAtUtc = [DateTime]::UtcNow.ToString('o')
        $manifest.fatalError = $_.Exception.Message
        Save-CleanupManifest -Manifest $manifest -Path $manifestPath
    }
}
finally {
    Write-Progress -Activity 'Resolving seeded Defender XDR alerts' -Completed
    Write-Progress -Activity 'Closing seeded Defender XDR incidents' -Completed
    Write-Progress -Activity 'Removing recorded demo AI agents' -Completed
    if ($null -ne $context) {
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    }
}

if ($null -ne $fatalError) {
    throw $fatalError
}

if ($null -ne $manifest) {
    $failedCount = @($manifest.failedAlerts).Count + @($manifest.failedIncidents).Count + @($manifest.failedAgentObjects).Count
    if ($failedCount -gt 0) {
        Write-Warning "Cleanup completed with $failedCount failure(s). Review the manifest: $manifestPath"
    }
    elseif ($manifest.executionStarted) {
        Write-Host "Resolved $(@($manifest.resolvedAlertIds).Count) alerts, closed $(@($manifest.resolvedIncidentIds).Count) incidents, removed $(@($manifest.deletedAgentRegistrationIds).Count) registrations, and deleted $(@($manifest.deletedBlueprintIds).Count) blueprints." -ForegroundColor Green
    }
    Write-Host "Cleanup manifest: $manifestPath"

    [pscustomobject]@{
        Mode                    = [string]$manifest.mode
        Version                 = $ProjectVersion
        ActiveAlertsScanned     = [int]$manifest.activeAlertsScanned
        MatchedAlerts           = [int]$manifest.matchedAlertCount
        ResolvedAlerts          = @($manifest.resolvedAlertIds).Count
        ResolvedIncidents       = @($manifest.resolvedIncidentIds).Count
        ProtectedIncidents      = @($manifest.protectedIncidentIds).Count
        RemovedAgentRegistrations = @($manifest.deletedAgentRegistrationIds).Count
        DeletedAgentBlueprints  = @($manifest.deletedBlueprintIds).Count
        FailedOperations        = $failedCount
        ManifestPath            = $manifestPath
    }
}
