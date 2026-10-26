[CmdletBinding(DefaultParameterSetName = 'Interactive')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Token')]
    [string]$AccessToken,

    [Parameter(Mandatory, ParameterSetName = 'Sdk')]
    [switch]$UseGraphSdkSession,

    [Parameter(ParameterSetName = 'Interactive')]
    [switch]$UseDeviceCode,

    [Parameter(ParameterSetName = 'Interactive')]
    [string]$TenantId,

    [Parameter(ParameterSetName = 'Interactive')]
    [string]$ClientId,

    [Parameter(ParameterSetName = 'Interactive')]
    [switch]$InstallGraphModule,

    [Parameter(ParameterSetName = 'Interactive')]
    [switch]$DisconnectWhenComplete,

    [string]$OutputPath = (Join-Path $PSScriptRoot 'intune-readiness-evidence.json'),
    [string]$ManifestPath = (Join-Path $PSScriptRoot 'query-manifest.json'),
    [ValidateRange(0, 10)]
    [int]$MaxRetryCount = 4,
    [ValidateRange(2, 100)]
    [int]$JsonDepth = 40,
    [switch]$ExcludeBeta,
    [switch]$IncludeFullDeviceIdentity,
    [switch]$CaptureDebug,
    [switch]$Quiet
)

# Graph derived types legitimately omit properties that sibling types contain.
# Version 1 catches uninitialized variables without making those sparse payloads fatal.
Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'

function ConvertTo-PlainObject {
    param([AllowNull()][object]$InputObject)
    if ($null -eq $InputObject) { return $null }
    return ($InputObject | ConvertTo-Json -Depth 100 | ConvertFrom-Json)
}

function Write-CollectorStatus {
    param([Parameter(Mandatory)][string]$Message)
    if (-not $Quiet) {
        Write-Host ('[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $Message) -ForegroundColor Cyan
    }
}

function Import-GraphAuthenticationModule {
    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Authentication)) {
        if (-not $InstallGraphModule) {
            throw @'
Microsoft.Graph.Authentication is required for interactive sign-in.
Install it with:
  Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
Or rerun this collector with -InstallGraphModule.
'@
        }
        Write-CollectorStatus 'Installing Microsoft.Graph.Authentication for the current user...'
        Install-Module Microsoft.Graph.Authentication -Scope CurrentUser -Repository PSGallery -Force -AllowClobber
    }
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
}

function Connect-CollectorGraphSession {
    param([Parameter(Mandatory)][string[]]$Scopes)
    Import-GraphAuthenticationModule
    $connectParameters = @{
        Scopes = $Scopes
        ContextScope = 'Process'
        NoWelcome = $true
        ErrorAction = 'Stop'
    }
    if ($UseDeviceCode) { $connectParameters.UseDeviceCode = $true }
    if ($TenantId) { $connectParameters.TenantId = $TenantId }
    if ($ClientId) { $connectParameters.ClientId = $ClientId }

    $flow = if ($UseDeviceCode) { 'device-code' } else { 'interactive browser' }
    Write-CollectorStatus "Starting Microsoft Graph $flow sign-in..."
    Connect-MgGraph @connectParameters | Out-Null
    $context = Get-MgContext
    if ($null -eq $context -or [string]::IsNullOrWhiteSpace([string]$context.Account)) {
        throw 'Microsoft Graph authentication did not return a signed-in account.'
    }
    Write-CollectorStatus "Connected to Microsoft Graph as $($context.Account)."
    return $context
}

function Get-HttpStatusCode {
    param([System.Management.Automation.ErrorRecord]$ErrorRecord)
    $response = $ErrorRecord.Exception.Response
    if ($null -ne $response -and $null -ne $response.StatusCode) {
        try { return [int]$response.StatusCode } catch { }
    }
    if ($ErrorRecord.Exception.Message -match '\b(400|401|403|404|405|409|429|500|502|503|504)\b') {
        return [int]$Matches[1]
    }
    return $null
}

