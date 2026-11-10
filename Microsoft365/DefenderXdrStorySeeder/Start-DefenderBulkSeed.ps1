#requires -Version 7.2

[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidatePattern('^[^@\s]+@[^@\s]+\.[^@\s]+$')]
    [string]$GlobalAdminUpn,

    [ValidateRange(1, 50)]
    [int]$IncidentCount = 50,

    [switch]$CreateDemoAiAgents,

    [switch]$SkipDemoAiAgents,

    [ValidateSet('evaluated', 'inventory', 'none')]
    [string]$AgentMode,

    [ValidateRange(1, 50)]
    [int]$DemoAgentCount = 10,

    [ValidateRange(0, 50)]
    [int]$AiIncidentCount,

    [string]$ResumeManifestPath,

    [string]$EvaluatedAgentManifestPath,

    [switch]$UseDeviceCode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Initialize-PackageScriptExecution {
    try {
        Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned -Force -ErrorAction Stop
    }
    catch {
        Write-Warning "Could not set the current PowerShell process to RemoteSigned: $($_.Exception.Message)"
    }

    Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -File |
        ForEach-Object { Unblock-File -LiteralPath $_.FullName -ErrorAction Stop }
}

Initialize-PackageScriptExecution

function Read-NumberWithDefault {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][int]$Default,
        [Parameter(Mandatory)][int]$Minimum,
        [Parameter(Mandatory)][int]$Maximum
    )

    while ($true) {
        $answer = Read-Host "$Prompt [$Default]"
        if ([string]::IsNullOrWhiteSpace($answer)) {
            return $Default
        }
        $parsed = 0
        if ([int]::TryParse($answer, [ref]$parsed) -and $parsed -ge $Minimum -and $parsed -le $Maximum) {
            return $parsed
        }
        Write-Warning "Enter a whole number from $Minimum through $Maximum."
    }
}

$resumeSeedManifest = $null
if (-not [string]::IsNullOrWhiteSpace($ResumeManifestPath)) {
    $resolvedResumePath = (Resolve-Path -LiteralPath $ResumeManifestPath).Path
    $resumeSeedManifest = Get-Content -LiteralPath $resolvedResumePath -Raw |
        ConvertFrom-Json -AsHashtable -Depth 50

    if (-not $PSBoundParameters.ContainsKey('IncidentCount') -and
        $resumeSeedManifest.ContainsKey('requestedCount')) {
        $IncidentCount = [int]$resumeSeedManifest.requestedCount
    }
    if (-not $PSBoundParameters.ContainsKey('DemoAgentCount') -and
        $resumeSeedManifest.ContainsKey('requestedDemoAgentCount')) {
        $DemoAgentCount = [int]$resumeSeedManifest.requestedDemoAgentCount
    }
    if (-not $PSBoundParameters.ContainsKey('AiIncidentCount') -and
        $resumeSeedManifest.ContainsKey('requestedAiIncidentCount')) {
        $AiIncidentCount = [int]$resumeSeedManifest.requestedAiIncidentCount
    }
    if ([string]::IsNullOrWhiteSpace($EvaluatedAgentManifestPath) -and
        $resumeSeedManifest.ContainsKey('evaluatedAgentManifestPath')) {
        $EvaluatedAgentManifestPath = [string]$resumeSeedManifest.evaluatedAgentManifestPath
    }
}

if (-not $PSBoundParameters.ContainsKey('IncidentCount')) {
    if ($null -eq $resumeSeedManifest) {
        $IncidentCount = Read-NumberWithDefault -Prompt 'How many incidents should be created?' -Default 50 -Minimum 1 -Maximum 50
    }
}

if ($CreateDemoAiAgents -and $SkipDemoAiAgents) {
    throw 'CreateDemoAiAgents and SkipDemoAiAgents cannot be used together.'
}

if ($PSBoundParameters.ContainsKey('AgentMode') -and ($CreateDemoAiAgents -or $SkipDemoAiAgents)) {
    throw 'AgentMode cannot be combined with CreateDemoAiAgents or SkipDemoAiAgents.'
}

