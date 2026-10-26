$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$t=$null;$e=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'Invoke-IntuneReadinessCollection.ps1'),[ref]$t,[ref]$e)
if($e.Count){throw 'Syntax failure'}
$fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-GraphErrorDiagnostics'},$true)
Invoke-Expression $fn.Extent.Text
$ex=[Exception]::new('Bad Request')
$err=[Management.Automation.ErrorRecord]::new($ex,'GraphFailure',[Management.Automation.ErrorCategory]::InvalidOperation,$null)
$err.ErrorDetails=[Management.Automation.ErrorDetails]::new('{"error":{"code":"BadRequest","message":"Invalid filter","innerError":{"request-id":"test-request"}}}')
$d=Get-GraphErrorDiagnostics -ErrorRecord $err -Method POST -RequestBody @{filter="(PolicyId eq 'test')"}
if($d.graphError.code -ne 'BadRequest' -or $d.graphError.message -ne 'Invalid filter' -or $d.method -ne 'POST'){throw 'Graph response extraction failed'}
if($d.requestBody.filter -ne "(PolicyId eq 'test')"){throw 'Request body lost'}
$err.ErrorDetails=$null
$d=Get-GraphErrorDiagnostics -ErrorRecord $err -Method GET
if(-not $d.bodyUnavailable){throw 'Unavailable body not marked'}
Write-Output 'PASS: Graph error extraction, request body capture, missing body handling, syntax.'
