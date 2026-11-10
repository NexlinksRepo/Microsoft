#requires -Version 7.2

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path $PSScriptRoot -Parent
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Condition {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )

    if ($Condition) {
        Write-Host "PASS: $Message" -ForegroundColor Green
    }
    else {
        Write-Host "FAIL: $Message" -ForegroundColor Red
        $failures.Add($Message)
    }
}

$requiredFiles = @(
    'Start-DefenderBulkSeed.ps1'
    'Invoke-DefenderBulkSeeder.ps1'
    'DefenderXdrStorySeeder.Authentication.ps1'
    'DefenderXdrStorySeeder.Agent365.ps1'
    'Start-DefenderAgentRegistrationRetry.ps1'
    'Invoke-DefenderAgentRegistrationRetry.ps1'
    'Start-DefenderAgentCleanup.ps1'
    'Invoke-DefenderAgentCleanup.ps1'
    'Start-DefenderEvaluatedAgentLab.ps1'
    'Invoke-DefenderEvaluatedAgentLab.ps1'
    'Start-DefenderEvaluatedAgentCleanup.ps1'
    'Invoke-DefenderEvaluatedAgentCleanup.ps1'
    'Start-DefenderBulkCleanup.ps1'
    'Invoke-DefenderBulkCleanup.ps1'
    'Clear-DefenderGraphAuthCache.ps1'
    'Build-Release.ps1'
    'README.md'
    'CHANGELOG.md'
    'SECURITY.md'
    'VERSION'
    'catalog\attack-catalog.json'
    'catalog\ai-agent-catalog.json'
    'catalog\agent-risk-profiles.json'
    'catalog\endpoint-roster.json'
    'catalog\mailbox-roster.json'
    'docs\ARCHITECTURE.md'
    'docs\AGENT365.md'
    'docs\CATALOG.md'
    'docs\TROUBLESHOOTING.md'
    'docs\defender-xdr-seeded-incidents.png'
    'docs\defender-xdr-attack-story.png'
)
foreach ($relativePath in $requiredFiles) {
    Assert-Condition -Condition (Test-Path -LiteralPath (Join-Path $projectRoot $relativePath) -PathType Leaf) -Message "Required file exists: $relativePath"
}

$scriptFiles = @(
    'Start-DefenderBulkSeed.ps1'
    'Invoke-DefenderBulkSeeder.ps1'
    'DefenderXdrStorySeeder.Authentication.ps1'
    'DefenderXdrStorySeeder.Agent365.ps1'
    'Start-DefenderAgentRegistrationRetry.ps1'
    'Invoke-DefenderAgentRegistrationRetry.ps1'
    'Start-DefenderAgentCleanup.ps1'
    'Invoke-DefenderAgentCleanup.ps1'
    'Start-DefenderEvaluatedAgentLab.ps1'
    'Invoke-DefenderEvaluatedAgentLab.ps1'
    'Start-DefenderEvaluatedAgentCleanup.ps1'
    'Invoke-DefenderEvaluatedAgentCleanup.ps1'
    'Start-DefenderBulkCleanup.ps1'
    'Invoke-DefenderBulkCleanup.ps1'
    'Clear-DefenderGraphAuthCache.ps1'
    'Build-Release.ps1'
)
foreach ($relativePath in $scriptFiles) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $projectRoot $relativePath),
        [ref]$tokens,
        [ref]$parseErrors
    )
    Assert-Condition -Condition ($parseErrors.Count -eq 0) -Message "PowerShell parses without errors: $relativePath"
}

$version = (Get-Content -LiteralPath (Join-Path $projectRoot 'VERSION') -Raw).Trim()
Assert-Condition -Condition ($version -match '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$') -Message 'VERSION uses semantic-version syntax'

