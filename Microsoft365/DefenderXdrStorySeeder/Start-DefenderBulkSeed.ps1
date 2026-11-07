#requires -Version 7.2

[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidatePattern('^[^@\s]+@[^@\s]+\.[^@\s]+$')]
    [string]$GlobalAdminUpn,

    [ValidateRange(1, 50)]
    [int]$IncidentCount = 50,

    [switch]$UseDeviceCode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$seederPath = Join-Path $PSScriptRoot 'Invoke-DefenderBulkSeeder.ps1'
& $seederPath `
    -GlobalAdminUpn $GlobalAdminUpn `
    -IncidentCount $IncidentCount `
    -Execute `
    -UseDeviceCode:$UseDeviceCode