function Get-GraphErrorDiagnostics {
    param([System.Management.Automation.ErrorRecord]$ErrorRecord, [string]$Method, [AllowNull()][object]$RequestBody)
    $details = [ordered]@{ method = $Method; requestBody = $RequestBody }
    $response = $ErrorRecord.Exception.Response
    $body = $null
    if ($null -ne $ErrorRecord.ErrorDetails) { $body = [string]$ErrorRecord.ErrorDetails.Message }
    # SDK and PowerShell versions expose response content in different places.
    if ($null -ne $response) {
        try {
            if ($null -ne $response.Content -and $response.Content -is [System.Net.Http.HttpContent]) {
                $content = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                if ($content) { $body = $content }
            } elseif ($response.Content -is [string] -and $response.Content) { $body = $response.Content }
        } catch { }
        if (-not $body) {
            try {
                if ($response.PSObject.Methods['GetResponseStream']) {
                    $reader = [IO.StreamReader]::new($response.GetResponseStream())
                    try { $body = $reader.ReadToEnd() } finally { $reader.Dispose() }
                }
            } catch { }
        }
    }
    if (-not $body) {
        try { $body = [string]$ErrorRecord.Exception.ResponseBody } catch { }
    }
    if ($body) {
        $details.responseBody = $body
        try {
            $parsed = $body | ConvertFrom-Json -ErrorAction Stop
            if ($parsed.error) {
                $details.graphError = $parsed.error
            }
        } catch { }
    }
    $headers = [ordered]@{}
    foreach ($source in @($response, $ErrorRecord.Exception)) {
        if ($null -eq $source) { continue }
        foreach ($property in @('Headers','ResponseHeaders')) {
            try {
                $available = $source.$property
                if ($null -eq $available) { continue }
                foreach ($name in @('request-id','client-request-id','x-ms-request-id','Date','Retry-After')) {
                    $value = $null
                    if ($available -is [System.Net.Http.Headers.HttpHeaders]) {
                        if ($available.Contains($name)) { $value = @($available.GetValues($name)) -join ', ' }
                    } else { $value = $available[$name] }
                    if ($value) { $headers[$name] = [string]($value -join ', ') }
                }
            } catch { }
        }
    }
    $details.responseHeaders = $headers
    if (-not $body) { $details.bodyUnavailable = $true }
    return [pscustomobject]$details
}

function Invoke-GraphGet {
    param([Parameter(Mandatory)][string]$Uri, [ValidateSet('GET','POST')][string]$Method = 'GET', [AllowNull()][object]$Body)
    $attempt = 0
    while ($true) {
        try {
            if ($PSCmdlet.ParameterSetName -eq 'Token') {
                $request = @{ Method = $Method; Uri = $Uri; Headers = @{
                    Authorization = "Bearer $AccessToken"; Accept = 'application/json'
                }}
                if ($Method -eq 'POST') { $request.Body = ($Body | ConvertTo-Json -Depth 20 -Compress); $request.ContentType = 'application/json' }
                return Invoke-RestMethod @request
            }
            if (-not (Get-Command Invoke-MgGraphRequest -ErrorAction SilentlyContinue)) {
                throw 'Invoke-MgGraphRequest is unavailable. Install Microsoft.Graph.Authentication or provide -AccessToken.'
            }
            $request = @{ Method = $Method; Uri = $Uri; OutputType = 'PSObject' }
            if ($Method -eq 'POST') { $request.Body = ($Body | ConvertTo-Json -Depth 20 -Compress); $request.ContentType = 'application/json' }
            return Invoke-MgGraphRequest @request
        }
        catch {
            if ($CaptureDebug) {
                $diagnostics = Get-GraphErrorDiagnostics -ErrorRecord $_ -Method $Method -RequestBody $Body
                $_.Exception.Data['IntuneReadinessGraphDiagnostics'] = $diagnostics
            }
            $status = Get-HttpStatusCode -ErrorRecord $_
            $retryable = $status -in @(429, 500, 502, 503, 504)
            if (-not $retryable -or $attempt -ge $MaxRetryCount) { throw }
            $attempt++
            $delay = [Math]::Min(30, [Math]::Pow(2, $attempt))
            Start-Sleep -Seconds $delay
        }
    }
}

