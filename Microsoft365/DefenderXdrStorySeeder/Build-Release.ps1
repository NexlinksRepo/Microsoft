#requires -Version 7.2

[CmdletBinding()]
param(
    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'dist')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$versionPath = Join-Path $PSScriptRoot 'VERSION'
if (-not (Test-Path -LiteralPath $versionPath -PathType Leaf)) {
    throw "VERSION file was not found: $versionPath"
}

$version = (Get-Content -LiteralPath $versionPath -Raw).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$') {
    throw "VERSION is not a supported semantic version: $version"
}

$testPath = Join-Path $PSScriptRoot 'tests\Offline.Tests.ps1'
& $testPath

$runtimeFiles = @(
    'Start-DefenderBulkSeed.ps1'
    'Invoke-DefenderBulkSeeder.ps1'
    'DefenderXdrStorySeeder.Authentication.ps1'
    'DefenderXdrStorySeeder.Agent365.ps1'
    'Start-DefenderAgentRegistrationRetry.ps1'
    'Invoke-DefenderAgentRegistrationRetry.ps1'
    'Start-DefenderAgentCleanup.ps1'
    'Invoke-DefenderAgentCleanup.ps1'
    'Start-DefenderBulkCleanup.ps1'
    'Invoke-DefenderBulkCleanup.ps1'
    'README.md'
    'CHANGELOG.md'
    'SECURITY.md'
    'VERSION'
)

foreach ($relativePath in $runtimeFiles) {
    $sourcePath = Join-Path $PSScriptRoot $relativePath
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "Required release file was not found: $sourcePath"
    }
}

foreach ($directoryName in @('catalog', 'docs')) {
    $sourcePath = Join-Path $PSScriptRoot $directoryName
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Container)) {
        throw "Required release directory was not found: $sourcePath"
    }
}

$repositoryLicense = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'LICENSE'
if (-not (Test-Path -LiteralPath $repositoryLicense -PathType Leaf)) {
    throw "Repository license was not found: $repositoryLicense"
}

if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}
$resolvedOutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path

$temporaryBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$temporaryRoot = Join-Path $temporaryBase "defender-xdr-story-seeder-$([guid]::NewGuid().ToString('N'))"
$packageRoot = Join-Path $temporaryRoot 'defender-xdr-story-seeder'
$archiveName = "Defender-XDR-Story-Seeder-v$version.zip"
$archivePath = Join-Path $resolvedOutputDirectory $archiveName
$checksumPath = Join-Path $resolvedOutputDirectory 'SHA256SUMS.txt'

try {
    New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null

    foreach ($relativePath in $runtimeFiles) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $relativePath) -Destination $packageRoot
    }
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'catalog') -Destination $packageRoot -Recurse
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'docs') -Destination $packageRoot -Recurse
    Copy-Item -LiteralPath $repositoryLicense -Destination (Join-Path $packageRoot 'LICENSE')

    Compress-Archive -LiteralPath $packageRoot -DestinationPath $archivePath -CompressionLevel Optimal -Force
    $hash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $archiveName" | Set-Content -LiteralPath $checksumPath -Encoding utf8
}
finally {
    $resolvedTemporaryRoot = [System.IO.Path]::GetFullPath($temporaryRoot)
    if ($resolvedTemporaryRoot.StartsWith($temporaryBase, [System.StringComparison]::OrdinalIgnoreCase) -and
        [System.IO.Path]::GetFileName($resolvedTemporaryRoot).StartsWith('defender-xdr-story-seeder-', [System.StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $resolvedTemporaryRoot)) {
        Remove-Item -LiteralPath $resolvedTemporaryRoot -Recurse -Force
    }
}

$archive = Get-Item -LiteralPath $archivePath
$checksum = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
Write-Host "Built $($archive.Name) ($($archive.Length) bytes)." -ForegroundColor Green
Write-Host "SHA-256: $checksum"
Write-Host "Checksums: $checksumPath"

[pscustomobject]@{
    Version      = $version
    ArchivePath  = $archive.FullName
    Length       = $archive.Length
    Sha256       = $checksum
    ChecksumPath = $checksumPath
}

