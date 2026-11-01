#requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $projectRoot 'src\M365SignInReport.psm1') -Force

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -ne $Expected) { throw "$Message Expected '$Expected', received '$Actual'." }
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$samplePath = Join-Path $projectRoot 'samples\sample-signins.json'
$exampleConfig = ([System.IO.File]::ReadAllText((Join-Path $projectRoot 'config.example.json')) | ConvertFrom-Json)
Assert-True (-not [bool]$exampleConfig.Authentication.UseDeviceCode) 'Interactive browser authentication must remain the delegated default.'
Assert-Equal ([int]$exampleConfig.Collection.ReportHours) 48 'The default sign-in collection window must remain 48 hours.'
Assert-True (@($exampleConfig.Collection.EventTypes) -notcontains 'nonInteractiveUser') 'Non-interactive user sign-ins must remain excluded from collection.'
Assert-True (@($exampleConfig.Collection.EventTypes) -notcontains 'managedIdentity') 'Managed-identity sign-ins must remain excluded from collection.'
Assert-True (@($exampleConfig.Collection.EventTypes) -notcontains 'servicePrincipal') 'Service-principal sign-ins must remain excluded from collection.'
Assert-Equal @($exampleConfig.Collection.EventTypes).Count 1 'Only interactive-user sign-ins should be configured for collection.'
$entryScript = [System.IO.File]::ReadAllText((Join-Path $projectRoot 'Invoke-M365SignInReport.ps1'))
Assert-True ($entryScript.Contains("'interactive browser'")) 'The default delegated flow must match the Intune collector interactive-browser pattern.'
$raw = @(Read-SignInInputFile -Path $samplePath)
$normalized = @($raw | ConvertTo-NormalizedSignIn)
Assert-Equal $normalized.Count 13 'The sample event count changed.'
Assert-Equal $normalized[4].TimeUtc '2026-11-01T00:00:00.0000000+00:00' 'UTC timestamps must not be shifted by the local time zone.'
Assert-Equal $normalized[5].ErrorCode 53003 'The Conditional Access error code was not normalized.'
Assert-Equal @($normalized[5].Policies).Count 2 'Applied Conditional Access policies were not preserved.'
$managedIdentity = $normalized[0].PSObject.Copy()
$managedIdentity.EventType = 'managedIdentity'
$managedIdentity.ActorType = 'ManagedIdentity'
$managedIdentity.IsInteractive = $false
$reportable = @(@($normalized) + @($managedIdentity) | Select-ReportableSignIn)
Assert-Equal $reportable.Count 11 'A non-user sign-in was not excluded.'
Assert-True (@($reportable | Where-Object EventType -eq 'nonInteractiveUser').Count -eq 0) 'A non-interactive user sign-in remained in the reportable records.'
Assert-True (@($reportable | Where-Object EventType -eq 'managedIdentity').Count -eq 0) 'A managed-identity sign-in remained in the reportable records.'
Assert-True (@($reportable | Where-Object EventType -eq 'servicePrincipal').Count -eq 0) 'A service-principal sign-in remained in the reportable records.'

$analysis = Get-SignInAnalysis -Records $reportable `
    -ReportStartUtc ([DateTimeOffset]'2026-10-31T23:00:00Z') `
    -ReportEndUtc ([DateTimeOffset]'2026-11-01T23:00:01Z')

Assert-Equal $analysis.BaselineCount 4 'The baseline event count is incorrect.'
Assert-Equal $analysis.CurrentCount 7 'The report event count is incorrect.'
Assert-Equal $analysis.FailureCount 6 'The failure count is incorrect.'
Assert-Equal $analysis.ConditionalAccessDenials 1 'The enforced Conditional Access denial count is incorrect.'
Assert-True (@($analysis.Findings | Where-Object Category -eq 'Password spray').Count -eq 1) 'The sample password spray was not detected.'
Assert-True (@($analysis.Findings | Where-Object Category -eq 'Location').Count -eq 1) 'The sample new-country sign-in was not detected.'
Assert-True (@($analysis.Findings | Where-Object Category -eq 'Potential impossible travel').Count -eq 1) 'The sample travel anomaly was not detected.'
Assert-True (@($analysis.Findings | Where-Object Category -eq 'Conditional Access').Count -eq 1) 'The sample Conditional Access denial was not detected.'