function Invoke-PolicyDeviceReport {
    param([string]$Uri, [string]$PolicyId)
    $skip = 0
    $top = 100
    do {
        $body = @{ filter = "(PolicyBaseTypeName eq 'DeviceManagementConfigurationPolicy') and (PolicyId eq '$PolicyId')"; skip = $skip; top = $top }
        $response = Invoke-GraphGet -Uri $Uri -Method POST -Body $body
        if ($response -is [byte[]]) { $response = [Text.Encoding]::UTF8.GetString($response) }
        if ($response -is [System.IO.Stream]) {
            $reader = [IO.StreamReader]::new($response)
            try { $response = $reader.ReadToEnd() } finally { $reader.Dispose() }
        }
        if ($response -is [string]) { $response = $response | ConvertFrom-Json }
        if ($response -is [System.Collections.IDictionary]) { $response = [pscustomobject]$response }
        if ($null -eq $response.PSObject.Properties['Schema'] -or $null -eq $response.PSObject.Properties['Values']) {
            throw 'Report response is missing Schema or Values; device status evidence was not collected.'
        }
        $names = @($response.Schema | ForEach-Object { $_.Column })
        $rows = @($response.Values)
        foreach ($row in $rows) {
            if (@($row).Count -ne $names.Count) { throw 'Report row does not match its column schema.' }
            $record = [ordered]@{}
            for ($i = 0; $i -lt $names.Count; $i++) { $record[$names[$i]] = $row[$i] }
            if (-not $IncludeFullDeviceIdentity) {
                foreach ($name in @('DeviceName','UserName','UPN','UserPrincipalName','UserId','AzureADDeviceId')) { $record.Remove($name) }
            }
            [pscustomobject]$record
        }
        $skip += $rows.Count
        if ($rows.Count -eq 0) { break }
        if ($null -ne $response.PSObject.Properties['TotalRowCount']) {
            if ($skip -ge [int]$response.TotalRowCount) { break }
        }
    } while ($rows.Count -eq $top)
}

function Invoke-PagedGraphGet {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [ValidateSet('collection', 'object')][string]$ResponseShape = 'collection'
    )
    if ($ResponseShape -eq 'object') { return ,(ConvertTo-PlainObject (Invoke-GraphGet -Uri $Uri)) }
    $items = [System.Collections.Generic.List[object]]::new()
    $next = $Uri
    while ($next) {
        $response = ConvertTo-PlainObject (Invoke-GraphGet -Uri $next)
        if ($null -ne $response.value) {
            foreach ($item in @($response.value)) { $items.Add($item) }
        }
        elseif ($null -ne $response) {
            $items.Add($response)
        }
        $nextProperty = $response.PSObject.Properties['@odata.nextLink']
        $next = if ($null -ne $nextProperty) { [string]$nextProperty.Value } else { $null }
    }
    # Do not use unary comma here. It turns the page into one nested Object[] record,
    # causing property access during normalization to return arrays of values.
    return $items.ToArray()
}

function New-Category {
    param([string]$Name)
    [ordered]@{
        name = $Name
        collectionStatus = 'notStarted'
        evidenceSummary = [ordered]@{}
        data = [ordered]@{}
        warnings = [System.Collections.Generic.List[object]]::new()
        errors = [System.Collections.Generic.List[object]]::new()
    }
}

function Get-PropertyValue {
    param([AllowNull()][object]$Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-TypeName {
    param([AllowNull()][object]$Object)
    $type = Get-PropertyValue $Object '@odata.type'
    if ($type) { return ([string]$type -replace '^#microsoft\.graph\.', '') }
    return $null
}

function Get-SyncAgeDays {
    param([AllowNull()][object]$Value, [DateTimeOffset]$RelativeTo = [DateTimeOffset]::UtcNow)
    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Array]) {
        if ($Value.Count -ne 1) { return $null }
        $Value = $Value[0]
    }
    $parsed = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse([string]$Value, [ref]$parsed)) { return $null }
    return ($RelativeTo - $parsed).TotalDays
}

function ConvertTo-CountMap {
    param([object[]]$Items, [string]$Property)
    $map = [ordered]@{}
    foreach ($group in @($Items | Group-Object -Property $Property)) {
        $key = if ([string]::IsNullOrWhiteSpace([string]$group.Name)) { 'unknown' } else { [string]$group.Name }
        $map[$key] = $group.Count
    }
    return $map
}

function Protect-ManagedDevice {
    param([object]$Device)
    $copy = ConvertTo-PlainObject $Device
    if (-not $IncludeFullDeviceIdentity) {
        foreach ($field in @('deviceName', 'userPrincipalName', 'userId', 'azureADDeviceId')) {
            if ($null -ne $copy.PSObject.Properties[$field]) { $copy.PSObject.Properties.Remove($field) }
        }
    }
    return $copy
}

