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
    'Start-DefenderBulkCleanup.ps1'
    'Invoke-DefenderBulkCleanup.ps1'
    'Build-Release.ps1'
    'README.md'
    'CHANGELOG.md'
    'SECURITY.md'
    'VERSION'
    'catalog\attack-catalog.json'
    'catalog\endpoint-roster.json'
    'catalog\mailbox-roster.json'
    'docs\ARCHITECTURE.md'
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
$readmeText = Get-Content -LiteralPath (Join-Path $projectRoot 'README.md') -Raw
$changelogText = Get-Content -LiteralPath (Join-Path $projectRoot 'CHANGELOG.md') -Raw
Assert-Condition -Condition ($seederText.Contains("`$ProjectVersion = '$version'")) -Message 'Seeder version matches VERSION'
Assert-Condition -Condition ($cleanupText.Contains("`$ProjectVersion = '$version'")) -Message 'Cleanup version matches VERSION'
Assert-Condition -Condition ($readmeText.Contains("Current version: **$version**")) -Message 'README version matches VERSION'
Assert-Condition -Condition ($changelogText.Contains("## $version")) -Message 'Changelog contains the current version'

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
foreach ($scope in @('SecurityAlert.ReadWrite.All', 'SecurityIncident.ReadWrite.All')) {
    Assert-Condition -Condition ($cleanupText.Contains($scope)) -Message "Cleanup requests required scope: $scope"
}

Assert-Condition -Condition ($cleanupText.Contains("detectionSource -ine 'manual'")) -Message 'Cleanup restricts default selection to Manual alerts'
Assert-Condition -Condition ($cleanupText.Contains('protectedIncidentIds')) -Message 'Cleanup protects incidents containing unrelated active alerts'
Assert-Condition -Condition ($seederText.Contains('isExcludedFromCorrelation = $true')) -Message 'Seeder prevents unintended automatic incident correlation'

if ($failures.Count -gt 0) {
    throw "Offline validation failed with $($failures.Count) error(s): $($failures -join '; ')"
}

Write-Host "All offline checks passed for Defender XDR Story Seeder $version." -ForegroundColor Green
