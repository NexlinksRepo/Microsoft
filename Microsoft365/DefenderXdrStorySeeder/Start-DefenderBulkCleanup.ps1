#requires -Version 7.2

[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidatePattern('^[^@\s]+@[^@\s]+\.[^@\s]+$')]
    [string]$GlobalAdminUpn,

    [switch]$UseDeviceCode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$cleanupPath = Join-Path $PSScriptRoot 'Invoke-DefenderBulkCleanup.ps1'
& $cleanupPath `
    -GlobalAdminUpn $GlobalAdminUpn `
    -Execute `
    -UseDeviceCode:$UseDeviceCode