function Set-NormalizedSummaries {
    param([System.Collections.IDictionary]$Categories)

    $enrollment = $Categories.managedDevicesEnrollment
    $devices = @($enrollment.data.managedDevices)
    $now = [DateTimeOffset]::UtcNow
    $windows = @($devices | Where-Object { $_.operatingSystem -match '^Windows' })
    $activeWindows = @($windows | Where-Object {
        $lastSync = Get-PropertyValue $_ 'lastSyncDateTime'
        $ageDays = Get-SyncAgeDays -Value $lastSync -RelativeTo $now
        $null -ne $ageDays -and $ageDays -le 30
    })
    $enrollment.evidenceSummary = [ordered]@{
        totalManagedDevices = $devices.Count
        windowsDevices = $windows.Count
        activeWindowsDevices30Days = $activeWindows.Count
        syncedWithin7Days = @($devices | Where-Object {
            $ageDays = Get-SyncAgeDays -Value (Get-PropertyValue $_ 'lastSyncDateTime') -RelativeTo $now
            $null -ne $ageDays -and $ageDays -le 7
        }).Count
        staleOver30Days = @($devices | Where-Object {
            $ageDays = Get-SyncAgeDays -Value (Get-PropertyValue $_ 'lastSyncDateTime') -RelativeTo $now
            $null -eq $ageDays -or $ageDays -gt 30
        }).Count
        ownerTypes = ConvertTo-CountMap $devices 'managedDeviceOwnerType'
        enrollmentTypes = ConvertTo-CountMap $devices 'deviceEnrollmentType'
        managementAgents = ConvertTo-CountMap $devices 'managementAgent'
        enrollmentConfigurationCount = @($enrollment.data.enrollmentConfigurations).Count
        enrollmentConfigurationAssignmentCount = @($enrollment.data.enrollmentConfigurationAssignments).Count
        autopilotIdentityCount = @($enrollment.data.autopilotDevices).Count
    }
    $enrollment.data.managedDevices = @($devices | ForEach-Object { Protect-ManagedDevice $_ })

    $compliance = $Categories.compliance
    $policies = @($compliance.data.policies)
    $deviceSummary = @($compliance.data.tenantDeviceStateSummary) | Select-Object -First 1
    $compliance.evidenceSummary = [ordered]@{
        policyCount = $policies.Count
        policyTypes = ConvertTo-CountMap $policies '@odata.type'
        assignmentCount = @($compliance.data.assignments).Count
        tenantDeviceState = $deviceSummary
        settingStateSummaryCount = @($compliance.data.settingStateSummaries).Count
        policyDeviceStatusCount = @($compliance.data.deviceStatuses).Count
    }

    $config = $Categories.endpointSecuritySettingsCatalog
    $legacy = @($config.data.legacyProfiles)
    $modern = @($config.data.modernPolicies)
    $intents = @($config.data.securityIntents)
    $config.evidenceSummary = [ordered]@{
        legacyProfileCount = $legacy.Count
        legacyProfileTypes = ConvertTo-CountMap $legacy '@odata.type'
        modernPolicyCount = $modern.Count
        modernPlatforms = ConvertTo-CountMap $modern 'platforms'
        modernTechnologies = ConvertTo-CountMap $modern 'technologies'
        modernSettingInstanceCount = @($config.data.modernSettings).Count
        assignmentCount = @($config.data.legacyAssignments).Count + @($config.data.modernAssignments).Count
        deviceStatusCount = @($config.data.legacyDeviceStatuses).Count + @($config.data.modernDeviceStatuses).Count
        securityIntentCount = $intents.Count
    }

    $bitlocker = $Categories.bitLockerEncryption
    $bitlocker.data.deviceEncryptionEvidence = @($windows | ForEach-Object {
        [ordered]@{ id = $_.id; isEncrypted = $_.isEncrypted; lastSyncDateTime = $_.lastSyncDateTime; complianceState = $_.complianceState }
    })
    $bitlocker.data.policyEvidence = @($policies + $legacy + $modern | Where-Object {
        (($_ | ConvertTo-Json -Depth 15 -Compress) -match '(?i)bitlocker|encryption')
    })
    $encrypted = @($activeWindows | Where-Object { $_.isEncrypted -eq $true }).Count
    $bitlocker.evidenceSummary = [ordered]@{
        activeWindowsDevices30Days = $activeWindows.Count
        encryptedActiveWindowsDevices = $encrypted
        encryptedActiveWindowsPercent = if ($activeWindows.Count) { [Math]::Round(100 * $encrypted / $activeWindows.Count, 2) } else { $null }
        encryptionRelatedPolicyObjectCount = @($bitlocker.data.policyEvidence).Count
    }

    $updates = $Categories.windowsUpdate
    $updateRings = @($legacy | Where-Object { (Get-TypeName $_) -eq 'windowsUpdateForBusinessConfiguration' })
    $updates.data.updateRings = $updateRings
    $updates.evidenceSummary = [ordered]@{
        updateRingCount = $updateRings.Count
        featureUpdateProfileCount = @($updates.data.featureUpdateProfiles).Count
        qualityUpdateProfileCount = @($updates.data.qualityUpdateProfiles).Count
        profileAssignmentCount = @($updates.data.featureUpdateAssignments).Count + @($updates.data.qualityUpdateAssignments).Count
        pausedUpdateRingCount = @($updateRings | Where-Object { $_.qualityUpdatesPaused -eq $true -or $_.featureUpdatesPaused -eq $true }).Count
    }

    $ca = $Categories.conditionalAccess
    $caPolicies = @($ca.data.policies)
    $ca.evidenceSummary = [ordered]@{
        policyCount = $caPolicies.Count
        states = ConvertTo-CountMap $caPolicies 'state'
        policiesUsingCompliantDeviceGrant = @($caPolicies | Where-Object {
            @($_.grantControls.builtInControls) -contains 'compliantDevice'
        }).Count
        policiesUsingApprovedAppGrant = @($caPolicies | Where-Object {
            @($_.grantControls.builtInControls) -contains 'approvedApplication'
        }).Count
        policiesUsingAppProtectionGrant = @($caPolicies | Where-Object {
            @($_.grantControls.builtInControls) -contains 'compliantApplication'
        }).Count
    }

    $defender = $Categories.defender
    $defenderPolicies = @($legacy + $modern + $intents | Where-Object {
        (($_ | ConvertTo-Json -Depth 15 -Compress) -match '(?i)defender|antivirus|firewall|attack.surface|endpoint.detection|tamper')
    })
    $threatStates = ConvertTo-CountMap $devices 'partnerReportedThreatState'
    $defender.data.policyEvidence = $defenderPolicies
    $defender.data.deviceThreatStateCounts = $threatStates
    $defender.evidenceSummary = [ordered]@{
        defenderRelatedPolicyObjectCount = $defenderPolicies.Count
        deviceThreatStates = $threatStates
        onboardingStateSummaryCollected = @($defender.data.onboardingStateSummary).Count -gt 0
    }

    $apps = $Categories.mobileApps
    $appItems = @($apps.data.apps)
    $apps.evidenceSummary = [ordered]@{
        appCount = $appItems.Count
        publishingStates = ConvertTo-CountMap $appItems 'publishingState'
        appTypes = ConvertTo-CountMap $appItems '@odata.type'
        assignmentCount = @($apps.data.assignments).Count
        assignmentIntents = ConvertTo-CountMap @($apps.data.assignments) 'intent'
    }

    $licenses = $Categories.licensing
    $skus = @($licenses.data.subscribedSkus)
    $licenses.evidenceSummary = [ordered]@{
        subscribedSkuCount = $skus.Count
        enabledSkuCount = @($skus | Where-Object { $_.capabilityStatus -eq 'Enabled' }).Count
        totalConsumedUnits = ($skus | Measure-Object -Property consumedUnits -Sum).Sum
        intuneRelatedServicePlans = @($skus.servicePlans | Where-Object { $_.servicePlanName -match '(?i)intune|mdm|endpoint' } | Select-Object servicePlanId,servicePlanName,provisioningStatus,appliesTo)
    }

    $rbac = $Categories.intuneRbac
    $roles = @($rbac.data.roleDefinitions)
    $roleAssignments = @($rbac.data.roleAssignments)
    $rbac.evidenceSummary = [ordered]@{
        roleDefinitionCount = $roles.Count
        customRoleDefinitionCount = @($roles | Where-Object { $_.isBuiltIn -eq $false }).Count
        roleAssignmentCount = $roleAssignments.Count
        assignedMemberReferenceCount = @($roleAssignments.members).Count
    }

    $mam = $Categories.mamAppProtection
    $mam.evidenceSummary = [ordered]@{
        iosPolicyCount = @($mam.data.iosPolicies).Count
        androidPolicyCount = @($mam.data.androidPolicies).Count
        targetedConfigurationCount = @($mam.data.targetedConfigurations).Count
        assignmentCount = @($mam.data.iosAssignments).Count + @($mam.data.androidAssignments).Count + @($mam.data.targetedConfigurationAssignments).Count
        personalManagedDeviceCount = @($devices | Where-Object { $_.managedDeviceOwnerType -eq 'personal' }).Count
    }
}

