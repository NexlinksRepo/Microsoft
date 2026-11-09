Set-StrictMode -Version Latest

function Install-DefenderGraphAuthenticationModule {
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

    if (-not (Get-Module -ListAvailable -Name $moduleName)) {
        throw "'$moduleName' was installed but is not visible in the current module path. Reopen PowerShell and run the launcher again."
    }
}

function Connect-DefenderGraphSession {
    param(
        [Parameter(Mandatory)][string]$LoginHint,
        [Parameter(Mandatory)][string[]]$Scopes,
        [switch]$UseDeviceCode
    )

    Install-DefenderGraphAuthenticationModule
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

    $requiredScopes = @($Scopes | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    $context = Get-MgContext
    if ($null -ne $context -and [string]$context.Account -ieq $LoginHint) {
        $grantedScopes = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($scope in @($context.Scopes)) {
            [void]$grantedScopes.Add([string]$scope)
        }
        $missingScopes = @($requiredScopes | Where-Object { -not $grantedScopes.Contains($_) })
        if ($missingScopes.Count -eq 0) {
            Write-Host "Reusing the cached Microsoft Graph sign-in for $LoginHint." -ForegroundColor Cyan
            return $context
        }
    }

    $parameters = @{
        Scopes       = $requiredScopes
        ContextScope = 'CurrentUser'
        LoginHint    = $LoginHint
        NoWelcome    = $true
    }
    if ($UseDeviceCode) {
        $parameters.UseDeviceCode = $true
    }

    Connect-MgGraph @parameters | Out-Null
    $context = Get-MgContext
    if ($null -eq $context) {
        throw 'Microsoft Graph authentication did not return a context.'
    }
    if ([string]$context.Account -ine $LoginHint) {
        throw "Microsoft Graph authenticated as '$($context.Account)', but '$LoginHint' was requested. Run Disconnect-MgGraph, then retry with the intended administrator."
    }

    $grantedScopes = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($scope in @($context.Scopes)) {
        [void]$grantedScopes.Add([string]$scope)
    }
    $missingScopes = @($requiredScopes | Where-Object { -not $grantedScopes.Contains($_) })
    if ($missingScopes.Count -gt 0) {
        throw "The Microsoft Graph session is missing required delegated scope(s): $($missingScopes -join ', '). Grant consent, run Disconnect-MgGraph, and retry."
    }

    Write-Host "Microsoft Graph sign-in cached for $LoginHint and available to later seeding or cleanup runs." -ForegroundColor Cyan
    return $context
}
