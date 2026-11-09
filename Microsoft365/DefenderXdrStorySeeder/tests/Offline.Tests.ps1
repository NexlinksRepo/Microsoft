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
    'DefenderXdrStorySeeder.Agent365.ps1'
    'Start-DefenderAgentRegistrationRetry.ps1'
    'Invoke-DefenderAgentRegistrationRetry.ps1'
    'Start-DefenderBulkCleanup.ps1'
    'Invoke-DefenderBulkCleanup.ps1'
    'Build-Release.ps1'
    'README.md'
    'CHANGELOG.md'
    'SECURITY.md'
    'VERSION'
    'catalog\attack-catalog.json'
    'catalog\ai-agent-catalog.json'
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
    'DefenderXdrStorySeeder.Agent365.ps1'
    'Start-DefenderAgentRegistrationRetry.ps1'
    'Invoke-DefenderAgentRegistrationRetry.ps1'
    'Start-DefenderBulkCleanup.ps1'
    'Invoke-DefenderBulkCleanup.ps1'
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
$launcherText = Get-Content -LiteralPath (Join-Path $projectRoot 'Start-DefenderBulkSeed.ps1') -Raw
$agentHelperText = Get-Content -LiteralPath (Join-Path $projectRoot 'DefenderXdrStorySeeder.Agent365.ps1') -Raw
$registrationRetryText = Get-Content -LiteralPath (Join-Path $projectRoot 'Invoke-DefenderAgentRegistrationRetry.ps1') -Raw
$readmeText = Get-Content -LiteralPath (Join-Path $projectRoot 'README.md') -Raw
$changelogText = Get-Content -LiteralPath (Join-Path $projectRoot 'CHANGELOG.md') -Raw
Assert-Condition -Condition ($seederText.Contains("`$ProjectVersion = '$version'")) -Message 'Seeder version matches VERSION'
Assert-Condition -Condition ($cleanupText.Contains("`$ProjectVersion = '$version'")) -Message 'Cleanup version matches VERSION'
Assert-Condition -Condition ($registrationRetryText.Contains("`$ProjectVersion = '$version'")) -Message 'Registration retry version matches VERSION'
Assert-Condition -Condition ($agentHelperText.Contains("`$script:AgentSeederVersion = '$version'")) -Message 'Agent helper version matches VERSION'
Assert-Condition -Condition ($readmeText.Contains("Current version: **$version**")) -Message 'README version matches VERSION'
Assert-Condition -Condition ($changelogText.Contains("## $version")) -Message 'Changelog contains the current version'
Assert-Condition -Condition ($launcherText.Contains("How many incidents should be created?")) -Message 'Launcher prompts for incident count'
Assert-Condition -Condition ($launcherText.Contains("Create dormant demo AI agents")) -Message 'Launcher prompts for optional demo agents'
Assert-Condition -Condition ($launcherText.Contains("`$PSBoundParameters.ContainsKey('IncidentCount')")) -Message 'IncidentCount bypasses the interactive count prompt'

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
Assert-Condition -Condition ($agentHelperText.Contains('credentialsCreated       = $false')) -Message 'Demo agents do not create stored credentials'
Assert-Condition -Condition ($agentHelperText.Contains('permissionGrantsCreated  = @()')) -Message 'Demo agents do not auto-grant declared permissions'
Assert-Condition -Condition (-not $agentHelperText.Contains('managedByAppId =')) -Message 'Registry payload does not misidentify the blueprint as the calling management app'
Assert-Condition -Condition ($agentHelperText.Contains('ownerIds = @($OwnerId)')) -Message 'Registry payload satisfies the owner requirement'
Assert-Condition -Condition ($agentHelperText.Contains('Get-AgentGraphErrorInfo')) -Message 'Agent errors retain status and response details'
Assert-Condition -Condition ($registrationRetryText.Contains('Register-DemoAiAgent')) -Message 'Registration-only retry reuses existing agent identities'
Assert-Condition -Condition (-not $registrationRetryText.Contains('New-DemoAiAgent')) -Message 'Registration-only retry cannot create duplicate agent identities'
Assert-Condition -Condition ($registrationRetryText.Contains("'AgentRegistration.ReadWrite.All' -notin")) -Message 'Registration retry verifies the delegated scope is present'
Assert-Condition -Condition ($cleanupText.Contains('agentRegistrations/$registrationId')) -Message 'Cleanup removes only recorded registry IDs'
Assert-Condition -Condition ($cleanupText.Contains('microsoft.graph.agentIdentityBlueprint')) -Message 'Cleanup uses blueprint cascade deletion'

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

if ($failures.Count -gt 0) {
    throw "Offline validation failed with $($failures.Count) error(s): $($failures -join '; ')"
}

Write-Host "All offline checks passed for Defender XDR Story Seeder $version." -ForegroundColor Green
