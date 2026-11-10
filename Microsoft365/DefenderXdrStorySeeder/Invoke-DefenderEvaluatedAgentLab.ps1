#requires -Version 7.2

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidatePattern('^[^@\s]+@[^@\s]+\.[^@\s]+$')]
    [string]$GlobalAdminUpn,

    [ValidateRange(1, 30)]
    [int]$AgentCount = 9,

    [ValidateSet('low', 'medium', 'high')]
    [string[]]$RiskProfile = @('low', 'medium', 'high'),

    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string]$TenantId,

    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'artifacts'),

    [string]$LocalStateRoot,

    [switch]$SkipMcp,

    [switch]$InstallAgent365Cli,

    [switch]$Execute
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProjectVersion = '0.3.1-beta'
$NamePrefix = '[MXDR Demo]'
$GraphResourceAppId = '00000003-0000-0000-c000-000000000000'

function Save-EvaluatedAgentManifest {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Manifest,
        [Parameter(Mandatory)][string]$Path
    )

    $Manifest.lastUpdatedAtUtc = [DateTime]::UtcNow.ToString('o')
    $Manifest | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $Path -Encoding utf8
}

function Resolve-TenantIdFromUpn {
    param([Parameter(Mandatory)][string]$Upn)

    $domain = $Upn.Split('@')[-1]
    $metadataUri = "https://login.microsoftonline.com/$domain/v2.0/.well-known/openid-configuration"
    $metadata = Invoke-RestMethod -Method Get -Uri $metadataUri -ErrorAction Stop
    $issuer = [string]$metadata.issuer
    if ($issuer -notmatch '/(?<tenant>[0-9a-fA-F-]{36})/v2\.0$') {
        throw "Microsoft identity metadata did not return a tenant ID for '$domain'. Supply -TenantId explicitly."
    }
    return [string]$Matches.tenant
}

function Get-SupportedDotNetCommand {
    $candidates = [System.Collections.Generic.List[string]]::new()
    $command = Get-Command dotnet -ErrorAction SilentlyContinue
    if ($null -ne $command -and -not [string]::IsNullOrWhiteSpace([string]$command.Source)) {
        $candidates.Add([string]$command.Source)
    }
    foreach ($candidate in @(
        (Join-Path $env:ProgramFiles 'dotnet\dotnet.exe')
        $(if (-not [string]::IsNullOrWhiteSpace(${env:ProgramFiles(x86)})) { Join-Path ${env:ProgramFiles(x86)} 'dotnet\dotnet.exe' })
    )) {
        if (-not [string]::IsNullOrWhiteSpace([string]$candidate) -and
            -not $candidates.Contains([string]$candidate)) {
            $candidates.Add([string]$candidate)
        }
    }

    foreach ($candidate in $candidates) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            continue
        }
        $sdkVersions = @(& $candidate --list-sdks 2>$null)
        $hasSupportedSdk = @($sdkVersions | Where-Object {
            $_ -match '^(?<major>\d+)\.' -and [int]$Matches.major -ge 8
        }).Count -gt 0
        if ($hasSupportedSdk) {
            return $candidate
        }
    }
    return $null
}

function Install-DotNet8Sdk {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($null -eq $winget) {
        throw "The .NET 8 SDK is required and Windows Package Manager was not found. Install it manually with 'winget install --id Microsoft.DotNet.SDK.8 --exact --source winget'."
    }

    Write-Host 'Installing the Microsoft .NET 8 SDK. Approve the Windows elevation prompt if it appears...' -ForegroundColor Cyan
    $wingetArguments = @(
        'install'
        '--id', 'Microsoft.DotNet.SDK.8'
        '--exact'
        '--source', 'winget'
        '--accept-package-agreements'
        '--accept-source-agreements'
        '--silent'
    )
    try {
        $process = Start-Process `
            -FilePath ([string]$winget.Source) `
            -ArgumentList $wingetArguments `
            -Verb RunAs `
            -WindowStyle Hidden `
            -Wait `
            -PassThru
    }
    catch {
        throw "The .NET 8 SDK installation could not be started. Approve the Windows elevation prompt and retry. $($_.Exception.Message)"
    }

    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = @($machinePath, $userPath, $env:Path) -join [IO.Path]::PathSeparator
    $dotnetPath = Get-SupportedDotNetCommand
    if ($null -ne $dotnetPath) {
        Write-Host 'Microsoft .NET 8 SDK installation completed.' -ForegroundColor Green
        return $dotnetPath
    }

    if ($process.ExitCode -eq 3010) {
        throw 'The .NET 8 SDK installation completed and Windows requested a restart. Restart Windows, then rerun the bulk seeder.'
    }
    throw "The .NET 8 SDK installation did not produce a usable SDK. WinGet exited with code $($process.ExitCode)."
}