$seederText = Get-Content -LiteralPath (Join-Path $projectRoot 'Invoke-DefenderBulkSeeder.ps1') -Raw
$cleanupText = Get-Content -LiteralPath (Join-Path $projectRoot 'Invoke-DefenderBulkCleanup.ps1') -Raw
$cleanupLauncherText = Get-Content -LiteralPath (Join-Path $projectRoot 'Start-DefenderBulkCleanup.ps1') -Raw
$launcherText = Get-Content -LiteralPath (Join-Path $projectRoot 'Start-DefenderBulkSeed.ps1') -Raw
$authenticationText = Get-Content -LiteralPath (Join-Path $projectRoot 'DefenderXdrStorySeeder.Authentication.ps1') -Raw
$agentHelperText = Get-Content -LiteralPath (Join-Path $projectRoot 'DefenderXdrStorySeeder.Agent365.ps1') -Raw
$registrationRetryText = Get-Content -LiteralPath (Join-Path $projectRoot 'Invoke-DefenderAgentRegistrationRetry.ps1') -Raw
$agentCleanupText = Get-Content -LiteralPath (Join-Path $projectRoot 'Invoke-DefenderAgentCleanup.ps1') -Raw
$evaluatedAgentText = Get-Content -LiteralPath (Join-Path $projectRoot 'Invoke-DefenderEvaluatedAgentLab.ps1') -Raw
$evaluatedCleanupText = Get-Content -LiteralPath (Join-Path $projectRoot 'Invoke-DefenderEvaluatedAgentCleanup.ps1') -Raw
$graphCacheCleanupText = Get-Content -LiteralPath (Join-Path $projectRoot 'Clear-DefenderGraphAuthCache.ps1') -Raw
$readmeText = Get-Content -LiteralPath (Join-Path $projectRoot 'README.md') -Raw
$changelogText = Get-Content -LiteralPath (Join-Path $projectRoot 'CHANGELOG.md') -Raw
Assert-Condition -Condition ($seederText.Contains("`$ProjectVersion = '$version'")) -Message 'Seeder version matches VERSION'
Assert-Condition -Condition ($cleanupText.Contains("`$ProjectVersion = '$version'")) -Message 'Cleanup version matches VERSION'
Assert-Condition -Condition ($registrationRetryText.Contains("`$ProjectVersion = '$version'")) -Message 'Registration retry version matches VERSION'
Assert-Condition -Condition ($agentCleanupText.Contains("`$ProjectVersion = '$version'")) -Message 'Agent-only cleanup version matches VERSION'
Assert-Condition -Condition ($agentHelperText.Contains("`$script:AgentSeederVersion = '$version'")) -Message 'Agent helper version matches VERSION'
Assert-Condition -Condition ($evaluatedAgentText.Contains("`$ProjectVersion = '$version'")) -Message 'Evaluated-agent lab version matches VERSION'
Assert-Condition -Condition ($evaluatedCleanupText.Contains("`$ProjectVersion = '$version'")) -Message 'Evaluated-agent cleanup version matches VERSION'
Assert-Condition -Condition ($readmeText.Contains("Current version: **$version**")) -Message 'README version matches VERSION'
Assert-Condition -Condition ($changelogText.Contains("## $version")) -Message 'Changelog contains the current version'
Assert-Condition -Condition ($launcherText.Contains("How many incidents should be created?")) -Message 'Launcher prompts for incident count'
Assert-Condition -Condition ($launcherText.Contains("Agent mode: [E]valuated, [I]nventory-only, or [N]one? [E]")) -Message 'Bulk launcher defaults to the evaluated-agent workflow'
Assert-Condition -Condition ($launcherText.Contains('Invoke-DefenderEvaluatedAgentLab.ps1')) -Message 'Bulk launcher provisions evaluated agents before incidents'
Assert-Condition -Condition ($launcherText.Contains('-EvaluatedAgentManifestPath $EvaluatedAgentManifestPath')) -Message 'Bulk launcher passes the evaluated-agent manifest into incident seeding'
Assert-Condition -Condition ($launcherText.Contains("`$PSBoundParameters.ContainsKey('IncidentCount')")) -Message 'IncidentCount bypasses the interactive count prompt'
Assert-Condition -Condition ($graphCacheCleanupText.Contains('.mg\mg.authrecord*.json')) -Message 'Graph cache cleanup targets Graph authentication records'
Assert-Condition -Condition ($graphCacheCleanupText.Contains('.IdentityService\mg.msal.cache.cae')) -Message 'Graph cache cleanup targets the CAE token cache'
Assert-Condition -Condition ($graphCacheCleanupText.Contains('.IdentityService\mg.msal.cache.nocae')) -Message 'Graph cache cleanup targets the non-CAE token cache'
Assert-Condition -Condition (-not $graphCacheCleanupText.Contains('-Recurse')) -Message 'Graph cache cleanup is restricted to explicit cache files'

