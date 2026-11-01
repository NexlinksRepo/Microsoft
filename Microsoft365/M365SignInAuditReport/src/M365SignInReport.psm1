Set-StrictMode -Version 2.0

$script:ProjectVersion = '0.0.1-beta'

function Get-ObjectProperty {
    param(
        [AllowNull()]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name,
        [AllowNull()]$Default = $null
    )

    if ($null -eq $InputObject) { return $Default }
    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) { return $InputObject[$Name] }
        return $Default
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    return $property.Value
}

function Test-ObjectProperty {
    param(
        [AllowNull()]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($null -eq $InputObject) { return $false }
    if ($InputObject -is [System.Collections.IDictionary]) { return $InputObject.Contains($Name) }
    return $null -ne $InputObject.PSObject.Properties[$Name]
}

function ConvertTo-StringArray {
    param([AllowNull()]$Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Value)) { return @() }
        return @($Value)
    }
    return @($Value | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Get-StableId {
    param([Parameter(Mandatory = $true)][string]$Text)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function ConvertTo-NormalizedSignIn {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true, ValueFromPipeline = $true)]$SignIn)

    process {
        $status = Get-ObjectProperty -InputObject $SignIn -Name 'status'
        $location = Get-ObjectProperty -InputObject $SignIn -Name 'location'
        $geo = Get-ObjectProperty -InputObject $location -Name 'geoCoordinates'
        $device = Get-ObjectProperty -InputObject $SignIn -Name 'deviceDetail'

        $timeValue = Get-ObjectProperty -InputObject $SignIn -Name 'createdDateTime'
        $timeText = [string]$timeValue
        $time = [DateTimeOffset]::MinValue
        if ($timeValue -is [DateTimeOffset]) {
            $time = ([DateTimeOffset]$timeValue).ToUniversalTime()
        }
        elseif ($timeValue -is [DateTime]) {
            $dateTimeValue = [DateTime]$timeValue
            if ($dateTimeValue.Kind -eq [DateTimeKind]::Unspecified) { $dateTimeValue = [DateTime]::SpecifyKind($dateTimeValue, [DateTimeKind]::Utc) }
            $time = ([DateTimeOffset]$dateTimeValue).ToUniversalTime()
        }
        elseif (-not [DateTimeOffset]::TryParse($timeText, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$time)) {
            throw "A sign-in record has an invalid createdDateTime value: '$timeText'."
        }
        $time = $time.ToUniversalTime()

        $userPrincipalName = [string](Get-ObjectProperty -InputObject $SignIn -Name 'userPrincipalName')
        $servicePrincipalName = [string](Get-ObjectProperty -InputObject $SignIn -Name 'servicePrincipalName')
        $managedIdentity = Get-ObjectProperty -InputObject $SignIn -Name 'managedServiceIdentity'
        $managedIdentityName = [string](Get-ObjectProperty -InputObject $managedIdentity -Name 'msiType')

        $actor = $userPrincipalName
        $actorType = 'User'
        if ([string]::IsNullOrWhiteSpace($actor)) {
            $actor = $servicePrincipalName
            $actorType = 'ServicePrincipal'
        }
        if ([string]::IsNullOrWhiteSpace($actor)) {
            $actor = [string](Get-ObjectProperty -InputObject $SignIn -Name 'userDisplayName')
        }
        if ([string]::IsNullOrWhiteSpace($actor) -and -not [string]::IsNullOrWhiteSpace($managedIdentityName)) {
            $actor = $managedIdentityName
            $actorType = 'ManagedIdentity'
        }
        if ([string]::IsNullOrWhiteSpace($actor)) {
            $actor = [string](Get-ObjectProperty -InputObject $SignIn -Name 'appDisplayName' -Default '(unknown actor)')
            $actorType = 'Workload'
        }

        $eventTypes = @(ConvertTo-StringArray (Get-ObjectProperty -InputObject $SignIn -Name 'signInEventTypes'))
        if ($eventTypes.Count -gt 0) {
            $eventType = $eventTypes -join ', '
            if ($eventTypes -contains 'servicePrincipal') { $actorType = 'ServicePrincipal' }
            if ($eventTypes -contains 'managedIdentity') { $actorType = 'ManagedIdentity' }
        }
        else {
            $eventType = if ([bool](Get-ObjectProperty -InputObject $SignIn -Name 'isInteractive' -Default $false)) { 'interactiveUser' } else { 'unspecified' }
        }

        $errorCodeValue = Get-ObjectProperty -InputObject $status -Name 'errorCode' -Default 0
        $errorCode = 0L
        [void][long]::TryParse([string]$errorCodeValue, [ref]$errorCode)

        $policies = [System.Collections.Generic.List[object]]::new()
        $rawPolicies = Get-ObjectProperty -InputObject $SignIn -Name 'appliedConditionalAccessPolicies'
        foreach ($policy in @($rawPolicies)) {
            if ($null -eq $policy) { continue }
            $policies.Add([pscustomobject]@{
                Id                      = [string](Get-ObjectProperty -InputObject $policy -Name 'id')
                DisplayName             = [string](Get-ObjectProperty -InputObject $policy -Name 'displayName' -Default '(unnamed policy)')
                Result                  = [string](Get-ObjectProperty -InputObject $policy -Name 'result' -Default 'unknown')
                EnforcedGrantControls   = @(ConvertTo-StringArray (Get-ObjectProperty -InputObject $policy -Name 'enforcedGrantControls'))
                EnforcedSessionControls = @(ConvertTo-StringArray (Get-ObjectProperty -InputObject $policy -Name 'enforcedSessionControls'))
            })
        }

        $latitude = $null
        $longitude = $null
        $latitudeValue = Get-ObjectProperty -InputObject $geo -Name 'latitude'
        $longitudeValue = Get-ObjectProperty -InputObject $geo -Name 'longitude'
        $parsedCoordinate = 0.0
        if ($null -ne $latitudeValue -and [double]::TryParse([string]$latitudeValue, [Globalization.NumberStyles]::Any, [Globalization.CultureInfo]::InvariantCulture, [ref]$parsedCoordinate)) {
            $latitude = $parsedCoordinate
        }
        $parsedCoordinate = 0.0
        if ($null -ne $longitudeValue -and [double]::TryParse([string]$longitudeValue, [Globalization.NumberStyles]::Any, [Globalization.CultureInfo]::InvariantCulture, [ref]$parsedCoordinate)) {
            $longitude = $parsedCoordinate
        }

        $id = [string](Get-ObjectProperty -InputObject $SignIn -Name 'id')
        if ([string]::IsNullOrWhiteSpace($id)) {
            $id = Get-StableId "$($time.ToString('o'))|$actor|$(Get-ObjectProperty -InputObject $SignIn -Name 'ipAddress')|$(Get-ObjectProperty -InputObject $SignIn -Name 'appId')|$errorCode"
        }

        [pscustomobject]@{
            Id                          = $id
            TimeUtc                     = $time.ToString('o')
            Actor                       = $actor
            ActorType                   = $actorType
            UserDisplayName             = [string](Get-ObjectProperty -InputObject $SignIn -Name 'userDisplayName')
            UserId                      = [string](Get-ObjectProperty -InputObject $SignIn -Name 'userId')
            AppDisplayName              = [string](Get-ObjectProperty -InputObject $SignIn -Name 'appDisplayName')
            AppId                       = [string](Get-ObjectProperty -InputObject $SignIn -Name 'appId')
            ResourceDisplayName         = [string](Get-ObjectProperty -InputObject $SignIn -Name 'resourceDisplayName')
            IPAddress                   = [string](Get-ObjectProperty -InputObject $SignIn -Name 'ipAddress')
            ClientAppUsed               = [string](Get-ObjectProperty -InputObject $SignIn -Name 'clientAppUsed')
            EventType                   = $eventType
            IsInteractive               = [bool](Get-ObjectProperty -InputObject $SignIn -Name 'isInteractive' -Default $false)
            IsSuccess                   = ($errorCode -eq 0)
            ErrorCode                   = $errorCode
            FailureReason               = [string](Get-ObjectProperty -InputObject $status -Name 'failureReason')
            AdditionalDetails           = [string](Get-ObjectProperty -InputObject $status -Name 'additionalDetails')
            ConditionalAccessStatus     = [string](Get-ObjectProperty -InputObject $SignIn -Name 'conditionalAccessStatus' -Default 'unknown')
            CaPolicyDataPresent         = [bool](Test-ObjectProperty -InputObject $SignIn -Name 'appliedConditionalAccessPolicies')
            Policies                    = @($policies)
            Country                     = [string](Get-ObjectProperty -InputObject $location -Name 'countryOrRegion')
            State                       = [string](Get-ObjectProperty -InputObject $location -Name 'state')
            City                        = [string](Get-ObjectProperty -InputObject $location -Name 'city')
            Latitude                    = $latitude
            Longitude                   = $longitude
            DeviceId                    = [string](Get-ObjectProperty -InputObject $device -Name 'deviceId')
            DeviceName                  = [string](Get-ObjectProperty -InputObject $device -Name 'displayName')
            OperatingSystem             = [string](Get-ObjectProperty -InputObject $device -Name 'operatingSystem')
            Browser                     = [string](Get-ObjectProperty -InputObject $device -Name 'browser')
            IsCompliant                 = Get-ObjectProperty -InputObject $device -Name 'isCompliant'
            IsManaged                   = Get-ObjectProperty -InputObject $device -Name 'isManaged'
            TrustType                   = [string](Get-ObjectProperty -InputObject $device -Name 'trustType')
            RiskLevel                   = [string](Get-ObjectProperty -InputObject $SignIn -Name 'riskLevelAggregated' -Default 'none')
            RiskLevelDuringSignIn       = [string](Get-ObjectProperty -InputObject $SignIn -Name 'riskLevelDuringSignIn' -Default 'none')
            RiskState                   = [string](Get-ObjectProperty -InputObject $SignIn -Name 'riskState' -Default 'none')
            RiskDetail                  = [string](Get-ObjectProperty -InputObject $SignIn -Name 'riskDetail' -Default 'none')
            RiskEventTypes              = @(ConvertTo-StringArray (Get-ObjectProperty -InputObject $SignIn -Name 'riskEventTypes_v2'))
            CorrelationId               = [string](Get-ObjectProperty -InputObject $SignIn -Name 'correlationId')
        }
    }
}

