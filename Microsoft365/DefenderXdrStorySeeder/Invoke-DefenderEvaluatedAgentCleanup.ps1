#requires -Version 7.2

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidatePattern('^[^@\s]+@[^@\s]+\.[^@\s]+$')]
    [string]$GlobalAdminUpn,

    [Parameter(Mandatory, Position = 1)]
    [string]$ManifestPath,

    [string]$OutputDirectory,

    [switch]$RemoveLocalState,

    [switch]$Execute
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProjectVersion = '0.3.1-beta'

function Invoke-CleanupCli {
    param(
        [Parameter(Mandatory)][string]$CliPath,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][string]$LogPath
    )

    Push-Location $WorkingDirectory
    try {
        $output = @(& $CliPath @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
        $output | ForEach-Object {
            [string]$_ | Tee-Object -FilePath $LogPath -Append | Write-Host
        }
        return [ordered]@{ exitCode = $exitCode; succeeded = ($exitCode -eq 0) }
    }
    finally {
        Pop-Location
    }
}

$resolvedManifestPath = (Resolve-Path -LiteralPath $ManifestPath -ErrorAction Stop).Path
$manifest = Get-Content -LiteralPath $resolvedManifestPath -Raw | ConvertFrom-Json -AsHashtable -Depth 50
if ([int]$manifest.schemaVersion -ne 1 -or -not $manifest.ContainsKey('agents')) {
    throw 'The selected file is not a supported evaluated-agent lab manifest.'
}
if ([string]$manifest.globalAdminUpn -ine $GlobalAdminUpn) {
    throw "The manifest was created for '$([string]$manifest.globalAdminUpn)', not '$GlobalAdminUpn'."
}

$agents = @($manifest.agents)
if ($manifest.ContainsKey('cleanupSucceeded') -and [bool]$manifest.cleanupSucceeded) {
    Write-Host 'The evaluated-agent manifest is already marked as successfully cleaned.' -ForegroundColor Green
    return [pscustomobject]@{
        Mode = 'AlreadyCleaned'
        Version = $ProjectVersion
        AgentCount = $agents.Count
        CleanupManifestPath = if ($manifest.ContainsKey('cleanupManifestPath')) { [string]$manifest.cleanupManifestPath } else { $null }
        DefenderAlertsChanged = $false
        DefenderIncidentsChanged = $false
    }
}
$plan = @($agents | ForEach-Object {
    [pscustomobject]@{
        DisplayName = [string]$_.displayName
        TargetRisk = [string]$_.targetRisk
        LocalStatePath = [string]$_.localStatePath
    }
})
if (-not $Execute) {
    return [pscustomobject]@{
        Mode = 'DryRun'
        Version = $ProjectVersion
        AgentCount = $agents.Count
        Plan = $plan
        DefenderAlertsChanged = $false
        DefenderIncidentsChanged = $false
    }
}

if (-not $PSCmdlet.ShouldProcess(
    "Microsoft Agent 365 tenant selected by $GlobalAdminUpn",
    "Remove only the $($agents.Count) Agent 365 evaluated demo configuration(s) recorded in '$resolvedManifestPath'; do not change Defender alerts or incidents"
)) {
    return
}

$cliCommand = Get-Command a365 -ErrorAction SilentlyContinue
if ($null -eq $cliCommand) {
    $candidate = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.dotnet\tools\a365.exe'
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        throw "The Agent 365 CLI is required for cleanup. Install it with 'dotnet tool install --global Microsoft.Agents.A365.DevTools.Cli'."
    }
    $cliPath = $candidate
}
else {
    $cliPath = $cliCommand.Source
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Split-Path $resolvedManifestPath -Parent
}
if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}
$cleanupId = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
$cleanupPath = Join-Path (Resolve-Path -LiteralPath $OutputDirectory).Path "evaluated-agent-cleanup-run-$cleanupId.json"
$cleanupManifest = [ordered]@{
    schemaVersion = 1
    projectVersion = $ProjectVersion
    sourceManifestPath = $resolvedManifestPath
    tenantId = [string]$manifest.tenantId
    globalAdminUpn = $GlobalAdminUpn
    startedAtUtc = [DateTime]::UtcNow.ToString('o')
    completedAtUtc = $null
    removeLocalState = [bool]$RemoveLocalState
    agents = @()
    succeeded = $false
}