$catalog = Get-Content -LiteralPath (Join-Path $projectRoot 'catalog\attack-catalog.json') -Raw | ConvertFrom-Json -Depth 20
$attacks = @($catalog.attacks)
Assert-Condition -Condition ($attacks.Count -eq 50) -Message 'Attack catalog contains exactly 50 stories'

$expectedIds = (1..50) -join ','
$actualIds = (@($attacks | ForEach-Object { [int]$_.id }) -join ',')
Assert-Condition -Condition ($actualIds -eq $expectedIds) -Message 'Attack IDs are unique, sequential, and ordered from 1 through 50'

$allowedSeverities = @('informational', 'low', 'medium', 'high')
$invalidSeverities = @($attacks | Where-Object { [string]$_.severity -notin $allowedSeverities })
Assert-Condition -Condition ($invalidSeverities.Count -eq 0) -Message 'All catalog severities are supported'

$requiredWorkloads = @('Email', 'Identity', 'Endpoint', 'CloudApp', 'DefenderForCloud', 'Hybrid')
$actualWorkloads = @($attacks.workload | Sort-Object -Unique)
$missingWorkloads = @($requiredWorkloads | Where-Object { $_ -notin $actualWorkloads })
Assert-Condition -Condition ($missingWorkloads.Count -eq 0) -Message 'Catalog covers every documented workload context'

$prefixedTitles = @($attacks | Where-Object { [string]$_.title -match '^\s*\[' })
Assert-Condition -Condition ($prefixedTitles.Count -eq 0) -Message 'Catalog titles have no bracketed synthetic prefix'

$totalAlerts = 0
foreach ($catalogNumber in 1..50) {
    $totalAlerts += 10 + (($catalogNumber - 1) % 3)
}
Assert-Condition -Condition ($totalAlerts -eq 549) -Message 'Default 50-incident plan contains exactly 549 alerts'

$aiCatalog = Get-Content -LiteralPath (Join-Path $projectRoot 'catalog\ai-agent-catalog.json') -Raw | ConvertFrom-Json -Depth 20
$agents = @($aiCatalog.agents)
Assert-Condition -Condition ($agents.Count -eq 10) -Message 'AI-agent catalog contains ten varied demo profiles'
Assert-Condition -Condition (@($agents.authorityProfile | Sort-Object -Unique).Count -eq 3) -Message 'AI-agent catalog covers low, medium, and elevated profiles'
Assert-Condition -Condition (@($agents.executionMode | Sort-Object -Unique).Count -eq 2) -Message 'AI-agent catalog covers OBO and service-to-service modes'

$riskCatalog = Get-Content -LiteralPath (Join-Path $projectRoot 'catalog\agent-risk-profiles.json') -Raw | ConvertFrom-Json -Depth 20
$riskProfiles = @($riskCatalog.profiles)
Assert-Condition -Condition (($riskProfiles.id -join ',') -eq 'low,medium,high') -Message 'Evaluated-agent catalog contains low, medium, and high targets'
Assert-Condition -Condition (@($riskProfiles | Where-Object { @($_.instructions).Count -eq 0 }).Count -eq 0) -Message 'Every evaluated-agent profile includes instructions'
Assert-Condition -Condition (@($riskProfiles | Where-Object { $_.id -in @('medium', 'high') -and @($_.mcpServers).Count -eq 0 }).Count -eq 0) -Message 'Medium and high evaluated-agent profiles include governed MCP tooling'

$endpointCatalog = Get-Content -LiteralPath (Join-Path $projectRoot 'catalog\endpoint-roster.json') -Raw | ConvertFrom-Json -Depth 20
$endpoints = @($endpointCatalog.endpoints)
Assert-Condition -Condition ($endpoints.Count -eq 60) -Message 'Endpoint roster contains exactly 60 fictional endpoints'
Assert-Condition -Condition (@($endpoints.name | Sort-Object -Unique).Count -eq 60) -Message 'Endpoint names are unique'

