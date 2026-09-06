metadata description = 'AI App layer: private Container Apps environment, registry, configuration, identity and observability for self-hosted agents.'

@description('Base name used to derive resource names. Must be alphanumeric — it is used for the container registry name.')
@minLength(3)
@maxLength(20)
param baseName string

@description('Location for the app resources.')
param location string

@description('Tags applied to all resources.')
param tags object = {}

@description('Resource ID of the subnet delegated to the Container Apps environment.')
param appSubnetResourceId string

@description('Resource ID of the subnet for private endpoints.')
param privateEndpointSubnetResourceId string

@description('Private DNS zone resource ID for Container Registry.')
param acrPrivateDnsZoneResourceId string

@description('Private DNS zone resource ID for App Configuration.')
param appConfigPrivateDnsZoneResourceId string

var abbrs = loadJsonContent('../abbreviations.json')

// Identity the self-hosted agent uses to reach the registry, configuration, Foundry and the gateway.
module agentIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.6.0' = {
  name: 'id-${baseName}'
  params: {
    name: '${abbrs.managedIdentity}${baseName}'
    location: location
    tags: tags
  }
}

module logAnalytics 'br/public:avm/res/operational-insights/workspace:0.16.1' = {
  name: 'law-${baseName}'
  params: {
    name: '${abbrs.logAnalyticsWorkspace}${baseName}'
    location: location
    tags: tags
  }
}

module appInsights 'br/public:avm/res/insights/component:0.8.0' = {
  name: 'appi-${baseName}'
  params: {
    name: '${abbrs.applicationInsights}${baseName}'
    location: location
    tags: tags
    workspaceResourceId: logAnalytics.outputs.resourceId
  }
}

module containerRegistry 'br/public:avm/res/container-registry/registry:0.13.0' = {
  name: 'cr-${baseName}'
  params: {
    name: '${abbrs.containerRegistry}${baseName}'
    location: location
    tags: tags
    acrSku: 'Premium' // Premium is required for private endpoints
    acrAdminUserEnabled: false
    publicNetworkAccess: 'Disabled'
    privateEndpoints: [
      {
        subnetResourceId: privateEndpointSubnetResourceId
        service: 'registry'
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: acrPrivateDnsZoneResourceId
            }
          ]
        }
      }
    ]
    roleAssignments: [
      {
        principalId: agentIdentity.outputs.principalId
        principalType: 'ServicePrincipal'
        roleDefinitionIdOrName: 'AcrPull'
      }
    ]
  }
}

module appConfiguration 'br/public:avm/res/app-configuration/configuration-store:0.10.0' = {
  name: 'appcs-${baseName}'
  params: {
    name: '${abbrs.appConfiguration}${baseName}'
    location: location
    tags: tags
    sku: 'Standard' // Standard is required for private endpoints
    disableLocalAuth: true
    publicNetworkAccess: 'Disabled'
    privateEndpoints: [
      {
        subnetResourceId: privateEndpointSubnetResourceId
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: appConfigPrivateDnsZoneResourceId
            }
          ]
        }
      }
    ]
    roleAssignments: [
      {
        principalId: agentIdentity.outputs.principalId
        principalType: 'ServicePrincipal'
        roleDefinitionIdOrName: 'App Configuration Data Reader'
      }
    ]
  }
}

// VNet-injected, internal-only environment: agent containers are not reachable from the internet.
module containerAppsEnvironment 'br/public:avm/res/app/managed-environment:0.16.0' = {
  name: 'cae-${baseName}'
  params: {
    name: '${abbrs.containerAppsEnvironment}${baseName}'
    location: location
    tags: tags
    infrastructureSubnetResourceId: appSubnetResourceId
    internal: true
    zoneRedundant: false
    publicNetworkAccess: 'Disabled'
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsWorkspaceResourceId: logAnalytics.outputs.resourceId
    }
  }
}

@description('Resource ID of the Container Apps environment that hosts self-hosted agents.')
output containerAppsEnvironmentResourceId string = containerAppsEnvironment.outputs.resourceId

@description('Login server of the container registry.')
output containerRegistryLoginServer string = containerRegistry.outputs.loginServer

@description('Endpoint of the App Configuration store.')
output appConfigurationEndpoint string = appConfiguration.outputs.endpoint

@description('Resource ID of the agent user-assigned managed identity.')
output agentIdentityResourceId string = agentIdentity.outputs.resourceId

@description('Principal ID of the agent user-assigned managed identity.')
output agentIdentityPrincipalId string = agentIdentity.outputs.principalId

@description('Resource ID of the Log Analytics workspace.')
output logAnalyticsResourceId string = logAnalytics.outputs.resourceId

@description('Resource ID of the Application Insights component.')
output appInsightsResourceId string = appInsights.outputs.resourceId

@description('Connection string of the Application Insights component.')
output appInsightsConnectionString string = appInsights.outputs.connectionString
