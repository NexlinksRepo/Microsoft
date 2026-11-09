#requires -Version 7.2

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[^@\s]+@[^@\s]+\.[^@\s]+$')]
    [string]$GlobalAdminUpn,

    [string]$ManifestPath,

    [string]$AiAgentCatalogPath = (Join-Path $PSScriptRoot 'catalog\ai-agent-catalog.json'),

    [switch]$Execute,

    [switch]$UseDeviceCode,

    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'artifacts')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProjectVersion = '0.2.1-beta'

. (Join-Path $PSScriptRoot 'DefenderXdrStorySeeder.Agent365.ps1')

function Install-GraphAuthenticationModule {
    $moduleName = 'Microsoft.Graph.Authentication'
    if (Get-Module -ListAvailable -Name $moduleName) {
        return
    }

    Write-Host "Installing required PowerShell module '$moduleName' for the current user..." -ForegroundColor Cyan
    if (Get-Command Install-PSResource -ErrorAction SilentlyContinue) {
        Install-PSResource -Name $moduleName -Repository PSGallery -Scope CurrentUser -TrustRepository -AcceptLicense -Quiet -ErrorAction Stop
    }
    elseif (Get-Command Install-Module -ErrorAction SilentlyContinue) {
        Install-Module -Name $moduleName -Repository PSGallery -Scope CurrentUser -Force -AllowClobber -Confirm:$false -ErrorAction Stop
    }
    else {
        throw "Install PowerShellGet or PSResourceGet, then install '$moduleName'."
    }
}

function Resolve-RegistrationManifestPath {
    param([AllowEmptyString()][string]$Path, [Parameter(Mandatory)][string]$Directory)

    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        return (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    }
    $latest = Get-ChildItem -LiteralPath $Directory -Filter 'bulk-seed-run-*.json' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1
    if ($null -eq $latest) {
        throw "No seed manifest was found under '$Directory'. Supply the existing manifest as the second argument or with -ManifestPath."
    }
    return $latest.FullName
}

function Save-Manifest {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Manifest, [Parameter(Mandatory)][string]$Path)
    $Manifest | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $Path -Encoding utf8
}

$resolvedManifestPath = Resolve-RegistrationManifestPath -Path $ManifestPath -Directory $OutputDirectory
$resolvedCatalogPath = (Resolve-Path -LiteralPath $AiAgentCatalogPath -ErrorAction Stop).Path
$manifest = Get-Content -LiteralPath $resolvedManifestPath -Raw | ConvertFrom-Json -AsHashtable
$catalog = Get-Content -LiteralPath $resolvedCatalogPath -Raw | ConvertFrom-Json -AsHashtable

if (-not $manifest.ContainsKey('agents') -or @($manifest.agents).Count -eq 0) {
    throw "The manifest does not contain demo-agent records: $resolvedManifestPath"
}

$definitionsById = @{}
foreach ($definition in @($catalog.agents)) {
    $definitionsById[[int]$definition.id] = $definition
}

$pendingAgents = @($manifest.agents | Where-Object {
    [string]::IsNullOrWhiteSpace([string]$_.agentRegistrationId) -and
    -not [string]::IsNullOrWhiteSpace([string]$_.blueprintId)
})

if (-not $Execute) {
    Write-Host 'DRY RUN — no Agent 365 registrations were changed.' -ForegroundColor Cyan
    $pendingAgents | Select-Object displayName, blueprintId, agentIdentityId, registrationSourceId | Format-Table -AutoSize | Out-Host
    return [pscustomobject]@{
        Mode = 'DryRun'
        Version = $ProjectVersion
        PendingRegistrationCount = $pendingAgents.Count
        ManifestPath = $resolvedManifestPath
    }
}

if ($pendingAgents.Count -eq 0) {
    Write-Host 'Every recorded demo agent already has a registration ID. Nothing needs retrying.' -ForegroundColor Green
    return [pscustomobject]@{ Mode = 'Executed'; Version = $ProjectVersion; Registered = 0; Failed = 0; ManifestPath = $resolvedManifestPath }
}

if (-not $PSCmdlet.ShouldProcess(
    "Agent 365 registry selected by $GlobalAdminUpn",
    "Retry registration for $($pendingAgents.Count) existing demo agent identity set(s); do not recreate identities, incidents, or alerts"
)) {
    return
}

Install-GraphAuthenticationModule
Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
$connectParameters = @{
    Scopes = @('AgentRegistration.ReadWrite.All', 'User.Read')
    ContextScope = 'Process'
    LoginHint = $GlobalAdminUpn
    NoWelcome = $true
}
if ($UseDeviceCode) {
    $connectParameters.UseDeviceCode = $true
}

