[CmdletBinding()]
param(
    [string]$TenantId = 'contoso.com',
    [Parameter(Mandatory)][string]$PolicyId,
    [switch]$UseGraphSdkSession,
    [switch]$UseDeviceCode,
    [string]$OutputPath = (Join-Path $PSScriptRoot 'runs\modern-policy-probe.json')
)
$ErrorActionPreference = 'Stop'
Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
if ($UseGraphSdkSession) {
    $context = Get-MgContext
    if (-not $context) { throw 'No Graph session exists. Run without -UseGraphSdkSession to sign in.' }
    if ($TenantId -and $context.TenantId -ne $TenantId) { throw 'Existing session belongs to a different tenant.' }
} else {
    $auth = @{ TenantId=$TenantId; Scopes=@('DeviceManagementConfiguration.Read.All'); ContextScope='Process'; NoWelcome=$true }
    if ($UseDeviceCode) { $auth.UseDeviceCode=$true }
    Connect-MgGraph @auth
}
# Load only the error-capture helper, without running the full collector.
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Invoke-IntuneReadinessCollection.ps1'),[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw 'Collector syntax is invalid.' }
$fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-GraphErrorDiagnostics'},$true)
Invoke-Expression $fn.Extent.Text
$escapedId=$PolicyId.Replace("'","''")
$idFilter="(PolicyId eq '$escapedId')"
$typeFilter="(PolicyBaseTypeName eq 'DeviceManagementConfigurationPolicy') and $idFilter"
$columns=@('IntuneDeviceId','PolicyId','PolicyStatus','PspdpuLastModifiedTimeUtc')
$variants=@(
    @{name='Original';body=@{filter=$idFilter;skip=0;top=5}},
    @{name='PolicyTypeFilter';body=@{filter=$typeFilter;skip=0;top=5}},
    @{name='ExplicitColumns';body=@{filter=$idFilter;select=$columns;skip=0;top=5}},
    @{name='PolicyTypeAndColumns';body=@{filter=$typeFilter;select=$columns;skip=0;top=5}}
)
$uri='https://graph.microsoft.com/beta/deviceManagement/reports/getConfigurationPolicyDevicesReport'
$results=[Collections.Generic.List[object]]::new()
foreach ($variant in $variants) {
    Write-Host ("Testing {0} for policy {1}" -f $variant.name,$PolicyId)
    $result=[ordered]@{ variant=$variant.name; uri=$uri; method='POST'; requestBody=$variant.body }
    try {
        $response=Invoke-MgGraphRequest -Method POST -Uri $uri -Body ($variant.body|ConvertTo-Json -Depth 10 -Compress) -ContentType 'application/json' -OutputType PSObject
        if ($response -is [byte[]]) { $response=[Text.Encoding]::UTF8.GetString($response) }
        if ($response -is [IO.Stream]) {
            $reader=[IO.StreamReader]::new($response)
            try { $response=$reader.ReadToEnd() } finally { $reader.Dispose() }
        }
        if ($response -is [string]) { $response=$response|ConvertFrom-Json }
        if ($response -is [Collections.IDictionary]) { $response=[pscustomobject]$response }
        if (-not $response.PSObject.Properties['Schema'] -or -not $response.PSObject.Properties['Values']) {
            throw 'HTTP request returned, but response was not a Schema/Values report.'
        }
        $result.status='succeeded'
        $result.totalRowCount=$response.TotalRowCount
        $result.returnedRowCount=@($response.Values).Count
        # Save structure/counts only; the full device/user rows are unnecessary for this probe.
        $result.responseSchema=$response.Schema
        Write-Host ("Succeeded; returned {0} row(s)." -f $result.returnedRowCount)
    } catch {
        $result.status='failed'
        $result.message=$_.Exception.Message
        $result.diagnostics=Get-GraphErrorDiagnostics -ErrorRecord $_ -Method POST -RequestBody $variant.body
        Write-Host 'Failed; response details captured.'
    }
    $results.Add($result)
    $parent=Split-Path -Parent $OutputPath
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force|Out-Null }
    [ordered]@{
        policyId=$PolicyId
        tenantId=(Get-MgContext).TenantId
        completedAtUtc=[DateTimeOffset]::UtcNow.ToString('o')
        note='Four request variants, one policy, first page only. No full inventory collected.'
        results=$results.ToArray()
    }|ConvertTo-Json -Depth 100|Set-Content -LiteralPath $OutputPath -Encoding utf8
}
Write-Host ("Probe results saved to {0}" -f [IO.Path]::GetFullPath($OutputPath))