function Select-ReportableSignIn {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true, ValueFromPipeline = $true)]$Record)

    process {
        $eventTypes = @(([string]$Record.EventType -split '\s*,\s*') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $isNonInteractiveUser = ($eventTypes -contains 'nonInteractiveUser') -or
            (($eventTypes -contains 'unspecified') -and [string]$Record.ActorType -eq 'User' -and -not [bool]$Record.IsInteractive)
        $isManagedIdentity = ($eventTypes -contains 'managedIdentity') -or [string]$Record.ActorType -eq 'ManagedIdentity'
        $isServicePrincipal = ($eventTypes -contains 'servicePrincipal') -or [string]$Record.ActorType -eq 'ServicePrincipal'
        if (-not $isNonInteractiveUser -and -not $isManagedIdentity -and -not $isServicePrincipal) { $Record }
    }
}

function Get-GraphResponseText {
    param([Parameter(Mandatory = $true)]$Response)
    return $Response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
}

function Invoke-GraphGetWithRetry {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [hashtable]$Headers = @{},
        [ValidateRange(1, 10)][int]$MaxAttempts = 5
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            return Invoke-MgGraphRequest -Method GET -Uri $Uri -Headers $Headers -OutputType HttpResponseMessage -ErrorAction Stop
        }
        catch {
            $statusCode = 0
            $response = $_.Exception.Response
            if ($null -ne $response) {
                try { $statusCode = [int]$response.StatusCode } catch { $statusCode = 0 }
            }
            $isTransient = $statusCode -in @(429, 500, 502, 503, 504)
            if (-not $isTransient -or $attempt -eq $MaxAttempts) { throw }

            $delaySeconds = [math]::Min(60, [math]::Pow(2, $attempt))
            try {
                $retryAfter = $response.Headers.RetryAfter.Delta.TotalSeconds
                if ($retryAfter -gt 0) { $delaySeconds = [math]::Min(60, [math]::Ceiling($retryAfter)) }
            }
            catch { }
            Write-Warning "Microsoft Graph returned HTTP $statusCode. Retrying in $delaySeconds seconds (attempt $attempt of $MaxAttempts)."
            Start-Sleep -Seconds $delaySeconds
        }
    }
}

function Get-GraphSignInEvents {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][DateTimeOffset]$StartTimeUtc,
        [Parameter(Mandatory = $true)][DateTimeOffset]$EndTimeUtc,
        [Parameter(Mandatory = $true)][string]$RawDirectory,
        [ValidateSet('beta', 'v1.0')][string]$GraphApiVersion = 'beta',
        [string[]]$EventTypes = @('interactiveUser'),
        [ValidateRange(1, 1000)][int]$PageSize = 1000
    )

    if ($StartTimeUtc -ge $EndTimeUtc) { throw 'StartTimeUtc must be earlier than EndTimeUtc.' }
    if ($GraphApiVersion -eq 'v1.0' -and $EventTypes.Count -gt 0) {
        Write-Warning 'The v1.0 sign-in endpoint does not support signInEventTypes. Collecting the v1.0 user sign-in stream once.'
        $EventTypes = @('')
    }
    if ($GraphApiVersion -eq 'beta' -and $EventTypes.Count -eq 0) { $EventTypes = @('interactiveUser') }

    $pageDirectory = Join-Path $RawDirectory 'api-pages'
    [void](New-Item -ItemType Directory -Force -Path $pageDirectory)
    $jsonlPath = Join-Path $RawDirectory 'signins.jsonl'
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    $writer = [System.IO.StreamWriter]::new($jsonlPath, $false, $utf8NoBom)
    $events = [System.Collections.Generic.List[object]]::new()
    $seenIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $stats = [System.Collections.Generic.List[object]]::new()

    try {
        foreach ($eventType in $EventTypes) {
            $baseFilter = "createdDateTime ge $($StartTimeUtc.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')) and createdDateTime lt $($EndTimeUtc.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))"
            if (-not [string]::IsNullOrWhiteSpace($eventType)) {
                $baseFilter += " and signInEventTypes/any(t:t eq '$eventType')"
            }
            $encodedFilter = [uri]::EscapeDataString($baseFilter)
            $uri = "https://graph.microsoft.com/$GraphApiVersion/auditLogs/signIns?`$filter=$encodedFilter&`$top=$PageSize"
            $pageNumber = 0
            $eventCount = 0
            $safeEventType = if ([string]::IsNullOrWhiteSpace($eventType)) { 'user' } else { $eventType }

            while (-not [string]::IsNullOrWhiteSpace($uri)) {
                $pageNumber++
                Write-Progress -Activity 'Collecting Microsoft Entra sign-in logs' -Status "$safeEventType page $pageNumber" -CurrentOperation $uri
                $response = Invoke-GraphGetWithRetry -Uri $uri -Headers @{ Prefer = 'include-unknown-enum-members' }
                $rawText = Get-GraphResponseText -Response $response
                $pagePath = Join-Path $pageDirectory ('{0}-page-{1:D5}.json' -f $safeEventType, $pageNumber)
                [System.IO.File]::WriteAllText($pagePath, $rawText, $utf8NoBom)
                $page = $rawText | ConvertFrom-Json

                $pageEventCount = 0
                foreach ($event in @(Get-ObjectProperty -InputObject $page -Name 'value' -Default @())) {
                    $id = [string](Get-ObjectProperty -InputObject $event -Name 'id')
                    if ([string]::IsNullOrWhiteSpace($id)) {
                        $id = Get-StableId (($event | ConvertTo-Json -Depth 15 -Compress))
                    }
                    if ($seenIds.Add($id)) {
                        $events.Add($event)
                        $writer.WriteLine(($event | ConvertTo-Json -Depth 50 -Compress))
                        $eventCount++
                        $pageEventCount++
                    }
                }
                Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Retrieved $safeEventType page ${pageNumber}: $pageEventCount new records ($eventCount total)." -ForegroundColor DarkCyan
                $uri = [string](Get-ObjectProperty -InputObject $page -Name '@odata.nextLink')
            }
            $stats.Add([pscustomobject]@{ EventType = $safeEventType; Pages = $pageNumber; Events = $eventCount })
        }
    }
    finally {
        $writer.Dispose()
        Write-Progress -Activity 'Collecting Microsoft Entra sign-in logs' -Completed
    }

    return [pscustomobject]@{
        Events    = @($events)
        Statistics = @($stats)
        JsonlPath = $jsonlPath
    }
}