$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$createdGraphSession = $false
$graphContext = $null
if ($PSCmdlet.ParameterSetName -eq 'Interactive') {
    $requestedScopes = @($manifest.queries | Where-Object {
        -not ($ExcludeBeta -and $_.apiVersion -eq 'beta')
    } | ForEach-Object { $_.permissions } | Sort-Object -Unique)
    $graphContext = Connect-CollectorGraphSession -Scopes $requestedScopes
    $createdGraphSession = $true
}
elseif ($PSCmdlet.ParameterSetName -eq 'Sdk') {
    Import-GraphAuthenticationModule
    $graphContext = Get-MgContext
    if ($null -eq $graphContext) {
        throw 'No Microsoft Graph SDK session is active. Run Connect-MgGraph first, or run this collector without -UseGraphSdkSession for interactive sign-in.'
    }
}
$categoryNames = @(
    'managedDevicesEnrollment', 'compliance', 'endpointSecuritySettingsCatalog',
    'bitLockerEncryption', 'windowsUpdate', 'conditionalAccess', 'defender',
    'mobileApps', 'licensing', 'intuneRbac', 'mamAppProtection'
)
$categories = [ordered]@{}
foreach ($name in $categoryNames) { $categories[$name] = New-Category $name }
$rawResults = [ordered]@{}
$queryRuns = [System.Collections.Generic.List[object]]::new()
$globalWarnings = [System.Collections.Generic.List[object]]::new()
$globalErrors = [System.Collections.Generic.List[object]]::new()
$started = [DateTimeOffset]::UtcNow
$categoryLabels = [ordered]@{
    tenant = 'Reading tenant information'
    managedDevicesEnrollment = 'Extracting managed device and enrollment information'
    compliance = 'Extracting compliance information'
    endpointSecuritySettingsCatalog = 'Extracting Endpoint Security and Settings Catalog information'
    windowsUpdate = 'Extracting Windows Update information'
    conditionalAccess = 'Extracting Conditional Access information'
    defender = 'Extracting Microsoft Defender information'
    mobileApps = 'Extracting mobile app and assignment information'
    licensing = 'Extracting licensing information'
    intuneRbac = 'Extracting Intune RBAC information'
    mamAppProtection = 'Extracting MAM and app protection information'
}
$lastDisplayedCategory = $null

