#requires -Version 7.2

Set-StrictMode -Version Latest

function Get-AgentDeclaredResourceAccess {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Definition)

    $permissionMap = @{
        'User.Read'           = @{ id = 'e1fe6dd8-ba31-4d61-89e7-88639da4683d'; type = 'Scope' }
        'Files.Read'          = @{ id = '10465720-29dd-4523-a11a-6a75c743c9d9'; type = 'Scope' }
        'Files.ReadWrite'     = @{ id = '863451e7-0667-486c-a5d6-d135439485f0'; type = 'Scope' }
        'Mail.Read'           = @{ id = '570282fd-fa5c-430d-a7fd-fc8dc98a9dca'; type = 'Scope' }
        'Mail.ReadWrite'      = @{ id = '024d486e-b451-40bb-833d-3e66d98c5c73'; type = 'Scope' }
        'Calendars.ReadWrite' = @{ id = '1ec239c2-d7c9-4623-a91a-a9775856bb36'; type = 'Scope' }
        'User.Read.All'       = @{ id = 'df021288-bdef-4463-88db-98f22de89214'; type = 'Role' }
    }

    $resourceAccess = @(
        foreach ($permissionName in @($Definition.permissions)) {
            if (-not $permissionMap.ContainsKey([string]$permissionName)) {
                throw "Unknown demo-agent permission '$permissionName'."
            }
            [ordered]@{
                id   = [string]$permissionMap[[string]$permissionName].id
                type = [string]$permissionMap[[string]$permissionName].type
            }
        }
    )

    return @([ordered]@{
        resourceAppId = '00000003-0000-0000-c000-000000000000'
        resourceAccess = $resourceAccess
    })
}

function Invoke-AgentGraphPost {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Body,
        [switch]$OData40
    )

    $parameters = @{
        Method      = 'POST'
        Uri         = $Uri
        Body        = ($Body | ConvertTo-Json -Depth 30 -Compress)
        ContentType = 'application/json'
        OutputType  = 'PSObject'
        ErrorAction = 'Stop'
    }
    if ($OData40) {
        $parameters.Headers = @{ 'OData-Version' = '4.0' }
    }

    # These POSTs are deliberately not retried. If a response is lost after the
    # service commits the object, an automatic retry could create a duplicate.
    return Invoke-MgGraphRequest @parameters
}