function Read-SignInInputFile {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    $resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    $extension = [System.IO.Path]::GetExtension($resolvedPath)
    $items = [System.Collections.Generic.List[object]]::new()

    if ($extension -eq '.jsonl' -or $extension -eq '.ndjson') {
        foreach ($line in [System.IO.File]::ReadLines($resolvedPath)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $items.Add(($line | ConvertFrom-Json))
        }
    }
    else {
        $parsed = ([System.IO.File]::ReadAllText($resolvedPath) | ConvertFrom-Json)
        if (Test-ObjectProperty -InputObject $parsed -Name 'value') {
            foreach ($item in @(Get-ObjectProperty -InputObject $parsed -Name 'value')) { $items.Add($item) }
        }
        else {
            foreach ($item in @($parsed)) { $items.Add($item) }
        }
    }
    return @($items)
}

function Save-NormalizedEventCache {
    param(
        [Parameter(Mandatory = $true)][object[]]$Records,
        [Parameter(Mandatory = $true)][string]$StateDirectory,
        [Parameter(Mandatory = $true)][DateTimeOffset]$CollectedThroughUtc,
        [Parameter(Mandatory = $true)][DateTimeOffset]$RetainFromUtc
    )

    $eventsDirectory = Join-Path $StateDirectory 'events'
    [void](New-Item -ItemType Directory -Force -Path $eventsDirectory)
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)

    $groups = $Records | Group-Object { ([DateTimeOffset]$_.TimeUtc).UtcDateTime.ToString('yyyy-MM-dd') }
    foreach ($group in $groups) {
        $path = Join-Path $eventsDirectory ($group.Name + '.jsonl')
        $knownIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        if (Test-Path -LiteralPath $path) {
            foreach ($line in [System.IO.File]::ReadLines($path)) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                try {
                    $cached = $line | ConvertFrom-Json
                    [void]$knownIds.Add([string]$cached.Id)
                }
                catch { Write-Warning "Skipped a malformed cache line in '$path'." }
            }
        }
        $writer = [System.IO.StreamWriter]::new($path, $true, $utf8NoBom)
        try {
            foreach ($record in $group.Group) {
                if ($knownIds.Add([string]$record.Id)) {
                    $writer.WriteLine(($record | ConvertTo-Json -Depth 15 -Compress))
                }
            }
        }
        finally { $writer.Dispose() }
    }

    $oldestDate = $RetainFromUtc.UtcDateTime.Date
    foreach ($file in Get-ChildItem -LiteralPath $eventsDirectory -Filter '*.jsonl' -File -ErrorAction SilentlyContinue) {
        $bucketDate = [datetime]::MinValue
        if ([datetime]::TryParseExact($file.BaseName, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$bucketDate)) {
            if ($bucketDate.Date -lt $oldestDate) { Remove-Item -LiteralPath $file.FullName -Force }
        }
    }

    $state = [ordered]@{
        SchemaVersion        = 1
        ProjectVersion       = $script:ProjectVersion
        CollectedThroughUtc  = $CollectedThroughUtc.ToUniversalTime().ToString('o')
        UpdatedUtc           = [DateTimeOffset]::UtcNow.ToString('o')
    }
    [System.IO.File]::WriteAllText((Join-Path $StateDirectory 'state.json'), ($state | ConvertTo-Json -Depth 5), $utf8NoBom)
}

function Get-NormalizedEventCache {
    param(
        [Parameter(Mandatory = $true)][string]$StateDirectory,
        [Parameter(Mandatory = $true)][DateTimeOffset]$StartTimeUtc,
        [Parameter(Mandatory = $true)][DateTimeOffset]$EndTimeUtc
    )

    $eventsDirectory = Join-Path $StateDirectory 'events'
    $records = [System.Collections.Generic.List[object]]::new()
    $seenIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if (-not (Test-Path -LiteralPath $eventsDirectory)) { return @() }

    foreach ($file in Get-ChildItem -LiteralPath $eventsDirectory -Filter '*.jsonl' -File | Sort-Object Name) {
        foreach ($line in [System.IO.File]::ReadLines($file.FullName)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $record = $line | ConvertFrom-Json
                $time = [DateTimeOffset]$record.TimeUtc
                if ($time -ge $StartTimeUtc -and $time -lt $EndTimeUtc -and $seenIds.Add([string]$record.Id)) {
                    $records.Add($record)
                }
            }
            catch { Write-Warning "Skipped a malformed cache line in '$($file.FullName)'." }
        }
    }
    return @($records)
}

function Get-CacheCollectedThrough {
    param([Parameter(Mandatory = $true)][string]$StateDirectory)
    $statePath = Join-Path $StateDirectory 'state.json'
    if (-not (Test-Path -LiteralPath $statePath)) { return $null }
    try {
        $state = ([System.IO.File]::ReadAllText($statePath) | ConvertFrom-Json)
        return [DateTimeOffset](Get-ObjectProperty -InputObject $state -Name 'CollectedThroughUtc')
    }
    catch {
        Write-Warning "The analysis cache state at '$statePath' is invalid. A baseline backfill will be performed."
        return $null
    }
}

function Get-HaversineDistanceKm {
    param(
        [double]$Latitude1,
        [double]$Longitude1,
        [double]$Latitude2,
        [double]$Longitude2
    )

    $earthRadiusKm = 6371.0088
    $toRadians = [math]::PI / 180
    $lat1 = $Latitude1 * $toRadians
    $lat2 = $Latitude2 * $toRadians
    $deltaLat = ($Latitude2 - $Latitude1) * $toRadians
    $deltaLon = ($Longitude2 - $Longitude1) * $toRadians
    $a = [math]::Sin($deltaLat / 2) * [math]::Sin($deltaLat / 2) + [math]::Cos($lat1) * [math]::Cos($lat2) * [math]::Sin($deltaLon / 2) * [math]::Sin($deltaLon / 2)
    return $earthRadiusKm * 2 * [math]::Atan2([math]::Sqrt($a), [math]::Sqrt(1 - $a))
}

