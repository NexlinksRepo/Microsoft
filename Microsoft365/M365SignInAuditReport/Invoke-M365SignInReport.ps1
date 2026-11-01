<#
.SYNOPSIS
Collects Microsoft Entra interactive-user sign-ins and creates an analyst-focused HTML report.

.DESCRIPTION
Authenticates to Microsoft Graph, retrieves interactive-user sign-in events for a selected time
window, preserves the raw Graph evidence, normalizes records into a tenant-scoped local cache, and
analyzes failures, Conditional Access outcomes, identity risk, authentication bursts, possible
password spraying, unusual locations, impossible travel, and successful legacy authentication.

The default interactive window is the previous 48 hours. Non-interactive user, service-principal,
and managed-identity sign-ins are excluded. Each run writes a self-contained HTML report, metadata,
raw JSONL, and exact Graph response pages under the configured output directory.

.PARAMETER ConfigPath
Path to a JSON configuration file. Defaults to config.json beside this script when that file exists.

.PARAMETER AuthMode
Authentication method: Delegated, Certificate, ManagedIdentity, or ExistingSession.

.PARAMETER TenantId
Microsoft Entra tenant ID. Optional for delegated sign-in and required for certificate authentication.

.PARAMETER TenantName
Tenant display name override. Delegated runs resolve the name from Microsoft Graph when omitted.

.PARAMETER ClientId
Application/client ID for certificate authentication, a custom delegated application, or a
user-assigned managed identity.

.PARAMETER CertificateThumbprint
Certificate thumbprint used with Certificate authentication.

.PARAMETER UseDeviceCode
Uses Microsoft Graph device-code authentication instead of the interactive browser flow.

.PARAMETER InputFile
Reads sign-ins from a JSON or JSONL file without connecting to Microsoft Graph. Intended for
development, testing, and controlled report regeneration.

.PARAMETER ReportHours
Default report duration when StartTime is omitted. Defaults to 48 hours.

.PARAMETER BaselineDays
Number of historical days retained for location and travel baselines. Defaults to 14 days.

.PARAMETER StartTime
Beginning of the report window. ISO 8601 values with an explicit UTC offset are recommended.

.PARAMETER EndTime
End of the report window. Defaults to the current time.

.PARAMETER OutputDirectory
Destination for timestamped run folders, the analysis cache, and latest-report.html.

.PARAMETER ForceBaselineBackfill
Requests the configured historical baseline window from Graph instead of only the report window.

.PARAMETER NoOpenReport
Creates the report without opening it in a browser.

.PARAMETER NonInteractive
Disables prompts and browser launch. Delegated authentication is not supported in this mode.

.EXAMPLE
PS> .\Invoke-M365SignInReport.ps1

Prompts for an optional local From/To window, authenticates interactively, and opens the report.

.EXAMPLE
PS> .\Invoke-M365SignInReport.ps1 -StartTime '2026-11-01T00:00:00-04:00' -EndTime '2026-11-02T00:00:00-05:00'

Runs a specific time window without displaying the date prompts.

.EXAMPLE
PS> .\Invoke-M365SignInReport.ps1 -InputFile .\samples\sample-signins.json -NoOpenReport

Exercises normalization, analysis, and HTML generation without accessing a tenant.

.NOTES
Beta v0.0.1. Sign-in logs contain sensitive identity and security data. The output directory and
config.json are intentionally excluded from source control by the supplied .gitignore.
#>
#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$ConfigPath,
    [ValidateSet('Delegated', 'Certificate', 'ManagedIdentity', 'ExistingSession')][string]$AuthMode,
    [string]$TenantId,
    [string]$TenantName,
    [string]$ClientId,
    [string]$CertificateThumbprint,
    [switch]$UseDeviceCode,
    [string]$InputFile,
    [Nullable[int]]$ReportHours,
    [Nullable[int]]$BaselineDays,
    [Nullable[DateTimeOffset]]$StartTime,
    [Nullable[DateTimeOffset]]$EndTime,
    [string]$OutputDirectory,
    [switch]$ForceBaselineBackfill,
    [switch]$NoOpenReport,
    [switch]$NonInteractive
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$invocationParameters = @{} + $PSBoundParameters
$ConfigPath = if ([string]::IsNullOrWhiteSpace($ConfigPath)) { Join-Path $PSScriptRoot 'config.json' } else { $ConfigPath }
$projectVersion = '0.0.1-beta'
$moduleName = 'Microsoft.Graph.Authentication'
$modulePath = Join-Path $PSScriptRoot 'src\M365SignInReport.psm1'