foreach ($query in $manifest.queries) {
    if ($ExcludeBeta -and $query.apiVersion -eq 'beta') {
        $warning = [ordered]@{ queryId = $query.id; code = 'BetaExcluded'; message = 'Skipped because -ExcludeBeta was specified.' }
        $globalWarnings.Add($warning)
        if ($categories.Contains($query.category)) { $categories[$query.category].warnings.Add($warning) }
        continue
    }
    if ($query.category -ne $lastDisplayedCategory) {
        $label = if ($categoryLabels.Contains($query.category)) { $categoryLabels[$query.category] } else { "Extracting $($query.category) information" }
        Write-CollectorStatus $label
        $lastDisplayedCategory = $query.category
    }
    $targets = @([ordered]@{ path = $query.path; parentId = $null })
    if ($null -ne $query.PSObject.Properties['pathTemplate']) {
        $parentResultKey = "{0}.{1}" -f $query.category, $query.forEachResultKey
        $parents = @($rawResults[$parentResultKey])
        $targets = @($parents | ForEach-Object {
            $parentId = [string](Get-PropertyValue $_ $query.parentIdField)
            if ($parentId) {
                [ordered]@{ path = ([string]$query.pathTemplate).Replace('{id}', [Uri]::EscapeDataString($parentId)); parentId = $parentId }
            }
        })
        $parentRuns = @($queryRuns | Where-Object {
            $_.category -eq $query.category -and $_.status -eq 'succeeded' -and
            $_.queryId -in @($manifest.queries | Where-Object { $_.category -eq $query.category -and $_.resultKey -eq $query.forEachResultKey } | ForEach-Object { $_.id })
        })
        if (-not $parents.Count -and -not $parentRuns.Count) {
            $parentWarning = [ordered]@{ queryId = $query.id; code = 'NoParentResults'; message = "No '$($query.forEachResultKey)' records were available for expansion." }
            $globalWarnings.Add($parentWarning)
            if ($categories.Contains($query.category)) { $categories[$query.category].warnings.Add($parentWarning) }
        }
    }
    foreach ($target in $targets) {
        $uri = "{0}/{1}{2}" -f $manifest.graphBaseUri, $query.apiVersion, $target.path
        $runStarted = [DateTimeOffset]::UtcNow
        try {
            $shape = if ($query.PSObject.Properties['responseShape']) { $query.responseShape } else { 'collection' }
            if ($shape -eq 'report') {
                $records = @(Invoke-PolicyDeviceReport -Uri $uri -PolicyId $target.parentId)
            } else {
                $records = @(Invoke-PagedGraphGet -Uri $uri -ResponseShape $shape)
            }
            if ($query.PSObject.Properties['outputFields']) {
                $records = @($records | Select-Object -Property $query.outputFields)
            }
            if ($target.parentId) {
                $records = @($records | ForEach-Object {
                    $copy = ConvertTo-PlainObject $_
                    $copy | Add-Member -NotePropertyName '_collectorParentId' -NotePropertyValue $target.parentId -Force
                    $copy
                })
            }
            $storageKey = "{0}.{1}" -f $query.category, $query.resultKey
            if (-not $rawResults.Contains($storageKey)) { $rawResults[$storageKey] = [System.Collections.Generic.List[object]]::new() }
            foreach ($record in $records) { $rawResults[$storageKey].Add($record) }
            $queryRuns.Add([ordered]@{
                queryId = $query.id; category = $query.category; apiVersion = $query.apiVersion
                uri = $uri; status = 'succeeded'; recordCount = $records.Count
                startedAtUtc = $runStarted.ToString('o'); completedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
            })
        }
        catch {
            $statusCode = Get-HttpStatusCode -ErrorRecord $_
            $code = if ($statusCode -in @(401,403)) { 'PermissionDenied' } elseif ($statusCode -eq 404) { 'EndpointUnavailable' } else { 'GraphRequestFailed' }
            $issue = [ordered]@{
                queryId = $query.id; category = $query.category; code = $code; httpStatus = $statusCode
                required = [bool]$query.required; uri = $uri; message = $_.Exception.Message
                expectedPermissions = @($query.permissions)

            }
            if ($CaptureDebug) {
                $issue.diagnostics = $_.Exception.Data['IntuneReadinessGraphDiagnostics']
            }
            if ($query.required) { $globalErrors.Add($issue) } else { $globalWarnings.Add($issue) }
            if ($categories.Contains($query.category)) {
                if ($query.required) { $categories[$query.category].errors.Add($issue) } else { $categories[$query.category].warnings.Add($issue) }
            }
            $queryRuns.Add([ordered]@{
                queryId = $query.id; category = $query.category; apiVersion = $query.apiVersion
                uri = $uri; status = 'failed'; recordCount = 0; httpStatus = $statusCode
                startedAtUtc = $runStarted.ToString('o'); completedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
            })
        }
    }
}