$mailboxCatalog = Get-Content -LiteralPath (Join-Path $projectRoot 'catalog\mailbox-roster.json') -Raw | ConvertFrom-Json -Depth 20
$mailboxes = @($mailboxCatalog.mailboxes)
Assert-Condition -Condition ($mailboxes.Count -eq 30) -Message 'Mailbox roster contains exactly 30 fictional aliases'
Assert-Condition -Condition (@($mailboxes.alias | Sort-Object -Unique).Count -eq 30) -Message 'Mailbox aliases are unique'

foreach ($scope in @('SecurityAlert.Create.All', 'SecurityIncident.ReadWrite.All', 'User.Read.All')) {
    Assert-Condition -Condition ($seederText.Contains($scope)) -Message "Seeder requests required scope: $scope"
}
Assert-Condition -Condition ($seederText.Contains('SecurityAlert.ReadWrite.All')) -Message 'Seeder requests cleanup alert scope for later session reuse'
Assert-Condition -Condition ($authenticationText.Contains("ContextScope = 'CurrentUser'")) -Message 'Authentication persists in the secure current-user Graph cache'
Assert-Condition -Condition ($authenticationText.Contains('Reusing the cached Microsoft Graph sign-in')) -Message 'Authentication reuses a matching cached Graph session'
Assert-Condition -Condition ($authenticationText.Contains('[string]$context.Account -ine $LoginHint')) -Message 'Authentication rejects a mismatched administrator account'
foreach ($runtimeText in @($seederText, $cleanupText, $registrationRetryText, $agentCleanupText)) {
    Assert-Condition -Condition (-not $runtimeText.Contains('Disconnect-MgGraph')) -Message 'Runtime script preserves the cached Graph sign-in'
}
foreach ($scope in @('AgentIdentityBlueprint.Create', 'AgentIdentityBlueprintPrincipal.Create', 'AgentIdentity.Create.All', 'AgentRegistration.ReadWrite.All')) {
    Assert-Condition -Condition ($seederText.Contains($scope)) -Message "Seeder requests optional agent scope: $scope"
}
foreach ($scope in @('SecurityAlert.ReadWrite.All', 'SecurityIncident.ReadWrite.All')) {
    Assert-Condition -Condition ($cleanupText.Contains($scope)) -Message "Cleanup requests required scope: $scope"
}

