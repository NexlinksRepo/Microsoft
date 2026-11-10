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

$retryPath = Join-Path $PSScriptRoot 'Invoke-DefenderAgentRegistrationRetry.ps1'
& $retryPath `
    -GlobalAdminUpn $GlobalAdminUpn `
    -ManifestPath $ManifestPath `
    -Execute `
    -UseDeviceCode:$UseDeviceCode
