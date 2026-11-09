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

    [ValidateRange(1, 50)]
    [int]$DemoAgentCount = 10,

    [ValidateRange(0, 50)]
    [int]$AiIncidentCount,

    [string]$ResumeManifestPath,

    [switch]$UseDeviceCode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

if (-not $PSBoundParameters.ContainsKey('IncidentCount')) {
    $IncidentCount = Read-NumberWithDefault -Prompt 'How many incidents should be created?' -Default 50 -Minimum 1 -Maximum 50
}

if ($CreateDemoAiAgents -and $SkipDemoAiAgents) {
    throw 'CreateDemoAiAgents and SkipDemoAiAgents cannot be used together.'
}

$createAgents = [bool]$CreateDemoAiAgents
if (-not $CreateDemoAiAgents -and -not $SkipDemoAiAgents) {
    $agentAnswer = Read-Host 'Create dormant demo AI agents and registry cards? [Y/n]'
    $createAgents = [string]::IsNullOrWhiteSpace($agentAnswer) -or $agentAnswer -match '^(?i)y(?:es)?$'
}

if ($createAgents) {
    if (-not $PSBoundParameters.ContainsKey('DemoAgentCount')) {
        $DemoAgentCount = Read-NumberWithDefault -Prompt 'How many demo AI agents should be created?' -Default 10 -Minimum 1 -Maximum 50
    }
    $defaultAiIncidentCount = [math]::Min($DemoAgentCount, $IncidentCount)
    if (-not $PSBoundParameters.ContainsKey('AiIncidentCount')) {
        $AiIncidentCount = Read-NumberWithDefault -Prompt 'How many incidents should use AI-agent scenarios?' -Default $defaultAiIncidentCount -Minimum 0 -Maximum $IncidentCount
    }
}
else {
    $DemoAgentCount = 0
    $AiIncidentCount = 0
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
    -ResumeManifestPath $ResumeManifestPath `
    -Execute `
    -UseDeviceCode:$UseDeviceCode