Assert-Condition -Condition ($cleanupText.Contains("detectionSource -ine 'manual'")) -Message 'Cleanup restricts default selection to Manual alerts'
Assert-Condition -Condition ($cleanupText.Contains('protectedIncidentIds')) -Message 'Cleanup protects incidents containing unrelated active alerts'
Assert-Condition -Condition ($seederText.Contains('isExcludedFromCorrelation = $true')) -Message 'Seeder prevents unintended automatic incident correlation'
Assert-Condition -Condition ($seederText.Contains("associationMode = if (`$isAiScenario) { 'manualProxy'")) -Message 'AI incidents declare manual proxy association'
Assert-Condition -Condition ($seederText.Contains('agentAssetLinked = $false')) -Message 'AI incidents do not claim native asset linkage'
Assert-Condition -Condition ($seederText.Contains('schemaVersion     = 3')) -Message 'New manifests use timeout-recovery schema 3'
Assert-Condition -Condition ($seederText.Contains('[MXDR-SEED:$runId')) -Message 'Created alerts carry deterministic correlation markers'
Assert-Condition -Condition ($seederText.Contains('Invoke-CreateManualAlertWithRecovery')) -Message 'Seeder reconciles ambiguous alert POST results'
Assert-Condition -Condition ($seederText.Contains('$existingIncidentRecords[$resumeOffset]')) -Message 'Resume reuses the partial incident record'
Assert-Condition -Condition ($seederText.Contains('$firstPendingStageOffset = @($incidentRecord.alerts).Count')) -Message 'Resume starts at the first unrecorded alert stage'
Assert-Condition -Condition ($agentHelperText.Contains('credentialsCreated       = $false')) -Message 'Demo agents do not create stored credentials'
Assert-Condition -Condition ($agentHelperText.Contains('permissionGrantsCreated  = @()')) -Message 'Demo agents do not auto-grant declared permissions'
Assert-Condition -Condition (-not $agentHelperText.Contains('managedByAppId =')) -Message 'Registry payload does not misidentify the blueprint as the calling management app'
Assert-Condition -Condition ($agentHelperText.Contains('ownerIds = @($OwnerId)')) -Message 'Registry payload satisfies the owner requirement'
Assert-Condition -Condition ($agentHelperText.Contains('Get-AgentGraphErrorInfo')) -Message 'Agent errors retain status and response details'
Assert-Condition -Condition ($registrationRetryText.Contains('Register-DemoAiAgent')) -Message 'Registration-only retry reuses existing agent identities'
Assert-Condition -Condition (-not $registrationRetryText.Contains('New-DemoAiAgent')) -Message 'Registration-only retry cannot create duplicate agent identities'
Assert-Condition -Condition ($registrationRetryText.Contains("'AgentRegistration.ReadWrite.All' -notin")) -Message 'Registration retry verifies the delegated scope is present'
Assert-Condition -Condition ($cleanupText.Contains('copilot/agentRegistrations/$([uri]::EscapeDataString([string]$agent.agentRegistrationId))')) -Message 'Cleanup removes only recorded registry IDs'
Assert-Condition -Condition ($cleanupText.Contains('microsoft.graph.agentIdentityBlueprint')) -Message 'Cleanup uses blueprint cascade deletion'
foreach ($fragment in @(
    'copilot/agentRegistrations/'
    'microsoft.graph.agentIdentityBlueprint"'
    'microsoft.graph.agentIdentity"'
    'microsoft.graph.agentIdentityBlueprintPrincipal"'
)) {
    Assert-Condition -Condition ($agentCleanupText.Contains($fragment)) -Message "Agent-only cleanup contains specialized endpoint: $fragment"
}
Assert-Condition -Condition ($agentCleanupText.Contains("-Filter 'bulk-seed-run-*.json'")) -Message 'Agent-only cleanup discovers seed manifests'
Assert-Condition -Condition ($agentCleanupText.Contains("[string]`$NamePrefix = '[MXDR Demo]'")) -Message 'Agent-only cleanup defaults to the exact MXDR Demo prefix'
Assert-Condition -Condition ($agentHelperText.Contains('[MXDR Demo]')) -Message 'New agent object names use the MXDR Demo prefix'
Assert-Condition -Condition ($agentCleanupText.Contains('microsoft.graph.agentIdentityBlueprint?$select=id,appId,displayName')) -Message 'Agent-only cleanup lists only Agent ID blueprints for prefix discovery'
Assert-Condition -Condition ($agentCleanupText.Contains('StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase)')) -Message 'Agent-only cleanup applies a strict starts-with prefix filter'
Assert-Condition -Condition ($agentCleanupText.Contains("PSObject.Properties['@odata.nextLink']")) -Message 'Agent-only cleanup treats the Graph next-link property as optional'
Assert-Condition -Condition ($agentCleanupText.Contains("result = 'alreadyAbsent'")) -Message 'Agent-only cleanup is repeat-safe for absent objects'
Assert-Condition -Condition (-not $agentCleanupText.Contains('/security/alerts')) -Message 'Agent-only cleanup does not access Defender alerts'
Assert-Condition -Condition (-not $agentCleanupText.Contains('/security/incidents')) -Message 'Agent-only cleanup does not access Defender incidents'
Assert-Condition -Condition ($evaluatedAgentText.Contains("@('setup', 'all'")) -Message 'Evaluated-agent lab delegates supported provisioning to the Agent 365 CLI'
Assert-Condition -Condition ($evaluatedAgentText.Contains("@('setup', 'permissions', 'mcp')")) -Message 'Evaluated-agent lab applies MCP permissions through the Agent 365 CLI'
Assert-Condition -Condition ($evaluatedAgentText.Contains("riskRatingGuaranteed = `$false")) -Message 'Evaluated-agent manifest does not claim a guaranteed Defender rating'
Assert-Condition -Condition ($evaluatedCleanupText.Contains("@('cleanup', 'instance')")) -Message 'Evaluated-agent cleanup removes the recorded instance through the Agent 365 CLI'
Assert-Condition -Condition ($evaluatedCleanupText.Contains("@('cleanup', 'blueprint')")) -Message 'Evaluated-agent cleanup removes the recorded blueprint through the Agent 365 CLI'
Assert-Condition -Condition (-not $evaluatedCleanupText.Contains("@('cleanup', 'azure')")) -Message 'Evaluated-agent cleanup never removes Azure resources'
Assert-Condition -Condition (-not $evaluatedCleanupText.Contains('/security/alerts')) -Message 'Evaluated-agent cleanup does not access Defender alerts'
Assert-Condition -Condition (-not $evaluatedCleanupText.Contains('/security/incidents')) -Message 'Evaluated-agent cleanup does not access Defender incidents'
Assert-Condition -Condition ($cleanupText.Contains("creationStatus -eq 'evaluatedConfiguration'")) -Message 'Graph cleanup skips evaluated agents owned by Agent 365 CLI cleanup'
Assert-Condition -Condition ($cleanupLauncherText.Contains('Invoke-DefenderEvaluatedAgentCleanup.ps1')) -Message 'Bulk cleanup launcher includes evaluated-agent cleanup'
Assert-Condition -Condition ($cleanupLauncherText.Contains('-SeedManifestPath $SeedManifestPath')) -Message 'Bulk cleanup launcher accepts an exact historical seed manifest'
Assert-Condition -Condition ($cleanupText.Contains('Get-SeedManifestScope')) -Message 'Cleanup recovers incident and alert IDs from the selected seed manifest'
Assert-Condition -Condition ($cleanupText.Contains("type = 'agentIdentity'")) -Message 'Bulk cleanup explicitly removes recorded agent identities'
Assert-Condition -Condition ($cleanupText.Contains("type = 'agentIdentityBlueprintPrincipal'")) -Message 'Bulk cleanup explicitly removes recorded blueprint principals'
Assert-Condition -Condition ($cleanupText.Contains("result = 'verifiedAbsent'")) -Message 'Cleanup distinguishes source-verified absence from a completed portal refresh'