function Get-LocalProperty {
    param([AllowNull()]$Object, [string]$Name, [AllowNull()]$Default = $null)
    if ($null -eq $Object) { return $Default }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $Default
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    return $property.Value
}

function Get-ConfigSetting {
    param([AllowNull()]$Config, [string[]]$Path, [AllowNull()]$Default = $null)
    $current = $Config
    foreach ($segment in $Path) {
        $current = Get-LocalProperty -Object $current -Name $segment -Default $null
        if ($null -eq $current) { return $Default }
    }
    return $current
}

function Resolve-ProjectPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    if ([System.IO.Path]::IsPathRooted($Path)) { return [System.IO.Path]::GetFullPath($Path) }
    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot $Path))
}

function Read-OptionalLocalDateTime {
    param([Parameter(Mandatory = $true)][string]$Prompt)

    while ($true) {
        $text = Read-Host $Prompt
        if ([string]::IsNullOrWhiteSpace($text)) { return $null }
        $parsed = [datetime]::MinValue
        if ([datetime]::TryParseExact($text.Trim(), 'yyyy-MM-dd HH:mm', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeLocal, [ref]$parsed)) {
            return [DateTimeOffset]$parsed
        }
        Write-Warning "Invalid date and time. Use yyyy-MM-dd HH:mm, for example 2026-11-01 08:00, or press Enter for the default."
    }
}

function Write-ReportStatus {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateRange(0, 100)][int]$PercentComplete
    )

    Write-Progress -Id 17 -Activity 'M365 Sign-in Report' -Status $Message -PercentComplete $PercentComplete
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Message" -ForegroundColor Cyan
}

function Open-ReportInNewBrowserWindow {
    param([Parameter(Mandatory = $true)][string]$Path)

    $resolvedPath = (Resolve-Path -LiteralPath $Path).Path
    $reportUri = ([Uri]$resolvedPath).AbsoluteUri
    $progId = ''
    $userChoicePath = 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice'
    if (Test-Path -LiteralPath $userChoicePath) {
        $progId = [string](Get-ItemProperty -LiteralPath $userChoicePath -Name ProgId -ErrorAction SilentlyContinue).ProgId
    }

    $browser = $null
    $browserArguments = @()
    $candidatePaths = [System.Collections.Generic.List[string]]::new()
    if ($progId -like '*ChromeHTML*') {
        $browser = Get-Command chrome.exe -ErrorAction SilentlyContinue | Select-Object -First 1
        foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA)) {
            if (-not [string]::IsNullOrWhiteSpace($root)) { $candidatePaths.Add((Join-Path $root 'Google\Chrome\Application\chrome.exe')) }
        }
        $browserArguments = @('--new-window', $reportUri)
    }
    elseif ($progId -like '*MSEdgeHTM*') {
        $browser = Get-Command msedge.exe -ErrorAction SilentlyContinue | Select-Object -First 1
        foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA)) {
            if (-not [string]::IsNullOrWhiteSpace($root)) { $candidatePaths.Add((Join-Path $root 'Microsoft\Edge\Application\msedge.exe')) }
        }
        $browserArguments = @('--new-window', $reportUri)
    }
    elseif ($progId -like '*FirefoxURL*') {
        $browser = Get-Command firefox.exe -ErrorAction SilentlyContinue | Select-Object -First 1
        foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
            if (-not [string]::IsNullOrWhiteSpace($root)) { $candidatePaths.Add((Join-Path $root 'Mozilla Firefox\firefox.exe')) }
        }
        $browserArguments = @('-new-window', $reportUri)
    }

    if ($null -eq $browser) {
        $browserPath = $candidatePaths | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if (-not [string]::IsNullOrWhiteSpace($browserPath)) { $browser = [pscustomobject]@{ Source = $browserPath } }
    }
    if ($null -ne $browser) {
        Start-Process -FilePath $browser.Source -ArgumentList $browserArguments
        return $progId
    }

    Start-Process -FilePath $resolvedPath
    return 'the default browser'
}

