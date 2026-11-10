#requires -Version 7.2

[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidatePattern('^[^@\s]+@[^@\s]+\.[^@\s]+$')]
    [string]$GlobalAdminUpn,

    [Parameter(Position = 1)]
    [string]$ManifestPath,

    [switch]$KeepLocalState
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
    $latestManifest = Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'artifacts') -Filter 'evaluated-agent-lab-run-*.json' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1
    if ($null -eq $latestManifest) {
        throw 'No evaluated-agent lab manifest was found. Supply its path as the second argument.'
    }
    $ManifestPath = $latestManifest.FullName
}

$invokePath = Join-Path $PSScriptRoot 'Invoke-DefenderEvaluatedAgentCleanup.ps1'
& $invokePath `
    -GlobalAdminUpn $GlobalAdminUpn `
    -ManifestPath $ManifestPath `
    -RemoveLocalState:(-not $KeepLocalState) `
    -Execute