$agentCleanupTokens = $null
$agentCleanupParseErrors = $null
$agentCleanupAst = [System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $projectRoot 'Invoke-DefenderAgentCleanup.ps1'),
    [ref]$agentCleanupTokens,
    [ref]$agentCleanupParseErrors
)
$blueprintDiscoveryFunction = $agentCleanupAst.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Get-PrefixedAgentBlueprintRecords'
}, $true)
Invoke-Expression $blueprintDiscoveryFunction.Extent.Text
function Invoke-MgGraphRequest {
    [CmdletBinding()]
    param([string]$Method, [string]$Uri)
    return [pscustomobject]@{
        value = @([pscustomobject]@{
            displayName = '[MXDR Demo] Single Page Agent'
            id = '11111111-1111-1111-1111-111111111111'
            appId = '22222222-2222-2222-2222-222222222222'
        })
    }
}
$singlePageDiscovery = @(Get-PrefixedAgentBlueprintRecords -Prefix '[MXDR Demo]')
Assert-Condition -Condition ($singlePageDiscovery.Count -eq 1) -Message 'Single-page blueprint discovery succeeds without @odata.nextLink'
Remove-Item -LiteralPath Function:\Invoke-MgGraphRequest -Force
Remove-Item -LiteralPath Function:\Get-PrefixedAgentBlueprintRecords -Force

$seederTokens = $null
$seederParseErrors = $null
$seederAst = [System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $projectRoot 'Invoke-DefenderBulkSeeder.ps1'),
    [ref]$seederTokens,
    [ref]$seederParseErrors
)
$createWithRecoveryFunction = $seederAst.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $node.Name -eq 'Invoke-CreateManualAlertWithRecovery'
}, $true)
Invoke-Expression $createWithRecoveryFunction.Extent.Text

$script:recoveryPostCalls = 0
function Invoke-MgGraphRequest {
    [CmdletBinding()]
    param([string]$Method, [string]$Uri, [string]$Body, [string]$ContentType, [string]$OutputType)
    $script:recoveryPostCalls++
    throw 'simulated HTTP timeout'
}
function Get-GraphStatusCode { param($ErrorRecord) return 408 }
function Wait-ManualAlertByMarker {
    param($Marker, $IncidentId, $NotBeforeUtc, $MaximumAttempts, $DelaySeconds)
    return [pscustomobject]@{ id = 'recovered-alert'; incidentId = '77'; title = 'Recovered' }
}
$recoveredAlert = Invoke-CreateManualAlertWithRecovery `
    -Body ([ordered]@{ title = 'Recovered'; description = 'marker' }) `
    -Marker '[MXDR-SEED:test:1:2]' `
    -IncidentId '77' `
    -AttemptedAtUtc ([DateTime]::UtcNow)