function New-DemoAiAgent {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Definition,
        [Parameter(Mandatory)][string]$OwnerId,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][int]$Sequence
    )

    $record = [ordered]@{
        sequence                 = $Sequence
        catalogId                = [int]$Definition.id
        displayName              = [string]$Definition.name
        description              = [string]$Definition.description
        authorityProfile         = [string]$Definition.authorityProfile
        executionMode            = [string]$Definition.executionMode
        declaredPermissions      = @($Definition.permissions)
        credentialsCreated       = $false
        permissionGrantsCreated  = @()
        blueprintId              = $null
        blueprintAppId           = $null
        blueprintPrincipalId     = $null
        agentIdentityId          = $null
        agentIdentityAppId       = $null
        agentRegistrationId      = $null
        registrationSourceId     = "defender-story-seeder-$RunId-$Sequence"
        creationStatus           = 'creating'
        componentStatus          = [ordered]@{
            blueprint          = 'notAttempted'
            blueprintPrincipal = 'notAttempted'
            agentIdentity      = 'notAttempted'
            agentRegistration  = 'notAttempted'
        }
        errors                    = @()
    }

    try {
        $blueprintBody = [ordered]@{
            '@odata.type' = 'Microsoft.Graph.AgentIdentityBlueprint'
            displayName = "[DXR Demo] $([string]$Definition.name)"
            'sponsors@odata.bind' = @("https://graph.microsoft.com/v1.0/users/$OwnerId")
            'owners@odata.bind' = @("https://graph.microsoft.com/v1.0/users/$OwnerId")
            requiredResourceAccess = @(Get-AgentDeclaredResourceAccess -Definition $Definition)
        }
        $blueprint = Invoke-AgentGraphPost `
            -Uri 'https://graph.microsoft.com/v1.0/applications/microsoft.graph.agentIdentityBlueprint' `
            -Body $blueprintBody `
            -OData40
        $record.blueprintId = [string]$blueprint.id
        $record.blueprintAppId = [string]$blueprint.appId
        $record.componentStatus.blueprint = 'created'
    }
    catch {
        $record.componentStatus.blueprint = 'unavailable'
        $record.errors = @($record.errors) + "blueprint: $($_.Exception.Message)"
        $record.creationStatus = 'proxyOnly'
        return $record
    }

    try {
        $principal = Invoke-AgentGraphPost `
            -Uri 'https://graph.microsoft.com/v1.0/serviceprincipals/microsoft.graph.agentIdentityBlueprintPrincipal' `
            -Body ([ordered]@{ appId = [string]$record.blueprintAppId }) `
            -OData40
        $record.blueprintPrincipalId = [string]$principal.id
        $record.componentStatus.blueprintPrincipal = 'created'
    }
    catch {
        $record.componentStatus.blueprintPrincipal = 'unavailable'
        $record.errors = @($record.errors) + "blueprintPrincipal: $($_.Exception.Message)"
    }

    try {
        $identity = Invoke-AgentGraphPost `
            -Uri 'https://graph.microsoft.com/v1.0/servicePrincipals/Microsoft.Graph.AgentIdentity' `
            -Body ([ordered]@{
                displayName = "[DXR Demo] $([string]$Definition.name)"
                agentIdentityBlueprintId = [string]$record.blueprintId
                'sponsors@odata.bind' = @("https://graph.microsoft.com/v1.0/users/$OwnerId")
            }) `
            -OData40
        $record.agentIdentityId = [string]$identity.id
        $record.agentIdentityAppId = [string]$identity.appId
        $record.componentStatus.agentIdentity = 'created'
    }
    catch {
        $record.componentStatus.agentIdentity = 'unavailable'
        $record.errors = @($record.errors) + "agentIdentity: $($_.Exception.Message)"
    }

    try {
        $now = [DateTime]::UtcNow.ToString('o')
        $registrationBody = [ordered]@{
            displayName = "[DXR Demo] $([string]$Definition.name)"
            description = [string]$Definition.description
            ownerIds = @($OwnerId)
            createdBy = $OwnerId
            lastPublishedBy = $OwnerId
            sourceCreatedDateTime = $now
            sourceLastModifiedDateTime = $now
            sourceAgentId = [string]$record.registrationSourceId
            originatingStore = 'DefenderXdrStorySeeder'
            managedByAppId = [string]$record.blueprintAppId
            agentIdentityBlueprintId = [string]$record.blueprintId
            agentCard = [ordered]@{
                name = [string]$Definition.name
                version = '0.2.0-beta'
                description = [string]$Definition.description
                provider = 'Defender XDR Story Seeder'
                capabilities = [ordered]@{ streaming = $false; pushNotifications = $false }
                defaultInputModes = @('text')
                defaultOutputModes = @('text')
                skills = @([ordered]@{
                    id = "demo-$([int]$Definition.id)"
                    name = [string]$Definition.name
                    description = [string]$Definition.description
                })
                securityProfile = [ordered]@{
                    authorityProfile = [string]$Definition.authorityProfile
                    executionMode = [string]$Definition.executionMode
                    declaredPermissions = @($Definition.permissions)
                    credentialsCreated = $false
                    consentGrantsCreated = $false
                    dormantDemo = $true
                }
            }
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$record.agentIdentityId)) {
            $registrationBody.agentIdentityId = [string]$record.agentIdentityId
        }
        $registration = Invoke-AgentGraphPost `
            -Uri 'https://graph.microsoft.com/beta/copilot/agentRegistrations' `
            -Body $registrationBody
        $record.agentRegistrationId = [string]$registration.id
        $record.componentStatus.agentRegistration = 'created'
    }
    catch {
        $record.componentStatus.agentRegistration = 'unavailable'
        $record.errors = @($record.errors) + "agentRegistration: $($_.Exception.Message)"
    }

    $createdComponentCount = @($record.componentStatus.Values | Where-Object { $_ -eq 'created' }).Count
    $record.creationStatus = if ($createdComponentCount -eq 4) { 'created' } elseif ($createdComponentCount -gt 0) { 'partial' } else { 'proxyOnly' }
    return $record
}