function Ensure-GraphAuthenticationModule {
    param([switch]$DoNotPrompt)

    $available = Get-Module -ListAvailable -Name $moduleName | Sort-Object Version -Descending | Select-Object -First 1
    if ($null -ne $available) { return }

    $installCommand = "Install-Module $moduleName -Scope CurrentUser -Repository PSGallery"
    if ($DoNotPrompt) {
        throw "Required module '$moduleName' is missing. Install it first with: $installCommand"
    }

    $caption = 'M365 Sign-in Report prerequisite'
    $message = "The required PowerShell module '$moduleName' is not installed. Install it for the current user from PowerShell Gallery now?"
    $choices = [System.Management.Automation.Host.ChoiceDescription[]]@(
        [System.Management.Automation.Host.ChoiceDescription]::new('&Yes', 'Install the Microsoft Graph authentication module for the current user.'),
        [System.Management.Automation.Host.ChoiceDescription]::new('&No', 'Stop without changing installed modules.')
    )
    $decision = $Host.UI.PromptForChoice($caption, $message, $choices, 1)
    if ($decision -ne 0) { throw "Installation declined. Run this command when ready: $installCommand" }

    Write-Host "Installing $moduleName for the current user..." -ForegroundColor Cyan
    try {
        Install-Module -Name $moduleName -Scope CurrentUser -Repository PSGallery -AllowClobber -Force -ErrorAction Stop
    }
    catch {
        throw "The module installation failed. Install it manually with '$installCommand'. $($_.Exception.Message)"
    }
}

function Connect-ReportGraphSession {
    param(
        [string]$Mode,
        [string]$DirectoryId,
        [string]$ApplicationId,
        [string]$Thumbprint,
        [bool]$DeviceCode
    )

    if ($Mode -eq 'ExistingSession') {
        $existing = Get-MgContext
        if ($null -eq $existing) { throw 'AuthMode ExistingSession was selected, but no Microsoft Graph session is connected.' }
        return $false
    }

    if ($Mode -eq 'Delegated') {
        $connectParameters = @{
            Scopes       = @('User.Read', 'AuditLog.Read.All', 'Policy.Read.ConditionalAccess')
            ContextScope = 'Process'
            NoWelcome    = $true
            ErrorAction  = 'Stop'
        }
        if (-not [string]::IsNullOrWhiteSpace($DirectoryId)) { $connectParameters.TenantId = $DirectoryId }
        if (-not [string]::IsNullOrWhiteSpace($ApplicationId)) { $connectParameters.ClientId = $ApplicationId }
        if ($DeviceCode) {
            $connectParameters.UseDeviceCode = $true
        }
        $flow = if ($DeviceCode) { 'device-code' } else { 'interactive browser' }
        Write-Host "Starting Microsoft Graph $flow sign-in..." -ForegroundColor Cyan
        if ($DeviceCode) {
            # The Graph module emits device-code instructions on the success stream.
            Connect-MgGraph @connectParameters | Out-Host
        }
        else {
            Connect-MgGraph @connectParameters | Out-Null
        }
        return $true
    }

    if ([string]::IsNullOrWhiteSpace($DirectoryId)) { throw "TenantId is required for $Mode authentication." }
    if ($Mode -eq 'Certificate') {
        if ([string]::IsNullOrWhiteSpace($ApplicationId) -or [string]::IsNullOrWhiteSpace($Thumbprint)) {
            throw 'ClientId and CertificateThumbprint are required for Certificate authentication.'
        }
        Connect-MgGraph -TenantId $DirectoryId -ClientId $ApplicationId -CertificateThumbprint $Thumbprint -ContextScope Process -NoWelcome -ErrorAction Stop | Out-Null
        return $true
    }
    if ($Mode -eq 'ManagedIdentity') {
        if ([string]::IsNullOrWhiteSpace($ApplicationId)) {
            Connect-MgGraph -Identity -ContextScope Process -NoWelcome -ErrorAction Stop | Out-Null
        }
        else {
            Connect-MgGraph -Identity -ClientId $ApplicationId -ContextScope Process -NoWelcome -ErrorAction Stop | Out-Null
        }
        return $true
    }
    throw "Unsupported authentication mode '$Mode'."
}

