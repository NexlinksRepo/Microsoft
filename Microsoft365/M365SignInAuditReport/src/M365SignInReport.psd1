@{
    RootModule        = 'M365SignInReport.psm1'
    ModuleVersion     = '0.0.1'
    GUID              = 'b6d4b68b-cc2f-4d56-9eb9-852982e43510'
    Author            = 'M365 Sign-in Report contributors'
    CompanyName       = 'Community'
    Copyright         = '(c) 2026. All rights reserved.'
    Description       = 'Collects, analyzes, and reports Microsoft Entra sign-in activity for daily analyst review.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
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
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Prerelease = 'beta'
            Tags       = @('Microsoft365', 'Entra', 'SignInLogs', 'ConditionalAccess', 'Security')
        }
    }
}