$duringRiskRecord = $normalized[0].PSObject.Copy()
$duringRiskRecord.TimeUtc = '2026-11-01T12:00:00.0000000+00:00'
$duringRiskRecord.RiskLevel = 'none'
$duringRiskRecord.RiskLevelDuringSignIn = 'medium'
$duringRiskRecord.RiskState = 'none'
$duringRiskRecord.RiskDetail = 'none'
$duringRiskRecord.RiskEventTypes = @()
$duringRiskAnalysis = Get-SignInAnalysis -Records @($duringRiskRecord) `
    -ReportStartUtc ([DateTimeOffset]'2026-11-01T00:00:00Z') `
    -ReportEndUtc ([DateTimeOffset]'2026-11-02T00:00:00Z')
$duringRiskFinding = @($duringRiskAnalysis.Findings | Where-Object Category -eq 'Identity risk')[0]
Assert-True ($null -ne $duringRiskFinding) 'Risk during sign-in did not create an identity-risk finding.'
Assert-True ($duringRiskFinding.Summary -like '*medium risk during sign-in*') 'The identity-risk summary did not identify the triggering field.'
Assert-True ($duringRiskFinding.Summary -notlike '*none sign-in risk*') 'The misleading none-risk summary returned.'

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('m365-signin-report-test-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $testRoot)
try {
    Save-NormalizedEventCache -Records $normalized -StateDirectory $testRoot -CollectedThroughUtc ([DateTimeOffset]'2026-11-01T23:00:01Z') -RetainFromUtc ([DateTimeOffset]'2026-10-18T00:00:00Z')
    Save-NormalizedEventCache -Records $normalized -StateDirectory $testRoot -CollectedThroughUtc ([DateTimeOffset]'2026-11-01T23:00:01Z') -RetainFromUtc ([DateTimeOffset]'2026-10-18T00:00:00Z')
    $cached = @(Get-NormalizedEventCache -StateDirectory $testRoot -StartTimeUtc ([DateTimeOffset]'2026-10-18T00:00:00Z') -EndTimeUtc ([DateTimeOffset]'2026-11-02T00:00:00Z'))
    Assert-Equal $cached.Count 13 'The rolling cache did not deduplicate repeated events.'
    Assert-Equal (Get-CacheCollectedThrough -StateDirectory $testRoot).ToUniversalTime().ToString('o') '2026-11-01T23:00:01.0000000+00:00' 'The cache cursor is incorrect.'

    $htmlPath = Join-Path $testRoot 'report.html'
    [void](New-SignInHtmlReport -Analysis $analysis -OutputPath $htmlPath -TenantName 'Smoke test tenant' -TenantId '11111111-2222-3333-4444-555555555555' -DisplayTimeZone 'UTC')
    Assert-True (Test-Path -LiteralPath $htmlPath) 'The HTML report was not created.'
    $html = [System.IO.File]::ReadAllText($htmlPath)
    Assert-True ($html.Contains('Block untrusted countries')) 'The report omitted the denying Conditional Access policy.'
    Assert-True ($html.Contains('Possible password spray')) 'The report omitted the password-spray finding.'
    Assert-True ($html.Contains('https://www.nexlinks.net/')) 'The report omitted the Nexlinks URL.'
    Assert-True ($html.Contains('data:image/png;base64,')) 'The report omitted the embedded Nexlinks website logo.'
    Assert-True (-not $html.Contains('M10 31V13l24 18V13')) 'The superseded vector logo remains in the report.'
    Assert-True ($html.Contains('Smoke test tenant')) 'The report omitted the tenant name.'
    Assert-True ($html.Contains('11111111-2222-3333-4444-555555555555')) 'The report omitted the tenant ID.'
}
finally {
    $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    $resolvedTest = [System.IO.Path]::GetFullPath($testRoot)
    if ($resolvedTest.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolvedTest) -like 'm365-signin-report-test-*') {
        Remove-Item -LiteralPath $resolvedTest -Recurse -Force
    }
}

Write-Host 'All M365 Sign-in Report smoke tests passed.' -ForegroundColor Green
