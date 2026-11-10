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
$bulkResult = & $cleanupPath `
    -GlobalAdminUpn $GlobalAdminUpn `
    -Execute `
    -UseDeviceCode:$UseDeviceCode

$evaluatedManifestPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$artifactPath = Join-Path $PSScriptRoot 'artifacts'
if (Test-Path -LiteralPath $artifactPath -PathType Container) {
    foreach ($seedFile in @(Get-ChildItem -LiteralPath $artifactPath -Filter 'bulk-seed-run-*.json' -File)) {
        try {
            $seedManifest = Get-Content -LiteralPath $seedFile.FullName -Raw | ConvertFrom-Json -AsHashtable -Depth 50
            if ($seedManifest.ContainsKey('evaluatedAgentManifestPath') -and
                -not [string]::IsNullOrWhiteSpace([string]$seedManifest.evaluatedAgentManifestPath) -and
                (Test-Path -LiteralPath ([string]$seedManifest.evaluatedAgentManifestPath) -PathType Leaf)) {
                $resolvedEvaluatedPath = (Resolve-Path -LiteralPath ([string]$seedManifest.evaluatedAgentManifestPath)).Path
                $evaluatedManifest = Get-Content -LiteralPath $resolvedEvaluatedPath -Raw | ConvertFrom-Json -AsHashtable -Depth 50
                if (-not ($evaluatedManifest.ContainsKey('cleanupSucceeded') -and [bool]$evaluatedManifest.cleanupSucceeded)) {
                    [void]$evaluatedManifestPaths.Add($resolvedEvaluatedPath)
                }
            }
        }
        catch {
            Write-Warning "Could not inspect '$($seedFile.FullName)' for evaluated-agent cleanup: $($_.Exception.Message)"
        }
    }
}

$evaluatedCleanupResults = @()
if ($evaluatedManifestPaths.Count -gt 0) {
    $evaluatedCleanupPath = Join-Path $PSScriptRoot 'Invoke-DefenderEvaluatedAgentCleanup.ps1'
    foreach ($evaluatedManifestPath in @($evaluatedManifestPaths | Sort-Object)) {
        $evaluatedCleanupResults += & $evaluatedCleanupPath `
            -GlobalAdminUpn $GlobalAdminUpn `
            -ManifestPath $evaluatedManifestPath `
            -RemoveLocalState `
            -Execute
    }
}

[pscustomobject]@{
    BulkCleanup = $bulkResult
    EvaluatedAgentCleanup = $evaluatedCleanupResults
}