function Get-SignInAnalysis {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$Records,
        [Parameter(Mandatory = $true)][DateTimeOffset]$ReportStartUtc,
        [Parameter(Mandatory = $true)][DateTimeOffset]$ReportEndUtc,
        [ValidateRange(1, 1000)][int]$MinimumUserBaselineEvents = 3,
        [ValidateRange(2, 1000)][int]$PasswordSprayDistinctUsers = 5,
        [ValidateRange(2, 10000)][int]$FailureBurstThreshold = 10,
        [ValidateRange(100, 5000)][int]$ImpossibleTravelSpeedKph = 900,
        [ValidateRange(50, 20000)][int]$ImpossibleTravelMinimumKm = 500,
        [string[]]$KnownCountries = @()
    )

    $baseline = [System.Collections.Generic.List[object]]::new()
    $current = [System.Collections.Generic.List[object]]::new()
    foreach ($record in $Records) {
        $time = [DateTimeOffset]$record.TimeUtc
        if ($time -lt $ReportStartUtc) { $baseline.Add($record) }
        elseif ($time -lt $ReportEndUtc) { $current.Add($record) }
    }

    $knownCountrySet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($country in $KnownCountries) { if (-not [string]::IsNullOrWhiteSpace($country)) { [void]$knownCountrySet.Add($country.Trim()) } }

    $userBaseline = @{}
    $globalCountryCounts = @{}
    $lastSuccess = @{}
    foreach ($record in $baseline) {
        $actorKey = ([string]$record.Actor).ToLowerInvariant()
        if (-not $userBaseline.ContainsKey($actorKey)) {
            $userBaseline[$actorKey] = @{
                Count     = 0
                Countries = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                Cities    = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                IPs       = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            }
        }
        $entry = $userBaseline[$actorKey]
        $entry.Count++
        if (-not [string]::IsNullOrWhiteSpace([string]$record.Country)) { [void]$entry.Countries.Add([string]$record.Country) }
        $cityKey = "$($record.Country)|$($record.State)|$($record.City)"
        if ($cityKey -ne '||') { [void]$entry.Cities.Add($cityKey) }
        if (-not [string]::IsNullOrWhiteSpace([string]$record.IPAddress)) { [void]$entry.IPs.Add([string]$record.IPAddress) }
        if (-not [string]::IsNullOrWhiteSpace([string]$record.Country)) {
            $countryKey = ([string]$record.Country).ToUpperInvariant()
            if (-not $globalCountryCounts.ContainsKey($countryKey)) { $globalCountryCounts[$countryKey] = 0 }
            $globalCountryCounts[$countryKey]++
        }
        if ([bool]$record.IsSuccess -and $null -ne $record.Latitude -and $null -ne $record.Longitude) {
            if (-not $lastSuccess.ContainsKey($actorKey) -or ([DateTimeOffset]$record.TimeUtc) -gt ([DateTimeOffset]$lastSuccess[$actorKey].TimeUtc)) {
                $lastSuccess[$actorKey] = $record
            }
        }
    }

    $findings = [System.Collections.Generic.List[object]]::new()
    $locationAnomalies = @{}
    $severityRank = @{ Critical = 4; High = 3; Medium = 2; Low = 1; Informational = 0 }

    foreach ($record in $current) {
        $actorKey = ([string]$record.Actor).ToLowerInvariant()
        if ($record.ActorType -eq 'User' -and $userBaseline.ContainsKey($actorKey)) {
            $entry = $userBaseline[$actorKey]
            $country = [string]$record.Country
            $cityKey = "$($record.Country)|$($record.State)|$($record.City)"
            $isNewCountry = -not [string]::IsNullOrWhiteSpace($country) -and -not $entry.Countries.Contains($country)
            $isNewCity = $cityKey -ne '||' -and -not $entry.Cities.Contains($cityKey)
            $isKnownCountry = $knownCountrySet.Count -gt 0 -and $knownCountrySet.Contains($country)
            if ($entry.Count -ge $MinimumUserBaselineEvents -and ($isNewCountry -or $isNewCity) -and -not $isKnownCountry) {
                $key = "$actorKey|$cityKey"
                if (-not $locationAnomalies.ContainsKey($key)) {
                    $locationAnomalies[$key] = [pscustomobject]@{
                        Actor       = $record.Actor
                        Location    = (@($record.City, $record.State, $record.Country) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ', '
                        FirstSeenUtc = $record.TimeUtc
                        LastSeenUtc  = $record.TimeUtc
                        Count       = 0
                        IPAddresses = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                        IsNewCountry = $isNewCountry
                        BaselineEvents = $entry.Count
                    }
                }
                $anomaly = $locationAnomalies[$key]
                $anomaly.Count++
                if (([DateTimeOffset]$record.TimeUtc) -lt ([DateTimeOffset]$anomaly.FirstSeenUtc)) { $anomaly.FirstSeenUtc = $record.TimeUtc }
                if (([DateTimeOffset]$record.TimeUtc) -gt ([DateTimeOffset]$anomaly.LastSeenUtc)) { $anomaly.LastSeenUtc = $record.TimeUtc }
                if (-not [string]::IsNullOrWhiteSpace([string]$record.IPAddress)) { [void]$anomaly.IPAddresses.Add([string]$record.IPAddress) }
            }
        }
    }

    foreach ($anomaly in $locationAnomalies.Values) {
        $severity = if ($anomaly.IsNewCountry) { 'High' } else { 'Medium' }
        $kind = if ($anomaly.IsNewCountry) { 'new country' } else { 'new city' }
        $findings.Add([pscustomobject]@{
            Severity = $severity
            Rank     = $severityRank[$severity]
            Category = 'Location'
            Summary  = "$($anomaly.Actor) signed in from a ${kind}: $($anomaly.Location)"
            Evidence = "$($anomaly.Count) event(s), IP(s): $(@($anomaly.IPAddresses) -join ', '); baseline: $($anomaly.BaselineEvents) events"
            TimeUtc  = $anomaly.LastSeenUtc
            Actor    = $anomaly.Actor
            IPAddress = @($anomaly.IPAddresses) -join ', '
        })
    }

    $failureByIp = @{}
    $failureByActor = @{}
    foreach ($record in $current) {
        if ([bool]$record.IsSuccess) { continue }
        $ip = [string]$record.IPAddress
        if ([string]::IsNullOrWhiteSpace($ip)) { $ip = '(no IP)' }
        if (-not $failureByIp.ContainsKey($ip)) {
            $failureByIp[$ip] = @{ Count = 0; Actors = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase); Records = [System.Collections.Generic.List[object]]::new() }
        }
        $failureByIp[$ip].Count++
        [void]$failureByIp[$ip].Actors.Add([string]$record.Actor)
        $failureByIp[$ip].Records.Add($record)

        $actorKey = ([string]$record.Actor).ToLowerInvariant()
        if (-not $failureByActor.ContainsKey($actorKey)) { $failureByActor[$actorKey] = [System.Collections.Generic.List[object]]::new() }
        $failureByActor[$actorKey].Add($record)
    }

    foreach ($ip in $failureByIp.Keys) {
        $entry = $failureByIp[$ip]
        if ($entry.Actors.Count -ge $PasswordSprayDistinctUsers) {
            $latest = $entry.Records | Sort-Object TimeUtc -Descending | Select-Object -First 1
            $findings.Add([pscustomobject]@{
                Severity = 'High'; Rank = 3; Category = 'Password spray';
                Summary = "Possible password spray from $ip against $($entry.Actors.Count) distinct actors"
                Evidence = "$($entry.Count) failed sign-ins; actors: $(@($entry.Actors | Select-Object -First 15) -join ', ')"
                TimeUtc = $latest.TimeUtc; Actor = "$($entry.Actors.Count) actors"; IPAddress = $ip
            })
        }
    }

    foreach ($actorKey in $failureByActor.Keys) {
        $actorFailures = $failureByActor[$actorKey]
        if ($actorFailures.Count -ge $FailureBurstThreshold) {
            $latest = $actorFailures | Sort-Object TimeUtc -Descending | Select-Object -First 1
            $distinctIps = @($actorFailures | Select-Object -ExpandProperty IPAddress -Unique)
            $findings.Add([pscustomobject]@{
                Severity = 'Medium'; Rank = 2; Category = 'Failure burst';
                Summary = "$($latest.Actor) had $($actorFailures.Count) failed sign-ins"
                Evidence = "$($distinctIps.Count) distinct IP(s): $($distinctIps -join ', ')"
                TimeUtc = $latest.TimeUtc; Actor = $latest.Actor; IPAddress = $distinctIps -join ', '
            })
        }
    }

    $deniedPolicies = @{}
    $policyResults = @{}
    foreach ($record in $current) {
        foreach ($policy in @($record.Policies)) {
            $policyName = [string]$policy.DisplayName
            $result = [string]$policy.Result
            $policyKey = "$policyName|$result"
            if (-not $policyResults.ContainsKey($policyKey)) {
                $policyResults[$policyKey] = [pscustomobject]@{
                    Policy = $policyName; Result = $result; Count = 0
                    GrantControls = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    SessionControls = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    Actors = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                }
            }
            $aggregate = $policyResults[$policyKey]
            $aggregate.Count++
            [void]$aggregate.Actors.Add([string]$record.Actor)
            foreach ($control in @($policy.EnforcedGrantControls)) { [void]$aggregate.GrantControls.Add([string]$control) }
            foreach ($control in @($policy.EnforcedSessionControls)) { [void]$aggregate.SessionControls.Add([string]$control) }
            if ($result -eq 'failure') {
                if (-not $deniedPolicies.ContainsKey($policyName)) { $deniedPolicies[$policyName] = [System.Collections.Generic.List[object]]::new() }
                $deniedPolicies[$policyName].Add($record)
            }
        }
    }
    foreach ($policyName in $deniedPolicies.Keys) {
        $items = $deniedPolicies[$policyName]
        $latest = $items | Sort-Object TimeUtc -Descending | Select-Object -First 1
        $actors = @($items | Select-Object -ExpandProperty Actor -Unique)
        $findings.Add([pscustomobject]@{
            Severity = 'High'; Rank = 3; Category = 'Conditional Access';
            Summary = "Conditional Access policy denied $($items.Count) sign-in(s): $policyName"
            Evidence = "Actor(s): $($actors -join ', ')"
            TimeUtc = $latest.TimeUtc; Actor = $actors -join ', '; IPAddress = ''
        })
    }

    $legacyClients = @('exchange activesync', 'imap', 'mapi', 'smtp', 'pop', 'other clients')
    $legacySuccesses = @($current | Where-Object { $_.ActorType -eq 'User' -and $_.IsSuccess -and $legacyClients -contains ([string]$_.ClientAppUsed).ToLowerInvariant() })
    if ($legacySuccesses.Count -gt 0) {
        $actors = @($legacySuccesses | Select-Object -ExpandProperty Actor -Unique)
        $latest = $legacySuccesses | Sort-Object TimeUtc -Descending | Select-Object -First 1
        $findings.Add([pscustomobject]@{
            Severity = 'Medium'; Rank = 2; Category = 'Legacy authentication';
            Summary = "$($legacySuccesses.Count) successful legacy-authentication sign-in(s)"
            Evidence = "Actor(s): $($actors -join ', ')"
            TimeUtc = $latest.TimeUtc; Actor = $actors -join ', '; IPAddress = ''
        })
    }

    foreach ($record in $current) {
        $risk = ([string]$record.RiskLevel).ToLowerInvariant()
        $riskDuring = ([string]$record.RiskLevelDuringSignIn).ToLowerInvariant()
        $riskState = ([string]$record.RiskState).ToLowerInvariant()
        if ($risk -in @('medium', 'high') -or $riskDuring -in @('medium', 'high') -or $riskState -in @('atrisk', 'confirmedcompromised')) {
            $severity = if ($risk -eq 'high' -or $riskDuring -eq 'high' -or $riskState -eq 'confirmedcompromised') { 'Critical' } else { 'High' }
            $riskSignals = [System.Collections.Generic.List[string]]::new()
            if ($risk -in @('medium', 'high')) { $riskSignals.Add("$risk aggregated risk") }
            if ($riskDuring -in @('medium', 'high')) { $riskSignals.Add("$riskDuring risk during sign-in") }
            if ($riskState -in @('atrisk', 'confirmedcompromised')) { $riskSignals.Add("risk state $($record.RiskState)") }
            $riskDetections = @($record.RiskEventTypes | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
            $riskDetectionText = if ($riskDetections.Count -gt 0) { $riskDetections -join ', ' } else { 'none reported' }
            $findings.Add([pscustomobject]@{
                Severity = $severity; Rank = $severityRank[$severity]; Category = 'Identity risk';
                Summary = "$($record.Actor) had $($riskSignals -join ' and ')"
                Evidence = "Risk during sign-in: $($record.RiskLevelDuringSignIn); aggregated risk: $($record.RiskLevel); state: $($record.RiskState); detail: $($record.RiskDetail); detections: $riskDetectionText"
                TimeUtc = $record.TimeUtc; Actor = $record.Actor; IPAddress = $record.IPAddress
            })
        }
    }

    $successesByActor = $current | Where-Object { $_.IsSuccess -and $null -ne $_.Latitude -and $null -ne $_.Longitude } | Group-Object { ([string]$_.Actor).ToLowerInvariant() }
    foreach ($group in $successesByActor) {
        $prior = if ($lastSuccess.ContainsKey($group.Name)) { $lastSuccess[$group.Name] } else { $null }
        foreach ($record in $group.Group | Sort-Object TimeUtc) {
            if ($null -ne $prior) {
                $hours = (([DateTimeOffset]$record.TimeUtc) - ([DateTimeOffset]$prior.TimeUtc)).TotalHours
                if ($hours -gt 0.05 -and $hours -le 24) {
                    $distance = Get-HaversineDistanceKm -Latitude1 ([double]$prior.Latitude) -Longitude1 ([double]$prior.Longitude) -Latitude2 ([double]$record.Latitude) -Longitude2 ([double]$record.Longitude)
                    $speed = $distance / $hours
                    if ($distance -ge $ImpossibleTravelMinimumKm -and $speed -ge $ImpossibleTravelSpeedKph) {
                        $from = (@($prior.City, $prior.State, $prior.Country) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ', '
                        $to = (@($record.City, $record.State, $record.Country) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ', '
                        $findings.Add([pscustomobject]@{
                            Severity = 'High'; Rank = 3; Category = 'Potential impossible travel';
                            Summary = "$($record.Actor) moved approximately $([math]::Round($distance)) km in $([math]::Round($hours, 1)) hours"
                            Evidence = "$from to $to (~$([math]::Round($speed)) km/h). VPNs and mobile egress can cause false positives."
                            TimeUtc = $record.TimeUtc; Actor = $record.Actor; IPAddress = $record.IPAddress
                        })
                    }
                }
            }
            $prior = $record
        }
    }

    $failures = @($current | Where-Object { -not $_.IsSuccess })
    $successes = @($current | Where-Object { $_.IsSuccess })
    $caDenials = @($current | Where-Object { ([string]$_.ConditionalAccessStatus).ToLowerInvariant() -eq 'failure' })
    $risky = @($current | Where-Object { ([string]$_.RiskLevel).ToLowerInvariant() -in @('low', 'medium', 'high') -or ([string]$_.RiskLevelDuringSignIn).ToLowerInvariant() -in @('low', 'medium', 'high') })
    $failureReasons = @($failures | Group-Object { "$($_.ErrorCode)|$($_.FailureReason)|$($_.AdditionalDetails)" } | ForEach-Object {
        $sample = $_.Group[0]
        [pscustomobject]@{ Count = $_.Count; ErrorCode = $sample.ErrorCode; FailureReason = $sample.FailureReason; AdditionalDetails = $sample.AdditionalDetails }
    } | Sort-Object Count -Descending)

    $locationRows = @($locationAnomalies.Values | ForEach-Object {
        [pscustomobject]@{
            Actor = $_.Actor; Location = $_.Location; Count = $_.Count
            IPAddresses = @($_.IPAddresses) -join ', '; FirstSeenUtc = $_.FirstSeenUtc; LastSeenUtc = $_.LastSeenUtc
            Type = if ($_.IsNewCountry) { 'New country' } else { 'New city' }
        }
    } | Sort-Object Count -Descending)

    $policyRows = @($policyResults.Values | ForEach-Object {
        [pscustomobject]@{
            Policy = $_.Policy; Result = $_.Result; Count = $_.Count
            GrantControls = @($_.GrantControls) -join ', '; SessionControls = @($_.SessionControls) -join ', '
            Actors = @($_.Actors) -join ', '
        }
    } | Sort-Object @{ Expression = { if ($_.Result -eq 'failure') { 0 } elseif ($_.Result -like 'reportOnlyFailure*') { 1 } elseif ($_.Result -eq 'success') { 2 } else { 3 } } }, Count -Descending)

    $warnings = [System.Collections.Generic.List[string]]::new()
    if ($baseline.Count -eq 0) { $warnings.Add('No baseline events were available. New-location and travel findings are limited on this run.') }
    elseif ($baseline.Count -lt 100) { $warnings.Add("Only $($baseline.Count) baseline events were available; rarity findings may be noisy.") }
    $caPresentCount = @($current | Where-Object { $_.CaPolicyDataPresent }).Count
    if ($current.Count -gt 0 -and $caPresentCount -eq 0) { $warnings.Add('Applied Conditional Access policy details were absent. Verify Policy.Read.ConditionalAccess (or Policy.Read.All) and an eligible Entra role.') }
    if (@($current | Where-Object { $_.RiskLevel -eq 'hidden' -or $_.RiskLevelDuringSignIn -eq 'hidden' }).Count -gt 0) { $warnings.Add('Some identity-risk fields are hidden because the tenant or account does not have the required Entra ID Protection licensing/access.') }

    $orderedFindings = @($findings | Sort-Object @{ Expression = { $_.Rank }; Descending = $true }, @{ Expression = { $_.TimeUtc }; Descending = $true })
    return [pscustomobject]@{
        BaselineCount          = $baseline.Count
        CurrentCount           = $current.Count
        SuccessCount           = $successes.Count
        FailureCount           = $failures.Count
        ConditionalAccessDenials = $caDenials.Count
        RiskyCount             = $risky.Count
        Findings               = $orderedFindings
        FailureReasons         = $failureReasons
        ConditionalAccessPolicies = $policyRows
        LocationAnomalies      = $locationRows
        Failures               = @($failures | Sort-Object TimeUtc -Descending)
        CurrentRecords         = @($current | Sort-Object TimeUtc -Descending)
        Warnings               = @($warnings)
        ReportStartUtc         = $ReportStartUtc.ToUniversalTime().ToString('o')
        ReportEndUtc           = $ReportEndUtc.ToUniversalTime().ToString('o')
    }
}

function ConvertTo-HtmlEncoded {
    param([AllowNull()]$Value)
    if ($null -eq $Value) { return '' }
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function ConvertTo-DisplayTime {
    param(
        [AllowNull()]$Value,
        [Parameter(Mandatory = $true)][TimeZoneInfo]$TimeZone
    )
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return '' }
    $dto = ([DateTimeOffset]$Value).ToUniversalTime()
    return [TimeZoneInfo]::ConvertTime($dto, $TimeZone).ToString('yyyy-MM-dd HH:mm:ss')
}

function Get-PoliciesDisplay {
    param([AllowNull()]$Policies)
    $values = foreach ($policy in @($Policies)) {
        if ($null -eq $policy) { continue }
        "$($policy.DisplayName) [$($policy.Result)]"
    }
    return $values -join '; '
}

function New-SignInHtmlReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Analysis,
        [Parameter(Mandatory = $true)][string]$OutputPath,
        [string]$TenantName = 'Microsoft 365 tenant',
        [string]$TenantId = '',
        [string]$BrandName = 'Nexlinks',
        [string]$BrandUrl = 'https://www.nexlinks.net/',
        [string]$DisplayTimeZone = 'Local',
        [ValidateRange(10, 5000)][int]$MaximumDetailRows = 500,
        [string]$RawDataRelativePath = 'raw/signins.jsonl'
    )

    $timeZone = if ($DisplayTimeZone -eq 'Local') { [TimeZoneInfo]::Local } else { [TimeZoneInfo]::FindSystemTimeZoneById($DisplayTimeZone) }
    $brandUri = $null
    if (-not [uri]::TryCreate($BrandUrl, [UriKind]::Absolute, [ref]$brandUri) -or $brandUri.Scheme -notin @('http', 'https')) {
        throw "BrandUrl must be an absolute HTTP or HTTPS URL. Received '$BrandUrl'."
    }
    $brandLinkLabel = $brandUri.Host -replace '^www\.', ''
    $encodedBrandName = ConvertTo-HtmlEncoded $BrandName
    $encodedBrandUrl = ConvertTo-HtmlEncoded $brandUri.AbsoluteUri
    $encodedBrandLinkLabel = ConvertTo-HtmlEncoded $brandLinkLabel
    $encodedTenantName = ConvertTo-HtmlEncoded $TenantName
    $encodedTenantId = if ([string]::IsNullOrWhiteSpace($TenantId)) { 'Unavailable' } else { ConvertTo-HtmlEncoded $TenantId }
    $logoPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'assets\nexlinks-logo.png'
    if (-not (Test-Path -LiteralPath $logoPath)) { throw "The report logo asset is missing: $logoPath" }
    $logoDataUri = 'data:image/png;base64,' + [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($logoPath))
    $failureRate = if ($Analysis.CurrentCount -gt 0) { [math]::Round(($Analysis.FailureCount / $Analysis.CurrentCount) * 100, 1) } else { 0 }
    $generated = ConvertTo-DisplayTime -Value ([DateTimeOffset]::UtcNow) -TimeZone $timeZone
    $reportStart = ConvertTo-DisplayTime -Value $Analysis.ReportStartUtc -TimeZone $timeZone
    $reportEnd = ConvertTo-DisplayTime -Value $Analysis.ReportEndUtc -TimeZone $timeZone
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('<!doctype html>')
    [void]$sb.AppendLine('<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">')
    [void]$sb.AppendLine('<title>M365 Sign-in Security Daily</title>')
    [void]$sb.AppendLine(@'
<style>
:root{--bg:#f3f6f9;--panel:#fff;--ink:#17212b;--muted:#5f6b76;--line:#d9e1e8;--brand:#0b5cab;--cyan:#72d8ff;--critical:#8b1e2d;--high:#c2410c;--medium:#b7791f;--low:#356a91;--ok:#157347}*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:14px/1.45 "Segoe UI",Arial,sans-serif}header{background:linear-gradient(120deg,#083d6d,#0b5cab 58%,#1573bd);color:#fff;padding:20px max(24px,calc((100vw - 1440px)/2)) 22px}.header-top{display:flex;align-items:center;justify-content:space-between;gap:24px;margin-bottom:17px;padding-bottom:13px;border-bottom:1px solid #ffffff35}.report-brand{display:inline-flex;align-items:center;color:#fff;text-decoration:none}.report-brand img{display:block;width:173px;max-width:42vw;height:auto;border-radius:4px;box-shadow:0 1px 5px #001a3040}.brand-url{color:#e9f7ff;text-decoration:none;font-weight:600}.brand-url:hover{text-decoration:underline}header h1{margin:0 0 5px;font-size:27px;letter-spacing:.1px}header p{margin:3px 0;color:#e8f2fb}.container{max-width:1440px;margin:0 auto;padding:22px}.cards{display:grid;grid-template-columns:repeat(7,minmax(120px,1fr));gap:12px;margin-bottom:18px}.card{background:var(--panel);border:1px solid var(--line);border-radius:9px;padding:14px;box-shadow:0 1px 2px #1e293b10}.card .label{color:var(--muted);font-size:12px;text-transform:uppercase;letter-spacing:.45px}.card .value{font-size:25px;font-weight:700;margin-top:3px}.card.bad .value{color:var(--high)}.card.good .value{color:var(--ok)}section{background:var(--panel);border:1px solid var(--line);border-radius:9px;margin:0 0 17px;overflow:hidden;box-shadow:0 1px 2px #1e293b0d}section h2{font-size:17px;margin:0;padding:14px 16px;border-bottom:1px solid var(--line);background:#fbfcfd}section .body{padding:14px 16px}.notice{border-left:4px solid var(--medium);background:#fff8e6;padding:10px 12px;margin:0 0 10px;border-radius:4px}.notice.danger{border-color:var(--critical);background:#fff1f2}.tools{display:flex;gap:9px;align-items:center;margin-bottom:11px}.tools input{min-width:300px;max-width:520px;width:45%;border:1px solid #b8c4ce;border-radius:6px;padding:8px 10px;font:inherit}.table-wrap{overflow:auto;max-height:610px}table{border-collapse:collapse;width:100%;font-size:12.5px}th,td{text-align:left;vertical-align:top;padding:8px 9px;border-bottom:1px solid #e6ebef}th{position:sticky;top:0;background:#eef3f7;color:#34424f;z-index:1;white-space:nowrap}tr:hover td{background:#f8fbfd}.sev{display:inline-block;color:#fff;padding:2px 7px;border-radius:999px;font-weight:700;font-size:11px}.sev-critical{background:var(--critical)}.sev-high{background:var(--high)}.sev-medium{background:var(--medium)}.sev-low{background:var(--low)}.muted{color:var(--muted)}.mono{font-family:Consolas,"SFMono-Regular",monospace;font-size:12px}.empty{color:var(--muted);padding:8px 0}.result-failure{color:var(--critical);font-weight:700}.result-reportonlyfailure{color:var(--medium);font-weight:700}.result-success{color:var(--ok)}details{margin:10px 0}summary{cursor:pointer;color:var(--brand);font-weight:600}footer{color:var(--muted);padding:3px 2px 24px}footer a{font-weight:600}a{color:var(--brand)}@media(max-width:1050px){.cards{grid-template-columns:repeat(3,1fr)}}@media(max-width:620px){.container{padding:12px}.cards{grid-template-columns:repeat(2,1fr)}.header-top{align-items:flex-start;flex-direction:column;gap:7px}.tools input{width:100%;min-width:0}}
</style></head><body>
'@)
    [void]$sb.AppendLine("<header><div class='header-top'><a class='report-brand' href='$encodedBrandUrl' target='_blank' rel='noopener noreferrer' aria-label='$encodedBrandName website'><img src='$logoDataUri' alt='$encodedBrandName'></a><a class='brand-url' href='$encodedBrandUrl' target='_blank' rel='noopener noreferrer'>$encodedBrandLinkLabel &#8599;</a></div><h1>Microsoft 365 sign-in security daily</h1><p><strong>Tenant:</strong> $encodedTenantName &middot; <strong>Tenant ID:</strong> <span class='mono'>$encodedTenantId</span></p><p>$reportStart to $reportEnd ($([System.Net.WebUtility]::HtmlEncode($timeZone.DisplayName)))</p><p>Generated $generated &middot; Beta v0.0.1</p></header><main class='container'>")
    [void]$sb.AppendLine("<div class='cards'><div class='card'><div class='label'>Sign-ins</div><div class='value'>$($Analysis.CurrentCount)</div></div><div class='card good'><div class='label'>Succeeded</div><div class='value'>$($Analysis.SuccessCount)</div></div><div class='card bad'><div class='label'>Failed</div><div class='value'>$($Analysis.FailureCount)</div></div><div class='card bad'><div class='label'>Failure rate</div><div class='value'>$failureRate%</div></div><div class='card bad'><div class='label'>CA denied</div><div class='value'>$($Analysis.ConditionalAccessDenials)</div></div><div class='card bad'><div class='label'>Risk flagged</div><div class='value'>$($Analysis.RiskyCount)</div></div><div class='card'><div class='label'>Findings</div><div class='value'>$(@($Analysis.Findings).Count)</div></div></div>")

    if (@($Analysis.Warnings).Count -gt 0) {
        [void]$sb.AppendLine("<section><h2>Data-quality notes</h2><div class='body'>")
        foreach ($warning in $Analysis.Warnings) { [void]$sb.AppendLine("<div class='notice'>$(ConvertTo-HtmlEncoded $warning)</div>") }
        [void]$sb.AppendLine('</div></section>')
    }

    [void]$sb.AppendLine("<section><h2>Priority findings</h2><div class='body'><div class='tools'><input class='filter' data-target='findings' placeholder='Filter findings...'></div><div class='table-wrap'><table id='findings'><thead><tr><th>Severity</th><th>Category</th><th>Latest ($([System.Net.WebUtility]::HtmlEncode($timeZone.StandardName)))</th><th>Summary</th><th>Evidence</th></tr></thead><tbody>")
    if (@($Analysis.Findings).Count -eq 0) { [void]$sb.AppendLine("<tr><td colspan='5' class='empty'>No priority findings met the configured thresholds.</td></tr>") }
    foreach ($finding in @($Analysis.Findings | Select-Object -First $MaximumDetailRows)) {
        $sev = ([string]$finding.Severity).ToLowerInvariant()
        [void]$sb.AppendLine("<tr><td><span class='sev sev-$sev'>$(ConvertTo-HtmlEncoded $finding.Severity)</span></td><td>$(ConvertTo-HtmlEncoded $finding.Category)</td><td>$(ConvertTo-HtmlEncoded (ConvertTo-DisplayTime $finding.TimeUtc $timeZone))</td><td>$(ConvertTo-HtmlEncoded $finding.Summary)</td><td>$(ConvertTo-HtmlEncoded $finding.Evidence)</td></tr>")
    }
    [void]$sb.AppendLine('</tbody></table></div></div></section>')

    [void]$sb.AppendLine("<section><h2>Top failure reasons</h2><div class='body'><div class='table-wrap'><table><thead><tr><th>Count</th><th>Error code</th><th>Failure reason</th><th>Additional details</th></tr></thead><tbody>")
    if (@($Analysis.FailureReasons).Count -eq 0) { [void]$sb.AppendLine("<tr><td colspan='4' class='empty'>No failed sign-ins in the report window.</td></tr>") }
    foreach ($row in @($Analysis.FailureReasons | Select-Object -First 50)) {
        [void]$sb.AppendLine("<tr><td>$($row.Count)</td><td class='mono'>$(ConvertTo-HtmlEncoded $row.ErrorCode)</td><td>$(ConvertTo-HtmlEncoded $row.FailureReason)</td><td>$(ConvertTo-HtmlEncoded $row.AdditionalDetails)</td></tr>")
    }
    [void]$sb.AppendLine('</tbody></table></div></div></section>')

    [void]$sb.AppendLine("<section><h2>Conditional Access policy outcomes</h2><div class='body'><div class='tools'><input class='filter' data-target='ca-policies' placeholder='Filter policies, results, actors...'></div><div class='table-wrap'><table id='ca-policies'><thead><tr><th>Policy</th><th>Result</th><th>Count</th><th>Grant controls</th><th>Session controls</th><th>Actors</th></tr></thead><tbody>")
    if (@($Analysis.ConditionalAccessPolicies).Count -eq 0) { [void]$sb.AppendLine("<tr><td colspan='6' class='empty'>No applied policy details were returned.</td></tr>") }
    foreach ($row in @($Analysis.ConditionalAccessPolicies | Select-Object -First $MaximumDetailRows)) {
        $resultClass = 'result-' + (([string]$row.Result).ToLowerInvariant() -replace '[^a-z]', '')
        [void]$sb.AppendLine("<tr><td>$(ConvertTo-HtmlEncoded $row.Policy)</td><td class='$resultClass'>$(ConvertTo-HtmlEncoded $row.Result)</td><td>$($row.Count)</td><td>$(ConvertTo-HtmlEncoded $row.GrantControls)</td><td>$(ConvertTo-HtmlEncoded $row.SessionControls)</td><td>$(ConvertTo-HtmlEncoded $row.Actors)</td></tr>")
    }
    [void]$sb.AppendLine('</tbody></table></div></div></section>')

    [void]$sb.AppendLine("<section><h2>Unusual locations</h2><div class='body'><div class='table-wrap'><table><thead><tr><th>Actor</th><th>Type</th><th>Location</th><th>Count</th><th>IP addresses</th><th>First seen</th><th>Last seen</th></tr></thead><tbody>")
    if (@($Analysis.LocationAnomalies).Count -eq 0) { [void]$sb.AppendLine("<tr><td colspan='7' class='empty'>No new user locations met the configured baseline threshold.</td></tr>") }
    foreach ($row in @($Analysis.LocationAnomalies | Select-Object -First $MaximumDetailRows)) {
        [void]$sb.AppendLine("<tr><td>$(ConvertTo-HtmlEncoded $row.Actor)</td><td>$(ConvertTo-HtmlEncoded $row.Type)</td><td>$(ConvertTo-HtmlEncoded $row.Location)</td><td>$($row.Count)</td><td class='mono'>$(ConvertTo-HtmlEncoded $row.IPAddresses)</td><td>$(ConvertTo-HtmlEncoded (ConvertTo-DisplayTime $row.FirstSeenUtc $timeZone))</td><td>$(ConvertTo-HtmlEncoded (ConvertTo-DisplayTime $row.LastSeenUtc $timeZone))</td></tr>")
    }
    [void]$sb.AppendLine('</tbody></table></div></div></section>')

    [void]$sb.AppendLine("<section><h2>Failure detail</h2><div class='body'><div class='tools'><input class='filter' data-target='failures' placeholder='Filter actor, IP, application, reason, policy...'></div><div class='table-wrap'><table id='failures'><thead><tr><th>Time ($([System.Net.WebUtility]::HtmlEncode($timeZone.StandardName)))</th><th>Actor</th><th>Type</th><th>Application / resource</th><th>Source</th><th>Error / reason</th><th>Conditional Access</th><th>Risk</th></tr></thead><tbody>")
    if (@($Analysis.Failures).Count -eq 0) { [void]$sb.AppendLine("<tr><td colspan='8' class='empty'>No failed sign-ins in the report window.</td></tr>") }
    foreach ($row in @($Analysis.Failures | Select-Object -First $MaximumDetailRows)) {
        $source = (@($row.City, $row.State, $row.Country) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ', '
        if (-not [string]::IsNullOrWhiteSpace($source)) { $source += ' / ' }
        $source += [string]$row.IPAddress
        $reason = "$($row.ErrorCode): $($row.FailureReason)"
        if (-not [string]::IsNullOrWhiteSpace([string]$row.AdditionalDetails)) { $reason += " ($($row.AdditionalDetails))" }
        $app = "$($row.AppDisplayName) / $($row.ResourceDisplayName)"
        $risk = "$($row.RiskLevel); $(@($row.RiskEventTypes) -join ', ')"
        [void]$sb.AppendLine("<tr><td>$(ConvertTo-HtmlEncoded (ConvertTo-DisplayTime $row.TimeUtc $timeZone))</td><td>$(ConvertTo-HtmlEncoded $row.Actor)</td><td>$(ConvertTo-HtmlEncoded $row.EventType)</td><td>$(ConvertTo-HtmlEncoded $app)</td><td class='mono'>$(ConvertTo-HtmlEncoded $source)</td><td>$(ConvertTo-HtmlEncoded $reason)</td><td>$(ConvertTo-HtmlEncoded (Get-PoliciesDisplay $row.Policies))</td><td>$(ConvertTo-HtmlEncoded $risk)</td></tr>")
    }
    [void]$sb.AppendLine('</tbody></table></div></div></section>')

    [void]$sb.AppendLine("<section><h2>Review notes</h2><div class='body'><p><strong>Baseline:</strong> $($Analysis.BaselineCount) earlier events were used to establish normal user locations. The report treats new geography, travel velocity, concentrated failures, legacy authentication, Entra risk, and enforced Conditional Access failures as analyst leads - not final incident determinations.</p><p><strong>Raw evidence:</strong> <a href='$(ConvertTo-HtmlEncoded $RawDataRelativePath)'>Open the deduplicated JSONL stream</a>. Exact API response pages and collection metadata are in the same run folder.</p><details><summary>Detection caveats</summary><p>VPNs, mobile carrier egress, cloud proxies, shared NAT, and token refresh behavior can create location and velocity false positives. Report-only Conditional Access failures are displayed but are not counted as enforced denials. Successful events with error code 0 are treated as successful even if individual authentication steps contain expected challenge activity.</p></details></div></section>")
    [void]$sb.AppendLine("<footer><a href='$encodedBrandUrl' target='_blank' rel='noopener noreferrer'>$encodedBrandName &middot; $encodedBrandLinkLabel</a><br>Generated by M365 Sign-in Report beta v0.0.1. Validate high-impact findings in the Microsoft Entra admin center or your SIEM before taking action. $encodedBrandName is not affiliated with Microsoft.</footer></main>")
    [void]$sb.AppendLine(@'
<script>
document.querySelectorAll('.filter').forEach(function(input){input.addEventListener('input',function(){var q=input.value.toLowerCase();var table=document.getElementById(input.dataset.target);table.querySelectorAll('tbody tr').forEach(function(row){row.style.display=row.innerText.toLowerCase().indexOf(q)>=0?'':'none';});});});
</script></body></html>
'@)

    $parent = Split-Path -Parent $OutputPath
    if (-not [string]::IsNullOrWhiteSpace($parent)) { [void](New-Item -ItemType Directory -Force -Path $parent) }
    [System.IO.File]::WriteAllText($OutputPath, $sb.ToString(), [System.Text.UTF8Encoding]::new($false))
    return $OutputPath
}

Export-ModuleMember -Function @(
    'ConvertTo-NormalizedSignIn',
    'Select-ReportableSignIn',
    'Get-GraphSignInEvents',
    'Read-SignInInputFile',
    'Save-NormalizedEventCache',
    'Get-NormalizedEventCache',
    'Get-CacheCollectedThrough',
    'Get-SignInAnalysis',
    'New-SignInHtmlReport'
)
