#requires -Version 7.2

[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidatePattern('^[^@\s]+@[^@\s]+\.[^@\s]+$')]
    [string]$GlobalAdminUpn,

    [Parameter(Position = 1)]
    [string]$SearchRoot = (Join-Path $PSScriptRoot 'artifacts'),

    [string[]]$ManifestPath,

    [string]$NamePrefix = '[MXDR Demo]',

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

$cleanupPath = Join-Path $PSScriptRoot 'Invoke-DefenderAgentCleanup.ps1'
& $cleanupPath `
    -GlobalAdminUpn $GlobalAdminUpn `
    -SearchRoot $SearchRoot `
    -ManifestPath $ManifestPath `
    -DiscoverByPrefix `
    -NamePrefix $NamePrefix `
    -Execute `
    -UseDeviceCode:$UseDeviceCode