$context = $null
$registered = 0
$failed = 0
$retryLog = [ordered]@{
    toolVersion = $ProjectVersion
    attemptedAtUtc = [DateTime]::UtcNow.ToString('o')
    signedInAccount = $null
    tenantId = $null
    requestedCount = $pendingAgents.Count
    succeeded = @()
    failed = @()
}

try {
    Connect-MgGraph @connectParameters | Out-Null
    $context = Get-MgContext
    $retryLog.signedInAccount = [string]$context.Account
    $retryLog.tenantId = [string]$context.TenantId
    if ('AgentRegistration.ReadWrite.All' -notin @($context.Scopes)) {
        throw 'The access token does not contain AgentRegistration.ReadWrite.All. Grant admin consent and retry.'
    }

    $escapedUpn = [uri]::EscapeDataString($GlobalAdminUpn)
    $owner = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/users/$escapedUpn`?`$select=id" -OutputType PSObject -ErrorAction Stop
    $ownerId = [string]$owner.id
    if ([string]::IsNullOrWhiteSpace($ownerId)) {
        throw "Could not resolve '$GlobalAdminUpn' to an owner object ID."
    }

    $number = 0
    foreach ($agent in $pendingAgents) {
        $number++
        Write-Progress -Activity 'Retrying Agent 365 registration' -Status "$number of $($pendingAgents.Count): $($agent.displayName)" -PercentComplete (($number / $pendingAgents.Count) * 100)
        try {
            $catalogId = [int]$agent.catalogId
            if (-not $definitionsById.ContainsKey($catalogId)) {
                throw "AI-agent catalog entry $catalogId was not found."
            }
            $registration = Register-DemoAiAgent -Definition $definitionsById[$catalogId] -AgentRecord $agent -OwnerId $ownerId
            $agent['agentRegistrationId'] = [string]$registration.id
            $agent.componentStatus['agentRegistration'] = 'created'
            $agent['registrationError'] = $null
            $agent['errors'] = @($agent.errors | Where-Object { [string]$_ -notmatch '^agentRegistration:' })
            $createdComponentCount = @($agent.componentStatus.Values | Where-Object { $_ -eq 'created' }).Count
            $agent['creationStatus'] = if ($createdComponentCount -eq 4) { 'created' } else { 'partial' }
            $registered++
            $retryLog.succeeded = @($retryLog.succeeded) + [ordered]@{
                displayName = [string]$agent.displayName
                agentRegistrationId = [string]$registration.id
            }
        }
        catch {
            $errorInfo = Get-AgentGraphErrorInfo -ErrorRecord $_
            $agent['registrationError'] = $errorInfo
            $agent.componentStatus['agentRegistration'] = 'unavailable'
            $agent['errors'] = @($agent.errors | Where-Object { [string]$_ -notmatch '^agentRegistration:' }) + "agentRegistration: $($errorInfo.message) Response: $($errorInfo.responseBody)"
            $failed++
            $retryLog.failed = @($retryLog.failed) + [ordered]@{
                displayName = [string]$agent.displayName
                statusCode = $errorInfo.statusCode
                message = $errorInfo.message
                responseBody = $errorInfo.responseBody
            }
            Write-Warning "Registration failed for '$($agent.displayName)' with HTTP $($errorInfo.statusCode). Response: $($errorInfo.responseBody)"
        }

        $manifest['lastRegistrationRetryToolVersion'] = $ProjectVersion
        $manifest['lastRegistrationRetryAtUtc'] = [DateTime]::UtcNow.ToString('o')
        if (-not $manifest.ContainsKey('registrationRetries')) {
            $manifest['registrationRetries'] = @()
        }
        Save-Manifest -Manifest $manifest -Path $resolvedManifestPath
    }
    Write-Progress -Activity 'Retrying Agent 365 registration' -Completed

    $manifest.capabilities['agentRegistry'] = if ($registered -gt 0) { 'available' } elseif ($failed -gt 0) { 'denied' } else { [string]$manifest.capabilities.agentRegistry }
    $retryLog['completedAtUtc'] = [DateTime]::UtcNow.ToString('o')
    $manifest.registrationRetries = @($manifest.registrationRetries) + $retryLog
    Save-Manifest -Manifest $manifest -Path $resolvedManifestPath
}
finally {
    Write-Progress -Activity 'Retrying Agent 365 registration' -Completed
    if ($null -ne $context) {
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    }
}

if ($failed -gt 0) {
    Write-Warning "$failed registration(s) still failed. The full Graph response is now stored in the manifest."
}
if ($registered -gt 0) {
    Write-Host "Registered $registered existing demo agent(s) without recreating identities, incidents, or alerts." -ForegroundColor Green
}

[pscustomobject]@{
    Mode = 'Executed'
    Version = $ProjectVersion
    Registered = $registered
    Failed = $failed
    ManifestPath = $resolvedManifestPath
}