function Get-GraphTenantDisplayName {
    param([Parameter(Mandatory = $true)][string]$DirectoryId)

    try {
        $uri = "https://graph.microsoft.com/v1.0/organization/${DirectoryId}?`$select=id,displayName"
        $organization = Invoke-MgGraphRequest -Method GET -Uri $uri -ErrorAction Stop
        return [string](Get-LocalProperty -Object $organization -Name 'displayName' -Default '')
    }
    catch {
        Write-Warning "The tenant display name could not be resolved from Microsoft Graph. Set TenantName in config.json if needed. $($_.Exception.Message)"
        return ''
    }
}

$config = $null
if (Test-Path -LiteralPath $ConfigPath) {
    try { $config = ([System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $ConfigPath).Path) | ConvertFrom-Json) }
    catch { throw "Could not read config file '$ConfigPath'. $($_.Exception.Message)" }
}

if (-not $invocationParameters.ContainsKey('AuthMode')) { $AuthMode = [string](Get-ConfigSetting $config @('Authentication', 'Mode') 'Delegated') }
if (-not $invocationParameters.ContainsKey('TenantId')) { $TenantId = [string](Get-ConfigSetting $config @('Authentication', 'TenantId') '') }
if (-not $invocationParameters.ContainsKey('TenantName')) { $TenantName = [string](Get-ConfigSetting $config @('TenantName') (Get-ConfigSetting $config @('TenantLabel') '')) }
if (-not $invocationParameters.ContainsKey('ClientId')) { $ClientId = [string](Get-ConfigSetting $config @('Authentication', 'ClientId') '') }
if (-not $invocationParameters.ContainsKey('CertificateThumbprint')) { $CertificateThumbprint = [string](Get-ConfigSetting $config @('Authentication', 'CertificateThumbprint') '') }
if (-not $invocationParameters.ContainsKey('UseDeviceCode')) { $UseDeviceCode = [bool](Get-ConfigSetting $config @('Authentication', 'UseDeviceCode') $false) }
if (-not $invocationParameters.ContainsKey('ReportHours')) { $ReportHours = [int](Get-ConfigSetting $config @('Collection', 'ReportHours') 48) }
if (-not $invocationParameters.ContainsKey('BaselineDays')) { $BaselineDays = [int](Get-ConfigSetting $config @('Collection', 'BaselineDays') 14) }
if (-not $invocationParameters.ContainsKey('OutputDirectory')) { $OutputDirectory = [string](Get-ConfigSetting $config @('OutputDirectory') '.\output') }