function Get-Agent365CliCommand {
    param([switch]$AllowInstall)

    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = @($machinePath, $userPath, $env:Path) -join [IO.Path]::PathSeparator

    $command = Get-Command a365 -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return [string]$command.Source
    }

    $candidate = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.dotnet\tools\a365.exe'
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        return [string]$candidate
    }

    if (-not $AllowInstall) {
        throw "The Microsoft Agent 365 CLI is required. Install it with 'dotnet tool install --global Microsoft.Agents.A365.DevTools.Cli' or rerun with -InstallAgent365Cli."
    }

    $dotnetPath = Get-SupportedDotNetCommand
    if ($null -eq $dotnetPath) {
        if (-not $AllowInstall) {
            throw "The Microsoft Agent 365 CLI requires the .NET 8 SDK or later. Install it with 'winget install --id Microsoft.DotNet.SDK.8 --exact --source winget' or rerun with -InstallAgent365Cli."
        }
        $dotnetPath = Install-DotNet8Sdk
    }

    $toolPackageId = 'Microsoft.Agents.A365.DevTools.Cli'
    $globalTools = @(& $dotnetPath tool list --global 2>&1)
    $toolVerb = if (@($globalTools | Where-Object { [string]$_ -match '^microsoft\.agents\.a365\.devtools\.cli\s' }).Count -gt 0) {
        'update'
    }
    else {
        'install'
    }
    $toolAction = if ($toolVerb -eq 'update') { 'Updating' } else { 'Installing' }
    Write-Host "$toolAction the Microsoft Agent 365 CLI for the current user..." -ForegroundColor Cyan
    $installOutput = @(& $dotnetPath tool $toolVerb --global $toolPackageId 2>&1)
    $installExitCode = $LASTEXITCODE
    $installOutput | ForEach-Object { Write-Host ([string]$_) }
    if ($installExitCode -ne 0) {
        throw "Agent 365 CLI installation failed with exit code $installExitCode."
    }

    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = @($machinePath, $userPath, $env:Path) -join [IO.Path]::PathSeparator
    $command = Get-Command a365 -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return [string]$candidate
        }
        throw 'Agent 365 CLI was installed but a365 could not be located. Open a new PowerShell window and retry.'
    }
    return [string]$command.Source
}

function Invoke-Agent365Cli {
    param(
        [Parameter(Mandatory)][string]$CliPath,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][string]$LogPath,
        [switch]$AllowFailure
    )

    Push-Location $WorkingDirectory
    try {
        $rendered = @($Arguments | ForEach-Object {
            if ($_ -match '\s') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
        }) -join ' '
        "[$([DateTime]::UtcNow.ToString('o'))] a365 $rendered" | Add-Content -LiteralPath $LogPath -Encoding utf8
        & $CliPath @Arguments 2>&1 | ForEach-Object {
            $line = [string]$_
            $line | Add-Content -LiteralPath $LogPath -Encoding utf8
            Write-Host $line
        }
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0 -and -not $AllowFailure) {
            throw "Agent 365 CLI failed with exit code $exitCode. Review '$LogPath'."
        }
        return [ordered]@{
            exitCode = $exitCode
            succeeded = ($exitCode -eq 0)
            logPath = $LogPath
        }
    }
    finally {
        Pop-Location
    }
}