Assert-Condition -Condition ($recoveredAlert.id -eq 'recovered-alert') -Message 'Ambiguous POST response recovers the existing alert'
Assert-Condition -Condition ($script:recoveryPostCalls -eq 1) -Message 'Recovered ambiguous POST is not submitted twice'

$script:recoveryPostCalls = 0
function Invoke-MgGraphRequest {
    [CmdletBinding()]
    param([string]$Method, [string]$Uri, [string]$Body, [string]$ContentType, [string]$OutputType)
    $script:recoveryPostCalls++
    if ($script:recoveryPostCalls -eq 1) {
        throw 'simulated HTTP timeout'
    }
    return [pscustomobject]@{ id = 'retried-alert'; incidentId = '77'; title = 'Retried' }
}
function Wait-ManualAlertByMarker {
    param($Marker, $IncidentId, $NotBeforeUtc, $MaximumAttempts, $DelaySeconds)
    return $null
}
$retriedAlert = Invoke-CreateManualAlertWithRecovery `
    -Body ([ordered]@{ title = 'Retried'; description = 'marker' }) `
    -Marker '[MXDR-SEED:test:1:3]' `
    -IncidentId '77' `
    -AttemptedAtUtc ([DateTime]::UtcNow)
Assert-Condition -Condition ($retriedAlert.id -eq 'retried-alert') -Message 'Absent timed-out alert receives one controlled retry'
Assert-Condition -Condition ($script:recoveryPostCalls -eq 2) -Message 'Ambiguous POST is retried at most once after reconciliation'

foreach ($functionName in @('Invoke-MgGraphRequest', 'Get-GraphStatusCode', 'Wait-ManualAlertByMarker', 'Invoke-CreateManualAlertWithRecovery')) {
    Remove-Item -LiteralPath "Function:\$functionName" -Force -ErrorAction SilentlyContinue
}

$dryRun = & (Join-Path $projectRoot 'Invoke-DefenderBulkSeeder.ps1') `
    -GlobalAdminUpn 'offline.test@contoso.example' `
    -IncidentCount 50 `
    -CreateDemoAiAgents `
    -DemoAgentCount 10 `
    -AiIncidentCount 10 `
    -Confirm:$false | Where-Object { $_ -is [psobject] -and $_.PSObject.Properties.Name -contains 'Mode' } | Select-Object -Last 1
$dryRunAlertCount = (@($dryRun.Plan) | Measure-Object -Property Alerts -Sum).Sum
Assert-Condition -Condition ($dryRun.Mode -eq 'DryRun') -Message 'Mixed AI plan remains non-mutating without Execute'
Assert-Condition -Condition (@($dryRun.Plan).Count -eq 50) -Message 'Mixed default plan contains 50 incidents'
Assert-Condition -Condition ($dryRunAlertCount -eq 549) -Message 'Mixed default plan contains exactly 549 alerts'
Assert-Condition -Condition (@($dryRun.Plan | Where-Object { $_.AssociationMode -eq 'manualProxy' }).Count -eq 10) -Message 'Mixed plan contains the requested ten AI proxy incidents'
Assert-Condition -Condition (@($dryRun.Plan | Where-Object { $_.Alerts -lt 10 -or $_.Alerts -gt 12 }).Count -eq 0) -Message 'Every mixed-plan incident contains 10 through 12 alerts'

$cycledAgentDryRun = & (Join-Path $projectRoot 'Invoke-DefenderBulkSeeder.ps1') `
    -GlobalAdminUpn 'offline.test@contoso.example' `
    -IncidentCount 8 `
    -CreateDemoAiAgents `
    -DemoAgentCount 3 `
    -AiIncidentCount 8 `
    -Confirm:$false | Where-Object { $_ -is [psobject] -and $_.PSObject.Properties.Name -contains 'Mode' } | Select-Object -Last 1