foreach ($agent in @($agents | Sort-Object { [int]$_.sequence } -Descending)) {
    $agentPath = [string]$agent.localStatePath
    $record = [ordered]@{
        displayName = [string]$agent.displayName
        localStatePath = $agentPath
        instanceCleanup = 'notAttempted'
        blueprintCleanup = 'notAttempted'
        localStateCleanup = 'notAttempted'
        errors = @()
    }
    $cleanupManifest.agents = @($cleanupManifest.agents) + $record
    $cleanupManifest | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $cleanupPath -Encoding utf8

    $workingDirectory = if (Test-Path -LiteralPath $agentPath -PathType Container) {
        $agentPath
    }
    else {
        Split-Path $resolvedManifestPath -Parent
    }
    $logPath = Join-Path (Split-Path $cleanupPath -Parent) "evaluated-agent-cleanup-$cleanupId-$([int]$agent.sequence).log"
    $useLocalConfig = Test-Path -LiteralPath (Join-Path $workingDirectory 'a365.generated.config.json') -PathType Leaf
    $baseArguments = if ($useLocalConfig) {
        @()
    }
    else {
        $agentBaseName = if ($agent.ContainsKey('agentBaseName')) { [string]$agent.agentBaseName } else { [string]$agent.displayName }
        @('--agent-name', $agentBaseName, '--tenant-id', [string]$manifest.tenantId)
    }

    $instanceResult = Invoke-CleanupCli `
        -CliPath $cliPath `
        -Arguments (@('cleanup', 'instance') + $baseArguments + @('--yes')) `
        -WorkingDirectory $workingDirectory `
        -LogPath $logPath
    $record.instanceCleanup = if ($instanceResult.succeeded) { 'removedOrAbsent' } else { 'failed' }
    if (-not $instanceResult.succeeded) {
        $record.errors = @($record.errors) + "Instance cleanup failed with exit code $($instanceResult.exitCode)."
    }

    $blueprintResult = Invoke-CleanupCli `
        -CliPath $cliPath `
        -Arguments (@('cleanup', 'blueprint') + $baseArguments + @('--yes')) `
        -WorkingDirectory $workingDirectory `
        -LogPath $logPath
    $record.blueprintCleanup = if ($blueprintResult.succeeded) { 'removedOrAbsent' } else { 'failed' }
    if (-not $blueprintResult.succeeded) {
        $record.errors = @($record.errors) + "Blueprint cleanup failed with exit code $($blueprintResult.exitCode)."
    }

    if ($RemoveLocalState -and $instanceResult.succeeded -and $blueprintResult.succeeded -and (Test-Path -LiteralPath $agentPath -PathType Container)) {
        $resolvedAgentPath = [System.IO.Path]::GetFullPath($agentPath)
        $resolvedRunRoot = [System.IO.Path]::GetFullPath([string]$manifest.localStateRoot)
        if ($resolvedAgentPath.StartsWith($resolvedRunRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedAgentPath -Recurse -Force
            $record.localStateCleanup = 'removed'
        }
        else {
            $record.localStateCleanup = 'refusedOutsideRecordedRunRoot'
            $record.errors = @($record.errors) + 'Local state path was outside the recorded run root and was not deleted.'
        }
    }
    elseif ($RemoveLocalState) {
        $record.localStateCleanup = 'retainedBecauseTenantCleanupFailed'
    }
    else {
        $record.localStateCleanup = 'retainedByRequest'
    }

    $cleanupManifest | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $cleanupPath -Encoding utf8
}

if ($RemoveLocalState -and (Test-Path -LiteralPath ([string]$manifest.localStateRoot) -PathType Container)) {
    $remainingItems = @(Get-ChildItem -LiteralPath ([string]$manifest.localStateRoot) -Force)
    if ($remainingItems.Count -eq 0) {
        Remove-Item -LiteralPath ([string]$manifest.localStateRoot) -Force
    }
}

$cleanupManifest.succeeded = (@($cleanupManifest.agents | Where-Object { @($_.errors).Count -gt 0 }).Count -eq 0)
$cleanupManifest.completedAtUtc = [DateTime]::UtcNow.ToString('o')
$cleanupManifest | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $cleanupPath -Encoding utf8

if (-not $cleanupManifest.succeeded) {
    throw "One or more evaluated agents could not be fully cleaned. Review '$cleanupPath'."
}

$manifest['cleanupSucceeded'] = $true
$manifest['cleanupCompletedAtUtc'] = $cleanupManifest.completedAtUtc
$manifest['cleanupManifestPath'] = $cleanupPath
$manifest | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $resolvedManifestPath -Encoding utf8

Write-Host "Cleaned $($agents.Count) evaluated Agent 365 configuration(s)." -ForegroundColor Green
Write-Host 'Defender alerts and incidents were not changed.' -ForegroundColor Green
Write-Host "Cleanup manifest: $cleanupPath"

[pscustomobject]@{
    Mode = 'Executed'
    Version = $ProjectVersion
    AgentCount = $agents.Count
    CleanupManifestPath = $cleanupPath
    DefenderAlertsChanged = $false
    DefenderIncidentsChanged = $false
}