function Get-SafeGeneratedIds {
    param([Parameter(Mandatory)][string]$Path)

    $result = [ordered]@{}
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $result
    }

    $config = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable -Depth 50
    $canonicalKeys = @{
        tenantId                    = 'tenantId'
        agentBlueprintId            = 'agentBlueprintId'
        agentIdentityBlueprintId    = 'agentBlueprintId'
        agentBlueprintAppId         = 'agentBlueprintAppId'
        agentIdentityId             = 'agentIdentityId'
        agentIdentityAppId          = 'agentIdentityAppId'
        agentRegistrationId         = 'agentRegistrationId'
        servicePrincipalId          = 'servicePrincipalId'
    }

    function Add-SafeIdsFromValue {
        param(
            [AllowNull()]$Value,
            [Parameter(Mandatory)][System.Collections.IDictionary]$Destination
        )

        if ($Value -is [System.Collections.IDictionary]) {
            foreach ($key in @($Value.Keys)) {
                $keyName = [string]$key
                if ($canonicalKeys.ContainsKey($keyName) -and
                    -not [string]::IsNullOrWhiteSpace([string]$Value[$key])) {
                    $Destination[[string]$canonicalKeys[$keyName]] = [string]$Value[$key]
                }
                Add-SafeIdsFromValue -Value $Value[$key] -Destination $Destination
            }
            return
        }

        if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
            foreach ($item in $Value) {
                Add-SafeIdsFromValue -Value $item -Destination $Destination
            }
        }
    }

    Add-SafeIdsFromValue -Value $config -Destination $result
    return $result
}

$catalogPath = Join-Path $PSScriptRoot 'catalog\agent-risk-profiles.json'
$catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json -AsHashtable -Depth 30
$profileById = @{}
foreach ($profile in @($catalog.profiles)) {
    $profileById[[string]$profile.id] = $profile
}
foreach ($requestedProfile in $RiskProfile) {
    if (-not $profileById.ContainsKey($requestedProfile)) {
        throw "Unknown risk profile '$requestedProfile'."
    }
}

$plan = @(
    foreach ($index in 1..$AgentCount) {
        $profileId = [string]$RiskProfile[(($index - 1) % $RiskProfile.Count)]
        $profile = $profileById[$profileId]
        [pscustomobject]@{
            Sequence = $index
            Name = "$NamePrefix $([string]$profile.displayLabel) $($index.ToString('00'))"
            TargetRisk = $profileId
            AuthMode = [string]$profile.authMode
            McpServers = if ($SkipMcp) { @() } else { @($profile.mcpServers) }
            DelegatedScopes = @($profile.graphDelegatedScopes)
        }
    }
)

if (-not $Execute) {
    return [pscustomobject]@{
        Mode = 'DryRun'
        Version = $ProjectVersion
        AgentCount = $AgentCount
        Plan = $plan
        CleanupSupported = $true
        RiskRatingGuaranteed = $false
    }
}

if (-not $PSCmdlet.ShouldProcess(
    "Microsoft Agent 365 tenant selected by $GlobalAdminUpn",
    "Create $AgentCount supported Agent 365 demo agent configuration(s), including consented profile permissions and optional MCP tooling; record every resource for dedicated cleanup"
)) {
    return
}

if ([string]::IsNullOrWhiteSpace($TenantId)) {
    $TenantId = Resolve-TenantIdFromUpn -Upn $GlobalAdminUpn
}

$cliPath = Get-Agent365CliCommand -AllowInstall:$InstallAgent365Cli
if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}
$resolvedOutput = (Resolve-Path -LiteralPath $OutputDirectory).Path

if ([string]::IsNullOrWhiteSpace($LocalStateRoot)) {
    $localBase = [Environment]::GetFolderPath('LocalApplicationData')
    if ([string]::IsNullOrWhiteSpace($localBase)) {
        throw 'LOCALAPPDATA could not be resolved. Supply -LocalStateRoot explicitly.'
    }
    $LocalStateRoot = Join-Path $localBase 'MXDRDemoAgentLab'
}

$runId = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
$runStatePath = Join-Path $LocalStateRoot $runId
New-Item -ItemType Directory -Path $runStatePath -Force | Out-Null
$runStatePath = (Resolve-Path -LiteralPath $runStatePath).Path
$manifestPath = Join-Path $resolvedOutput "evaluated-agent-lab-run-$runId.json"

$manifest = [ordered]@{
    schemaVersion = 1
    projectVersion = $ProjectVersion
    runId = $runId
    globalAdminUpn = $GlobalAdminUpn
    tenantId = $TenantId
    namePrefix = $NamePrefix
    requestedAgentCount = $AgentCount
    riskProfiles = @($RiskProfile)
    skipMcp = [bool]$SkipMcp
    riskRatingGuaranteed = $false
    localStateRoot = $runStatePath
    createdAtUtc = [DateTime]::UtcNow.ToString('o')
    lastUpdatedAtUtc = [DateTime]::UtcNow.ToString('o')
    completedAtUtc = $null
    succeeded = $false
    cleanupSucceeded = $false
    cleanupCompletedAtUtc = $null
    cleanupManifestPath = $null
    prerequisiteStatus = 'pending'
    prerequisiteLogPath = (Join-Path $runStatePath 'a365-requirements.log')
    agents = @()
    error = $null
}
Save-EvaluatedAgentManifest -Manifest $manifest -Path $manifestPath

