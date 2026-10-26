$root = Split-Path -Parent $PSScriptRoot
$manifest = Get-Content -LiteralPath (Join-Path $root 'query-manifest.json') -Raw | ConvertFrom-Json
$schema = Get-Content -LiteralPath (Join-Path $root 'intune-readiness.schema.json') -Raw | ConvertFrom-Json
$scriptText = Get-Content -LiteralPath (Join-Path $root 'Invoke-IntuneReadinessCollection.ps1') -Raw

Describe 'Intune Readiness Collector package' {
    It 'has unique query IDs' {
        @($manifest.queries.id | Group-Object | Where-Object Count -gt 1).Count | Should Be 0
    }

    It 'labels every beta query with a reason' {
        @($manifest.queries | Where-Object { $_.apiVersion -eq 'beta' -and [string]::IsNullOrWhiteSpace($_.betaReason) }).Count | Should Be 0
    }

    It 'uses only v1.0 or beta Graph versions' {
        @($manifest.queries.apiVersion | Where-Object { $_ -notin @('v1.0', 'beta') }).Count | Should Be 0
    }

    It 'declares at least one permission for each query' {
        @($manifest.queries | Where-Object { @($_.permissions).Count -eq 0 }).Count | Should Be 0
    }

    It 'keeps scoring null in the schema' {
        $schema.properties.scoring.type | Should Be 'null'
    }

    It 'does not contain RAG threshold logic' {
        $scriptText | Should Not Match '(?i)\b(red|amber|green)\b'
    }

    It 'parses as PowerShell' {
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseInput($scriptText, [ref]$tokens, [ref]$errors)
        @($errors).Count | Should Be 0
    }

    It 'provides a built-in interactive authentication flow' {
        $scriptText | Should Match 'Connect-MgGraph'
        $scriptText | Should Match "DefaultParameterSetName = 'Interactive'"
        $scriptText | Should Match 'UseDeviceCode'
    }

    It 'returns paged records without wrapping them in a nested Object array' {
        $scriptText | Should Not Match 'return\s+,[ ]*\$items\.ToArray\(\)'
        $scriptText | Should Match 'return\s+\$items\.ToArray\(\)'
    }

    It 'provides category-level progress with a quiet option' {
        $scriptText | Should Match 'Extracting compliance information'
        $scriptText | Should Match 'Extracting Endpoint Security and Settings Catalog information'
        $scriptText | Should Match '\[switch\]\$Quiet'
        $scriptText | Should Match 'Collection complete'
    }
}