foreach ($query in $manifest.queries) {
    if ($query.category -eq 'tenant') { continue }
    if (-not $categories.Contains($query.category)) { continue }
    $storageKey = "{0}.{1}" -f $query.category, $query.resultKey
    if ($rawResults.Contains($storageKey)) {
        $categories[$query.category].data[$query.resultKey] = @($rawResults[$storageKey])
    }
    elseif (-not $categories[$query.category].data.Contains($query.resultKey)) {
        $categories[$query.category].data[$query.resultKey] = @()
    }
}
foreach ($category in $categories.Values) {
    $failed = @($queryRuns | Where-Object { $_.category -eq $category.name -and $_.status -eq 'failed' }).Count
    $succeeded = @($queryRuns | Where-Object { $_.category -eq $category.name -and $_.status -eq 'succeeded' }).Count
    $category.collectionStatus = if ($succeeded -and -not $failed) { 'complete' } elseif ($succeeded) { 'partial' } elseif ($failed) { 'failed' } else { 'notCollected' }
}

# These categories are normalized views over evidence collected by more than one API family.
Write-CollectorStatus 'Normalizing collected evidence and building category summaries'
$derivedSources = [ordered]@{
    bitLockerEncryption = @('managedDevicesEnrollment', 'compliance', 'endpointSecuritySettingsCatalog')
    windowsUpdate = @('endpointSecuritySettingsCatalog', 'windowsUpdate')
    defender = @('managedDevicesEnrollment', 'endpointSecuritySettingsCatalog', 'defender')
}
foreach ($derived in $derivedSources.Keys) {
    if ($categories[$derived].data.Count -eq 0) { $categories[$derived].data = [ordered]@{} }
    $sourceRuns = @($queryRuns | Where-Object { $_.category -in $derivedSources[$derived] })
    $sourceSuccess = @($sourceRuns | Where-Object status -eq 'succeeded').Count
    $sourceFailure = @($sourceRuns | Where-Object status -eq 'failed').Count
    $categories[$derived].collectionStatus = if ($sourceSuccess -and -not $sourceFailure) {
        'complete'
    } elseif ($sourceSuccess) {
        'partial'
    } elseif ($sourceFailure) {
        'failed'
    } else {
        'notCollected'
    }
}
Set-NormalizedSummaries -Categories $categories