try {
    Write-Host 'Validating Agent 365, Azure subscription, role, and tenant prerequisites before creating agents...' -ForegroundColor Cyan
    $prerequisiteResult = Invoke-Agent365Cli `
        -CliPath $cliPath `
        -Arguments @('setup', 'requirements') `
        -WorkingDirectory $runStatePath `
        -LogPath $manifest.prerequisiteLogPath `
        -AllowFailure
    $manifest.prerequisiteStatus = if ($prerequisiteResult.succeeded) { 'passed' } else { 'failed' }
    if (-not $prerequisiteResult.succeeded) {
        $manifest.error = "Agent 365 prerequisite validation failed with exit code $($prerequisiteResult.exitCode). No agent provisioning was started."
        Save-EvaluatedAgentManifest -Manifest $manifest -Path $manifestPath
        throw "$($manifest.error) Review '$($manifest.prerequisiteLogPath)', correct the reported requirement, and rerun the bulk seeder."
    }
    Save-EvaluatedAgentManifest -Manifest $manifest -Path $manifestPath

    foreach ($planItem in $plan) {
        $profile = $profileById[[string]$planItem.TargetRisk]
        $safeFolderName = "agent-$($planItem.Sequence.ToString('00'))-$($planItem.TargetRisk)"
        $agentPath = Join-Path $runStatePath $safeFolderName
        New-Item -ItemType Directory -Path $agentPath -Force | Out-Null
        $logPath = Join-Path $agentPath 'a365-provision.log'
        $generatedConfigPath = Join-Path $agentPath 'a365.generated.config.json'

        $agentRecord = [ordered]@{
            sequence = [int]$planItem.Sequence
            displayName = [string]$planItem.Name
            agentBaseName = [string]$planItem.Name
            targetRisk = [string]$planItem.TargetRisk
            targetRiskIsAdvisory = $true
            authMode = [string]$planItem.AuthMode
            description = [string]$profile.description
            instructionsPath = (Join-Path $agentPath 'instructions.md')
            delegatedScopes = @($planItem.DelegatedScopes)
            mcpServers = @($planItem.McpServers)
            expectedSignals = @($profile.expectedSignals)
            instructionsStatus = 'generatedForRuntimeProfile'
            runtimeStatus = 'notDeployedBySeeder'
            observabilityStatus = 'notEmittingUntilRuntimeIntegrated'
            evaluationExpectation = 'configurationSignalsOnly'
            localStatePath = $agentPath
            generatedConfigPath = $generatedConfigPath
            safeGeneratedIds = [ordered]@{}
            status = 'preparing'
            mcpStatus = if (@($planItem.McpServers).Count -gt 0) { 'pending' } else { 'notRequested' }
            setupStatus = 'pending'
            permissionStatus = 'pending'
            cleanupCommand = 'a365 cleanup instance --yes; a365 cleanup blueprint --yes'
            errors = @()
        }
        $manifest.agents = @($manifest.agents) + $agentRecord
        Save-EvaluatedAgentManifest -Manifest $manifest -Path $manifestPath

        [string]$profile.instructions | Set-Content -LiteralPath $agentRecord.instructionsPath -Encoding utf8
        $profile | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $agentPath 'agent-profile.json') -Encoding utf8
        [ordered]@{
            tenantId = $TenantId
            environment = 'prod'
            agentIdentityDisplayName = "$($planItem.Name) Agent"
            agentBlueprintDisplayName = "$($planItem.Name) Blueprint"
            deploymentProjectPath = '.'
            agentDescription = [string]$profile.description
            authMode = [string]$planItem.AuthMode
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $agentPath 'a365.config.json') -Encoding utf8

        if (@($planItem.McpServers).Count -gt 0) {
            $mcpArguments = @('develop', 'add-mcp-servers') + @($planItem.McpServers) + @('--project-path', $agentPath)
            $mcpResult = Invoke-Agent365Cli -CliPath $cliPath -Arguments $mcpArguments -WorkingDirectory $agentPath -LogPath $logPath -AllowFailure
            $agentRecord.mcpStatus = if ($mcpResult.succeeded) { 'configured' } else { 'failed' }
            if (-not $mcpResult.succeeded) {
                $agentRecord.errors = @($agentRecord.errors) + "MCP manifest configuration failed with exit code $($mcpResult.exitCode)."
            }
            Save-EvaluatedAgentManifest -Manifest $manifest -Path $manifestPath
        }

        $setupResult = Invoke-Agent365Cli `
            -CliPath $cliPath `
            -Arguments @('setup', 'all', '--skip-requirements', '--authmode', [string]$planItem.AuthMode) `
            -WorkingDirectory $agentPath `
            -LogPath $logPath `
            -AllowFailure
        $agentRecord.setupStatus = if ($setupResult.succeeded) { 'created' } else { 'partialOrFailed' }
        $agentRecord.safeGeneratedIds = Get-SafeGeneratedIds -Path $generatedConfigPath
        if (-not $setupResult.succeeded) {
            $agentRecord.errors = @($agentRecord.errors) + "Agent 365 setup failed with exit code $($setupResult.exitCode). Cleanup remains available for partial resources."
            $agentRecord.status = 'partial'
            Save-EvaluatedAgentManifest -Manifest $manifest -Path $manifestPath
            continue
        }

        if (@($planItem.DelegatedScopes).Count -gt 0) {
            $scopeCsv = @($planItem.DelegatedScopes) -join ','
            $permissionResult = Invoke-Agent365Cli `
                -CliPath $cliPath `
                -Arguments @('setup', 'permissions', 'custom', '--resource-app-id', $GraphResourceAppId, '--scopes', $scopeCsv) `
                -WorkingDirectory $agentPath `
                -LogPath $logPath `
                -AllowFailure
            $agentRecord.permissionStatus = if ($permissionResult.succeeded) { 'granted' } else { 'partialOrFailed' }
            if (-not $permissionResult.succeeded) {
                $agentRecord.errors = @($agentRecord.errors) + "Custom permission configuration failed with exit code $($permissionResult.exitCode)."
            }
        }
        else {
            $agentRecord.permissionStatus = 'notRequested'
        }

        if ($agentRecord.mcpStatus -eq 'configured') {
            $mcpPermissionResult = Invoke-Agent365Cli `
                -CliPath $cliPath `
                -Arguments @('setup', 'permissions', 'mcp') `
                -WorkingDirectory $agentPath `
                -LogPath $logPath `
                -AllowFailure
            if (-not $mcpPermissionResult.succeeded) {
                $agentRecord.mcpStatus = 'manifestOnly'
                $agentRecord.errors = @($agentRecord.errors) + "MCP blueprint consent failed with exit code $($mcpPermissionResult.exitCode)."
            }
            else {
                $agentRecord.mcpStatus = 'configuredAndConsented'
            }
        }

        $agentRecord.safeGeneratedIds = Get-SafeGeneratedIds -Path $generatedConfigPath
        $agentRecord.status = if (@($agentRecord.errors).Count -eq 0) { 'created' } else { 'createdWithWarnings' }
        Save-EvaluatedAgentManifest -Manifest $manifest -Path $manifestPath
    }
    $manifest.succeeded = (@($manifest.agents | Where-Object { $_.status -in @('created', 'createdWithWarnings') }).Count -gt 0)
}
catch {
    $manifest.error = $_.Exception.Message
    throw
}
finally {
    $manifest.completedAtUtc = [DateTime]::UtcNow.ToString('o')
    Save-EvaluatedAgentManifest -Manifest $manifest -Path $manifestPath
}

Write-Host "Provisioned $(@($manifest.agents | Where-Object { $_.status -in @('created', 'createdWithWarnings') }).Count) evaluated Agent 365 configuration(s)." -ForegroundColor Green
Write-Host "Run manifest: $manifestPath"
Write-Host "Sensitive current-user CLI state: $runStatePath" -ForegroundColor Yellow
Write-Host 'Defender calculates the final risk level asynchronously; the requested profile is a target, not an assigned rating.' -ForegroundColor Yellow

[pscustomobject]@{
    Mode = 'Executed'
    Version = $ProjectVersion
    AgentCount = @($manifest.agents | Where-Object { $_.status -in @('created', 'createdWithWarnings') }).Count
    ManifestPath = $manifestPath
    LocalStatePath = $runStatePath
    CleanupLauncher = (Join-Path $PSScriptRoot 'Start-DefenderEvaluatedAgentCleanup.ps1')
}
