#requires -Version 7.2

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$graphCachePaths = @(
    "$env:USERPROFILE\.mg\mg.authrecord*.json"
    "$env:LOCALAPPDATA\.IdentityService\mg.msal.cache.cae"
    "$env:LOCALAPPDATA\.IdentityService\mg.msal.cache.nocae"
)

$cacheFiles = @(
    Get-Item -Path $graphCachePaths -Force -ErrorAction SilentlyContinue |
        Sort-Object -Property FullName -Unique
)

if ($cacheFiles.Count -eq 0) {
    Write-Host 'No Microsoft Graph PowerShell authentication cache files were found.' -ForegroundColor Green
    return [pscustomobject]@{
        FoundCount = 0
        RemovedCount = 0
        RemovedPaths = @()
    }
}

if (-not $PSCmdlet.ShouldProcess(
    "$($cacheFiles.Count) Microsoft Graph authentication cache file(s) for the current Windows user",
    'Delete the cached authentication records and require a fresh Microsoft Graph sign-in on the next run'
)) {
    return
}

$removedPaths = [System.Collections.Generic.List[string]]::new()
foreach ($cacheFile in $cacheFiles) {
    Remove-Item -LiteralPath $cacheFile.FullName -Force -ErrorAction Stop
    $removedPaths.Add($cacheFile.FullName)
}

Write-Host "Removed $($removedPaths.Count) Microsoft Graph authentication cache file(s)." -ForegroundColor Green
[pscustomobject]@{
    FoundCount = $cacheFiles.Count
    RemovedCount = $removedPaths.Count
    RemovedPaths = @($removedPaths)
}