if (-not $PSBoundParameters.ContainsKey('AgentMode')) {
    if ($CreateDemoAiAgents) {
        # Preserve the established meaning of the legacy switch for automation.
        $AgentMode = 'inventory'
    }
    elseif ($SkipDemoAiAgents) {
        $AgentMode = 'none'
    }
    elseif ($null -ne $resumeSeedManifest -and $resumeSeedManifest.ContainsKey('agentMode')) {
        $AgentMode = [string]$resumeSeedManifest.agentMode
    }
    elseif ($null -ne $resumeSeedManifest -and
        $resumeSeedManifest.ContainsKey('requestedDemoAgentCount') -and
        [int]$resumeSeedManifest.requestedDemoAgentCount -gt 0) {
        # Schema-2 and early schema-3 manifests predate the explicit agentMode field.
        $AgentMode = 'inventory'
    }
    elseif ($null -ne $resumeSeedManifest) {
        $AgentMode = 'none'
    }
    else {
        $agentAnswer = Read-Host 'Agent mode: [E]valuated, [I]nventory-only, or [N]one? [E]'
        if ([string]::IsNullOrWhiteSpace($agentAnswer) -or $agentAnswer -match '^(?i)e(?:valuated)?$') {
            $AgentMode = 'evaluated'
        }
        elseif ($agentAnswer -match '^(?i)i(?:nventory(?:-only)?)?$') {
            $AgentMode = 'inventory'
        }
        elseif ($agentAnswer -match '^(?i)n(?:one|o)?$') {
            $AgentMode = 'none'
        }
        else {
            throw "Unknown agent mode '$agentAnswer'. Enter E, I, or N."
        }
    }
}

$createAgents = $AgentMode -ne 'none'

if ($createAgents) {
    if (-not $PSBoundParameters.ContainsKey('DemoAgentCount')) {
        if ($null -eq $resumeSeedManifest) {
            $DemoAgentCount = Read-NumberWithDefault -Prompt 'How many demo AI agents should be created?' -Default 10 -Minimum 1 -Maximum 50
        }
    }
    $defaultAiIncidentCount = [math]::Min($DemoAgentCount, $IncidentCount)
    if (-not $PSBoundParameters.ContainsKey('AiIncidentCount')) {
        if ($null -eq $resumeSeedManifest) {
            $AiIncidentCount = Read-NumberWithDefault -Prompt 'How many incidents should use AI-agent scenarios?' -Default $defaultAiIncidentCount -Minimum 0 -Maximum $IncidentCount
        }
    }
}
else {
    $DemoAgentCount = 0
    $AiIncidentCount = 0
}

if ($AgentMode -eq 'evaluated' -and [string]::IsNullOrWhiteSpace($EvaluatedAgentManifestPath)) {
    $mcpAnswer = Read-Host 'Configure supported Agent 365 MCP tooling for medium/high profiles? [Y/n]'
    $skipMcp = -not ([string]::IsNullOrWhiteSpace($mcpAnswer) -or $mcpAnswer -match '^(?i)y(?:es)?$')
    $evaluatedPath = Join-Path $PSScriptRoot 'Invoke-DefenderEvaluatedAgentLab.ps1'
    $evaluatedResult = & $evaluatedPath `
        -GlobalAdminUpn $GlobalAdminUpn `
        -AgentCount $DemoAgentCount `
        -SkipMcp:$skipMcp `
        -InstallAgent365Cli `
        -Execute
    if ($null -eq $evaluatedResult -or [string]::IsNullOrWhiteSpace([string]$evaluatedResult.ManifestPath)) {
        throw 'Evaluated Agent 365 provisioning did not return a run manifest. Bulk incident seeding was not started.'
    }
    $EvaluatedAgentManifestPath = [string]$evaluatedResult.ManifestPath
    $DemoAgentCount = [int]$evaluatedResult.AgentCount
    if ($DemoAgentCount -lt 1) {
        throw "No evaluated agents completed provisioning. Review '$EvaluatedAgentManifestPath' and run its dedicated cleanup before retrying."
    }
}

if ($AiIncidentCount -gt $IncidentCount) {
    throw 'AiIncidentCount cannot exceed IncidentCount.'
}

$seederPath = Join-Path $PSScriptRoot 'Invoke-DefenderBulkSeeder.ps1'
& $seederPath `
    -GlobalAdminUpn $GlobalAdminUpn `
    -IncidentCount $IncidentCount `
    -CreateDemoAiAgents:$createAgents `
    -DemoAgentCount $DemoAgentCount `
    -AiIncidentCount $AiIncidentCount `
    -EvaluatedAgentManifestPath $EvaluatedAgentManifestPath `
    -ResumeManifestPath $ResumeManifestPath `
    -Execute `
    -UseDeviceCode:$UseDeviceCode
