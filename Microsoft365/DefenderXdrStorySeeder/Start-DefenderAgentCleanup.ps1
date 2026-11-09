#requires -Version 7.2

[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidatePattern('^[^@\s]+@[^@\s]+\.[^@\s]+$')]
    [string]$GlobalAdminUpn,

    [Parameter(Position = 1)]
    [string]$SearchRoot = (Join-Path $PSScriptRoot 'artifacts'),

    [string[]]$ManifestPath,

    [string]$NamePrefix = '[DXR Demo]',

    [switch]$UseDeviceCode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$cleanupPath = Join-Path $PSScriptRoot 'Invoke-DefenderAgentCleanup.ps1'
& $cleanupPath `
    -GlobalAdminUpn $GlobalAdminUpn `
    -SearchRoot $SearchRoot `
    -ManifestPath $ManifestPath `
    -DiscoverByPrefix `
    -NamePrefix $NamePrefix `
    -Execute `
    -UseDeviceCode:$UseDeviceCode