$graphApiVersion = [string](Get-ConfigSetting $config @('Collection', 'GraphApiVersion') 'beta')
$eventTypes = @((Get-ConfigSetting $config @('Collection', 'EventTypes') @('interactiveUser')) | Where-Object { [string]$_ -eq 'interactiveUser' })
$pageSize = [int](Get-ConfigSetting $config @('Collection', 'PageSize') 1000)
$brandName = [string](Get-ConfigSetting $config @('Branding', 'Name') 'Nexlinks')
$brandUrl = [string](Get-ConfigSetting $config @('Branding', 'Url') 'https://www.nexlinks.net/')
$displayTimeZone = [string](Get-ConfigSetting $config @('DisplayTimeZone') 'Local')
$maximumDetailRows = [int](Get-ConfigSetting $config @('Report', 'MaximumDetailRows') 500)
$openReportFromConfig = [bool](Get-ConfigSetting $config @('Report', 'OpenAfterGeneration') $true)
$minimumUserBaselineEvents = [int](Get-ConfigSetting $config @('Analysis', 'MinimumUserBaselineEvents') 3)
$passwordSprayDistinctUsers = [int](Get-ConfigSetting $config @('Analysis', 'PasswordSprayDistinctUsers') 5)
$failureBurstThreshold = [int](Get-ConfigSetting $config @('Analysis', 'FailureBurstThreshold') 10)
$impossibleTravelSpeedKph = [int](Get-ConfigSetting $config @('Analysis', 'ImpossibleTravelSpeedKph') 900)
$impossibleTravelMinimumKm = [int](Get-ConfigSetting $config @('Analysis', 'ImpossibleTravelMinimumKm') 500)
$knownCountries = @(Get-ConfigSetting $config @('Analysis', 'KnownCountries') @())

if ([int]$ReportHours -lt 1 -or [int]$ReportHours -gt 720) { throw 'ReportHours must be between 1 and 720.' }
if ([int]$BaselineDays -lt 1 -or [int]$BaselineDays -gt 90) { throw 'BaselineDays must be between 1 and 90.' }
if ($graphApiVersion -notin @('beta', 'v1.0')) { throw "Collection.GraphApiVersion must be 'beta' or 'v1.0'." }

$outputRoot = Resolve-ProjectPath $OutputDirectory
[void](New-Item -ItemType Directory -Force -Path $outputRoot)
$promptedStart = $null
$promptedEnd = $null
if ([string]::IsNullOrWhiteSpace($InputFile) -and -not $NonInteractive -and -not $invocationParameters.ContainsKey('StartTime') -and -not $invocationParameters.ContainsKey('EndTime')) {
    $localZoneName = [TimeZoneInfo]::Local.DisplayName
    Write-Host "Choose the sign-in window in local time ($localZoneName). Press Enter at both prompts for the last 48 hours." -ForegroundColor Cyan
    $promptedStart = Read-OptionalLocalDateTime 'From (yyyy-MM-dd HH:mm; blank = 48 hours before To)'
    $promptedEnd = Read-OptionalLocalDateTime 'To   (yyyy-MM-dd HH:mm; blank = now)'
}

$endTimeUtc = if ($null -ne $EndTime) {
    ([DateTimeOffset]$EndTime).ToUniversalTime()
} elseif ($null -ne $promptedEnd) {
    ([DateTimeOffset]$promptedEnd).ToUniversalTime()
} else {
    [DateTimeOffset]::UtcNow
}
$reportStartUtc = if ($null -ne $StartTime) {
    ([DateTimeOffset]$StartTime).ToUniversalTime()
} elseif ($null -ne $promptedStart) {
    ([DateTimeOffset]$promptedStart).ToUniversalTime()
} else {
    $endTimeUtc.AddHours(-1 * [int]$ReportHours)
}
if ($reportStartUtc -ge $endTimeUtc) { throw 'The From date/time must be earlier than the To date/time.' }
$baselineStartUtc = $endTimeUtc.AddDays(-1 * [int]$BaselineDays)
$cacheStartUtc = if ($reportStartUtc -lt $baselineStartUtc) { $reportStartUtc } else { $baselineStartUtc }
$runName = $endTimeUtc.ToString('yyyyMMddTHHmmssZ')
$runDirectory = Join-Path $outputRoot $runName
if (Test-Path -LiteralPath $runDirectory) { $runDirectory += '-' + [guid]::NewGuid().ToString('N').Substring(0, 6) }
$rawDirectory = Join-Path $runDirectory 'raw'
[void](New-Item -ItemType Directory -Force -Path $rawDirectory)

