$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'Invoke-IntuneReadinessCollection.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Syntax check failed'}
$fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-PolicyDeviceReport'},$true)
Invoke-Expression $fn.Extent.Text
$IncludeFullDeviceIdentity=$false
$script:calls=0
function Invoke-GraphGet {
    param($Uri,$Method,$Body)
    if($Method -ne 'POST' -or $Body.filter -ne "(PolicyBaseTypeName eq 'DeviceManagementConfigurationPolicy') and (PolicyId eq 'test-policy')"){throw 'Invalid report request'}
    $script:calls++
    $count=if($Body.skip -eq 0){100}else{1}
    $values=[Collections.Generic.List[object]]::new()
    for($i=0;$i -lt $count;$i++){ $values.Add(@("device-$($Body.skip+$i)",'Private device name',1)) }
    @{Schema=@(@{Column='DeviceId'},@{Column='DeviceName'},@{Column='PolicyStatus'});Values=$values.ToArray();TotalRowCount=101}|ConvertTo-Json -Depth 10 -Compress
}
$rows=@(Invoke-PolicyDeviceReport -Uri 'https://graph.microsoft.com/beta/deviceManagement/reports/getConfigurationPolicyDevicesReport' -PolicyId 'test-policy')
if($rows.Count -ne 101 -or $script:calls -ne 2){throw 'Pagination failed'}
if($rows[0].DeviceId -ne 'device-0' -or $rows[100].DeviceId -ne 'device-100'){throw 'Column mapping failed'}
if($rows[0].PSObject.Properties['DeviceName']){throw 'Privacy filtering failed'}
function Invoke-GraphGet {param($Uri,$Method,$Body) @{Schema=@(@{Column='DeviceId'});Values=@();TotalRowCount=0}}
if(@(Invoke-PolicyDeviceReport -Uri 'test' -PolicyId 'test-policy').Count -ne 0){throw 'Empty report failed'}
function Invoke-GraphGet {param($Uri,$Method,$Body) @{value=@()}}
$rejected=$false
try {Invoke-PolicyDeviceReport -Uri 'test' -PolicyId 'test-policy'}catch{$rejected=$true}
if(-not $rejected){throw 'Malformed response was accepted'}
$m=Get-Content (Join-Path $root 'query-manifest.json') -Raw|ConvertFrom-Json
if(($m.queries|Where-Object id -eq 'enrollment.autopilot').path -match '\?'){throw 'Autopilot query options remain'}
$q=$m.queries|Where-Object id -eq 'configuration.modernDeviceStatuses'
if($q.pathTemplate -ne '/deviceManagement/reports/getConfigurationPolicyDevicesReport' -or $q.responseShape -ne 'report'){throw 'Invalid report manifest'}
Write-Output 'PASS: syntax, report POST/filter, pagination, column mapping, privacy, empty reports, malformed response rejection, corrected manifest.'

