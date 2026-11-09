#requires -Version 7.2

[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidatePattern('^[^@\s]+@[^@\s]+\.[^@\s]+$')]
    [string]$GlobalAdminUpn,

    [Parameter(Position = 1)]
    [string]$ManifestPath,

    [switch]$UseDeviceCode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$retryPath = Join-Path $PSScriptRoot 'Invoke-DefenderAgentRegistrationRetry.ps1'
& $retryPath `
    -GlobalAdminUpn $GlobalAdminUpn `
    -ManifestPath $ManifestPath `
    -Execute `
    -UseDeviceCode:$UseDeviceCode