Import-Module $modulePath -Force -ErrorAction Stop
$connectedByScript = $false
$collection = $null
$allRecords = @()
$excludedNonInteractiveCount = 0
$excludedManagedIdentityCount = 0
$excludedServicePrincipalCount = 0
$queryStartUtc = $reportStartUtc
$context = $null

try {
    Write-ReportStatus -Message 'Preparing the collection run and output folders...' -PercentComplete 5
    if (-not [string]::IsNullOrWhiteSpace($InputFile)) {
        Write-ReportStatus -Message "Loading offline input: $InputFile" -PercentComplete 15
        $inputEvents = @(Read-SignInInputFile -Path $InputFile)
        Write-ReportStatus -Message "Normalizing $($inputEvents.Count) offline sign-in records..." -PercentComplete 35
        $allRecords = @($inputEvents | ConvertTo-NormalizedSignIn)
        if (-not $invocationParameters.ContainsKey('EndTime') -and $allRecords.Count -gt 0) {
            $endTimeUtc = ([DateTimeOffset](($allRecords | Sort-Object TimeUtc -Descending | Select-Object -First 1).TimeUtc)).AddSeconds(1)
            if (-not $invocationParameters.ContainsKey('StartTime')) { $reportStartUtc = $endTimeUtc.AddHours(-1 * [int]$ReportHours) }
            $baselineStartUtc = $endTimeUtc.AddDays(-1 * [int]$BaselineDays)
            $cacheStartUtc = if ($reportStartUtc -lt $baselineStartUtc) { $reportStartUtc } else { $baselineStartUtc }
        }
        $originalName = 'input-original' + [System.IO.Path]::GetExtension($InputFile)
        Copy-Item -LiteralPath (Resolve-Path -LiteralPath $InputFile).Path -Destination (Join-Path $rawDirectory $originalName)
        $writer = [System.IO.StreamWriter]::new((Join-Path $rawDirectory 'signins.jsonl'), $false, [System.Text.UTF8Encoding]::new($false))
        try { foreach ($item in $inputEvents) { $writer.WriteLine(($item | ConvertTo-Json -Depth 50 -Compress)) } }
        finally { $writer.Dispose() }
        $collection = [pscustomobject]@{ Statistics = @([pscustomobject]@{ EventType = 'offline-input'; Pages = 1; Events = $inputEvents.Count }); JsonlPath = (Join-Path $rawDirectory 'signins.jsonl') }
        if ([string]::IsNullOrWhiteSpace($TenantName)) { $TenantName = 'Offline sign-in data' }
    }
    else {
        Write-ReportStatus -Message 'Checking Microsoft Graph prerequisites...' -PercentComplete 10
        Ensure-GraphAuthenticationModule -DoNotPrompt:$NonInteractive
        Import-Module $moduleName -ErrorAction Stop
        if ($AuthMode -eq 'Delegated' -and $NonInteractive) { throw 'Delegated authentication is interactive. Use Certificate or ManagedIdentity authentication with -NonInteractive.' }
        Write-ReportStatus -Message 'Waiting for Microsoft Graph authentication...' -PercentComplete 15
        $connectedByScript = Connect-ReportGraphSession -Mode $AuthMode -DirectoryId $TenantId -ApplicationId $ClientId -Thumbprint $CertificateThumbprint -DeviceCode ([bool]$UseDeviceCode)
        $context = Get-MgContext
        if ($null -eq $context) { throw 'Microsoft Graph did not return a connected context.' }
        Write-Host "Connected to Microsoft Graph as $($context.Account) in tenant $($context.TenantId)." -ForegroundColor Green
        if ([string]::IsNullOrWhiteSpace($TenantName)) {
            Write-ReportStatus -Message 'Resolving the Microsoft 365 tenant name...' -PercentComplete 20
            $TenantName = Get-GraphTenantDisplayName -DirectoryId ([string]$context.TenantId)
        }
        if ([string]::IsNullOrWhiteSpace($TenantName)) { $TenantName = 'Microsoft 365 tenant' }

        $stateDirectory = Join-Path (Join-Path $outputRoot '_state') ([string]$context.TenantId)
        $queryStartUtc = if ($ForceBaselineBackfill) { $cacheStartUtc } else { $reportStartUtc }
        Write-ReportStatus -Message "Collecting interactive sign-ins from $($queryStartUtc.ToString('u')) through $($endTimeUtc.ToString('u'))..." -PercentComplete 25
        $collection = Get-GraphSignInEvents -StartTimeUtc $queryStartUtc -EndTimeUtc $endTimeUtc -RawDirectory $rawDirectory -GraphApiVersion $graphApiVersion -EventTypes $eventTypes -PageSize $pageSize
        Write-ReportStatus -Message "Collection complete. Normalizing $(@($collection.Events).Count) retrieved records..." -PercentComplete 50
        $newRecords = @($collection.Events | ConvertTo-NormalizedSignIn)
        Write-ReportStatus -Message 'Updating the local analysis cache...' -PercentComplete 57
        Save-NormalizedEventCache -Records $newRecords -StateDirectory $stateDirectory -CollectedThroughUtc $endTimeUtc -RetainFromUtc $cacheStartUtc
        Write-ReportStatus -Message 'Loading the retained location baseline...' -PercentComplete 62
        $allRecords = @(Get-NormalizedEventCache -StateDirectory $stateDirectory -StartTimeUtc $cacheStartUtc -EndTimeUtc $endTimeUtc)
    }

    Write-ReportStatus -Message 'Filtering the collected records to interactive-user sign-ins...' -PercentComplete 68
    $excludedNonInteractiveCount = @($allRecords | Where-Object {
        $recordEventTypes = @(([string]$_.EventType -split '\s*,\s*') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        ($recordEventTypes -contains 'nonInteractiveUser') -or
            (($recordEventTypes -contains 'unspecified') -and [string]$_.ActorType -eq 'User' -and -not [bool]$_.IsInteractive)
    }).Count
    $excludedManagedIdentityCount = @($allRecords | Where-Object {
        $recordEventTypes = @(([string]$_.EventType -split '\s*,\s*') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        ($recordEventTypes -contains 'managedIdentity') -or [string]$_.ActorType -eq 'ManagedIdentity'
    }).Count
    $excludedServicePrincipalCount = @($allRecords | Where-Object {
        $recordEventTypes = @(([string]$_.EventType -split '\s*,\s*') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        ($recordEventTypes -contains 'servicePrincipal') -or [string]$_.ActorType -eq 'ServicePrincipal'
    }).Count
    $allRecords = @($allRecords | Select-ReportableSignIn)

    Write-ReportStatus -Message "Analyzing $($allRecords.Count) records for failures, Conditional Access results, and anomalies..." -PercentComplete 75
    $analysis = Get-SignInAnalysis -Records $allRecords -ReportStartUtc $reportStartUtc -ReportEndUtc $endTimeUtc `
        -MinimumUserBaselineEvents $minimumUserBaselineEvents -PasswordSprayDistinctUsers $passwordSprayDistinctUsers `
        -FailureBurstThreshold $failureBurstThreshold -ImpossibleTravelSpeedKph $impossibleTravelSpeedKph `
        -ImpossibleTravelMinimumKm $impossibleTravelMinimumKm -KnownCountries $knownCountries

    $reportPath = Join-Path $runDirectory 'report.html'
    $reportTenantId = if ($null -ne $context) { [string]$context.TenantId } else { [string]$TenantId }
    Write-ReportStatus -Message 'Building the HTML analyst report...' -PercentComplete 85
    [void](New-SignInHtmlReport -Analysis $analysis -OutputPath $reportPath -TenantName $TenantName -TenantId $reportTenantId `
        -BrandName $brandName -BrandUrl $brandUrl -DisplayTimeZone $displayTimeZone `
        -MaximumDetailRows $maximumDetailRows -RawDataRelativePath 'raw/signins.jsonl')

    $metadata = [ordered]@{
        SchemaVersion = 1
        ProjectVersion = $projectVersion
        GeneratedUtc = [DateTimeOffset]::UtcNow.ToString('o')
        TenantName = $TenantName
        TenantLabel = $TenantName
        Branding = [ordered]@{ Name = $brandName; Url = $brandUrl }
        TenantId = if ([string]::IsNullOrWhiteSpace($reportTenantId)) { $null } else { $reportTenantId }
        Account = if ($null -ne $context) { [string]$context.Account } else { $null }
        AuthenticationMode = if ($InputFile) { 'Offline' } else { $AuthMode }
        AuthenticationFlow = if ($InputFile) { 'Offline' } elseif ($AuthMode -ne 'Delegated') { 'AppOnly' } elseif ([bool]$UseDeviceCode) { 'DeviceCode' } else { 'InteractiveBrowser' }
        GraphApiVersion = if ($InputFile) { $null } else { $graphApiVersion }
        QueryStartUtc = $queryStartUtc.ToString('o')
        ReportStartUtc = $reportStartUtc.ToString('o')
        ReportEndUtc = $endTimeUtc.ToString('o')
        BaselineStartUtc = $baselineStartUtc.ToString('o')
        RawEventCount = @($collection.Statistics | Measure-Object Events -Sum).Sum
        AnalyzedEventCount = $allRecords.Count
        CollectionStatistics = @($collection.Statistics)
        Summary = [ordered]@{
            SignIns = $analysis.CurrentCount
            Successes = $analysis.SuccessCount
            Failures = $analysis.FailureCount
            ConditionalAccessDenials = $analysis.ConditionalAccessDenials
            RiskFlagged = $analysis.RiskyCount
            Findings = @($analysis.Findings).Count
            ExcludedNonInteractiveUserSignIns = $excludedNonInteractiveCount
            ExcludedManagedIdentitySignIns = $excludedManagedIdentityCount
            ExcludedServicePrincipalSignIns = $excludedServicePrincipalCount
        }
        Warnings = @($analysis.Warnings)
    }
    Write-ReportStatus -Message 'Saving report metadata and the latest-report shortcut...' -PercentComplete 93
    [System.IO.File]::WriteAllText((Join-Path $runDirectory 'metadata.json'), ($metadata | ConvertTo-Json -Depth 10), [System.Text.UTF8Encoding]::new($false))
    Copy-Item -LiteralPath $reportPath -Destination (Join-Path $outputRoot 'latest-report.html') -Force

    Write-Host "Report created: $reportPath" -ForegroundColor Green
    Write-Host "Raw logs kept in: $rawDirectory" -ForegroundColor Green
    if (-not $NoOpenReport -and $openReportFromConfig -and -not $NonInteractive) {
        Write-ReportStatus -Message 'Opening the completed HTML report in a new browser window...' -PercentComplete 98
        try {
            $openedBrowser = Open-ReportInNewBrowserWindow -Path $reportPath
            Write-Host "Opened the report using $openedBrowser." -ForegroundColor Green
        }
        catch {
            Write-Warning "The report was created, but the browser could not be launched automatically. Open it manually at '$reportPath'. $($_.Exception.Message)"
        }
    }
    else {
        Write-ReportStatus -Message 'Automatic browser launch was skipped by the current run options.' -PercentComplete 98
    }
    Write-ReportStatus -Message 'M365 sign-in report complete.' -PercentComplete 100
    Write-Progress -Id 17 -Activity 'M365 Sign-in Report' -Completed

    [pscustomobject]@{
        Version = $projectVersion
        ReportPath = $reportPath
        RawDataPath = $rawDirectory
        MetadataPath = Join-Path $runDirectory 'metadata.json'
        SignIns = $analysis.CurrentCount
        Failures = $analysis.FailureCount
        Findings = @($analysis.Findings).Count
    }
}
finally {
    Write-Progress -Id 17 -Activity 'M365 Sign-in Report' -Completed
    if ($connectedByScript) {
        try { Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null } catch { }
    }
}