$cycledAgentPlan = @($cycledAgentDryRun.Plan)
Assert-Condition -Condition ((@($cycledAgentPlan.AgentPoolPosition) -join ',') -eq '1,2,3,1,2,3,1,2') -Message 'AI incidents cycle through a smaller selected agent pool'
Assert-Condition -Condition ((@($cycledAgentPlan.AgentCatalogId) -join ',') -eq '1,2,3,1,2,3,1,2') -Message 'Cycled AI incidents retain the matching agent story profile'

$evaluatedDryRun = & (Join-Path $projectRoot 'Invoke-DefenderEvaluatedAgentLab.ps1') `
    -GlobalAdminUpn 'offline.test@contoso.example' `
    -AgentCount 7 `
    -Confirm:$false
$evaluatedPlan = @($evaluatedDryRun.Plan)
Assert-Condition -Condition ($evaluatedDryRun.Mode -eq 'DryRun') -Message 'Evaluated-agent planning is non-mutating without Execute'
Assert-Condition -Condition (($evaluatedPlan.TargetRisk -join ',') -eq 'low,medium,high,low,medium,high,low') -Message 'Evaluated-agent plan cycles through requested risk profiles'
Assert-Condition -Condition (@($evaluatedPlan | Where-Object { $_.Name -notlike '[[]MXDR Demo]*' }).Count -eq 0) -Message 'Every evaluated-agent name uses the exact MXDR Demo prefix'

$externalAgentManifestPath = [System.IO.Path]::GetTempFileName()
try {
    [ordered]@{
        schemaVersion = 1
        projectVersion = $version
        globalAdminUpn = 'offline.test@contoso.example'
        tenantId = '11111111-1111-1111-1111-111111111111'
        agents = @(
            foreach ($sequence in 1..3) {
                [ordered]@{
                    sequence = $sequence
                    displayName = "[MXDR Demo] Evaluated Agent $sequence"
                    description = 'Offline evaluated-agent fixture'
                    targetRisk = @('low', 'medium', 'high')[$sequence - 1]
                    authMode = if ($sequence -eq 3) { 'both' } else { 'obo' }
                    delegatedScopes = @('User.Read')
                    mcpServers = if ($sequence -gt 1) { @('mcp_MailTools') } else { @() }
                    mcpStatus = if ($sequence -gt 1) { 'configuredAndConsented' } else { 'notRequested' }
                    runtimeStatus = 'notDeployedBySeeder'
                    setupStatus = 'created'
                    permissionStatus = 'granted'
                    status = 'created'
                    safeGeneratedIds = [ordered]@{
                        agentBlueprintId = "00000000-0000-0000-0000-00000000000$sequence"
                        agentIdentityId = "10000000-0000-0000-0000-00000000000$sequence"
                        agentRegistrationId = "20000000-0000-0000-0000-00000000000$sequence"
                    }
                    errors = @()
                }
            }
        )
    } | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $externalAgentManifestPath -Encoding utf8

    $integratedDryRun = & (Join-Path $projectRoot 'Invoke-DefenderBulkSeeder.ps1') `
        -GlobalAdminUpn 'offline.test@contoso.example' `
        -IncidentCount 6 `
        -CreateDemoAiAgents `
        -DemoAgentCount 10 `
        -AiIncidentCount 6 `
        -EvaluatedAgentManifestPath $externalAgentManifestPath `
        -Confirm:$false | Where-Object { $_ -is [psobject] -and $_.PSObject.Properties.Name -contains 'Mode' } | Select-Object -Last 1
    $integratedPlan = @($integratedDryRun.Plan)
    Assert-Condition -Condition ($integratedDryRun.AgentMode -eq 'evaluated') -Message 'Bulk seeder recognizes the evaluated-agent manifest mode'
    Assert-Condition -Condition ([int]$integratedDryRun.DemoAgentCount -eq 3) -Message 'Bulk seeder uses the completed evaluated-agent count from the manifest'
    Assert-Condition -Condition ((@($integratedPlan.AgentPoolPosition) -join ',') -eq '1,2,3,1,2,3') -Message 'AI incidents cycle through the imported evaluated-agent pool'
}
finally {
    Remove-Item -LiteralPath $externalAgentManifestPath -Force -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    throw "Offline validation failed with $($failures.Count) error(s): $($failures -join '; ')"
}

Write-Host "All offline checks passed for Defender XDR Story Seeder $version." -ForegroundColor Green


