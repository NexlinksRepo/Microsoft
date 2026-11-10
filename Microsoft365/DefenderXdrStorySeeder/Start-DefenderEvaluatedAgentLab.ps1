#requires -Version 7.2

[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidatePattern('^[^@\s]+@[^@\s]+\.[^@\s]+$')]
    [string]$GlobalAdminUpn,

    [ValidateRange(1, 30)]
    [int]$AgentCount = 9,

    [ValidateSet('low', 'medium', 'high')]
    [string[]]$RiskProfile = @('low', 'medium', 'high'),

    [string]$TenantId,

    [switch]$SkipMcp,

    [switch]$InstallAgent365Cli
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

if (-not $PSBoundParameters.ContainsKey('AgentCount')) {
    $AgentCount = Read-NumberWithDefault -Prompt 'How many evaluated demo AI agents should be created?' -Default 9 -Minimum 1 -Maximum 30
}

if (-not $PSBoundParameters.ContainsKey('SkipMcp')) {
    $mcpAnswer = Read-Host 'Configure supported Agent 365 MCP tooling for medium/high profiles? [Y/n]'
    $SkipMcp = -not ([string]::IsNullOrWhiteSpace($mcpAnswer) -or $mcpAnswer -match '^(?i)y(?:es)?$')
}

$defaultCliPath = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.dotnet\tools\a365.exe'
$installCli = [bool]$InstallAgent365Cli -or (
    $null -eq (Get-Command a365 -ErrorAction SilentlyContinue) -and
    -not (Test-Path -LiteralPath $defaultCliPath -PathType Leaf)
)

$invokePath = Join-Path $PSScriptRoot 'Invoke-DefenderEvaluatedAgentLab.ps1'
& $invokePath `
    -GlobalAdminUpn $GlobalAdminUpn `
    -AgentCount $AgentCount `
    -RiskProfile $RiskProfile `
    -TenantId $TenantId `
    -SkipMcp:$SkipMcp `
    -InstallAgent365Cli:$installCli `
    -Execute