$organization = @($rawResults['tenant.organizations']) | Select-Object -First 1
$tenantMetadata = [ordered]@{
    tenantId = Get-PropertyValue $organization 'id'
    displayName = Get-PropertyValue $organization 'displayName'
    tenantType = Get-PropertyValue $organization 'tenantType'
    createdDateTime = Get-PropertyValue $organization 'createdDateTime'
    verifiedDomains = @(Get-PropertyValue $organization 'verifiedDomains')
}
$completed = [DateTimeOffset]::UtcNow
$output = [ordered]@{
    schemaVersion = '1.0.0'
    assessmentType = 'IntuneEndpointReadinessEvidence'
    scoring = $null
    tenant = $tenantMetadata
    collection = [ordered]@{
        collectorName = 'IntuneReadinessCollector'
        collectorVersion = '1.0.5'
        manifestVersion = $manifest.manifestVersion
        startedAtUtc = $started.ToString('o')
        completedAtUtc = $completed.ToString('o')
        durationSeconds = [Math]::Round(($completed - $started).TotalSeconds, 3)
        authMode = switch ($PSCmdlet.ParameterSetName) {
            'Token' { 'bearerToken' }
            'Sdk' { 'existingGraphSdkSession' }
            default { if ($UseDeviceCode) { 'deviceCode' } else { 'interactiveBrowser' } }
        }
        authenticatedAccount = if ($null -ne $graphContext) { [string]$graphContext.Account } else { $null }
        authenticatedTenantId = if ($null -ne $graphContext) { [string]$graphContext.TenantId } else { $null }
        betaIncluded = -not [bool]$ExcludeBeta
        deviceIdentityIncluded = [bool]$IncludeFullDeviceIdentity
        queryRuns = $queryRuns.ToArray()
    }
    categories = $categories
    warnings = $globalWarnings.ToArray()
    errors = $globalErrors.ToArray()
}

$parent = Split-Path -Parent $OutputPath
if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
Write-CollectorStatus "Writing normalized evidence to $OutputPath"
$output | ConvertTo-Json -Depth $JsonDepth | Set-Content -LiteralPath $OutputPath -Encoding utf8
if ($CaptureDebug) {
    $debugPath = [IO.Path]::ChangeExtension($OutputPath, '.debug.json')
    $failedQueries = @($globalWarnings.ToArray()) + @($globalErrors.ToArray())
    $failedQueries = @($failedQueries | Where-Object { $_.Contains('httpStatus') })
    [ordered]@{
        collectorVersion = '1.0.5'
        evidenceFile = [IO.Path]::GetFullPath($OutputPath)
        completedAtUtc = $completed.ToString('o')
        failedQueries = $failedQueries
    } | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $debugPath -Encoding utf8
    Write-CollectorStatus "Writing failed-query diagnostics to $debugPath"
}
if ($createdGraphSession -and $DisconnectWhenComplete) {
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
}
Write-CollectorStatus 'Collection complete'
Write-Output (Resolve-Path -LiteralPath $OutputPath).Path





