targetScope = 'subscription'

metadata description = 'AI Platform Landing Zone — private Azure AI Foundry spoke (hosted + self-hosted agent runtimes) and an APIM AI gateway hub.'

// ---------------------------------------------------------------------------
// Parameters
// ---------------------------------------------------------------------------

@description('Short environment name (e.g. dev, uat, prod). Used in resource and resource-group names.')
@minLength(1)
@maxLength(10)
param environmentName string

@description('Azure region for all resources.')
param location string = deployment().location

@description('Additional tags applied to every resource.')
param tags object = {}

@description('Deploy the AI Spoke (Foundry agents workload and its data services). Set false to deploy only the hub.')
param deploySpoke bool = true

@description('Deploy the application layer (Container Apps environment, registry, configuration, observability) that hosts self-hosted agents. Only applies when the spoke is deployed.')
param deployAppLayer bool = true

@description('Deploy the AI Hub (APIM gateway and the Foundry account holding the shared models). Set false to deploy only the spoke.')
param deployHub bool = true

@description('Publisher email for API Management (hub only).')
param apimPublisherEmail string = 'admin@example.com'

@description('Publisher organization name for API Management (hub only).')
param apimPublisherName string = 'AI Platform'

@description('Deploy Azure Bastion and a jumpbox so the private landing zone can be reached. Requires jumpboxAdminPassword.')
param deployJumpbox bool = false

@description('Administrator password for the jumpbox. Supply at deployment time; never commit it.')
@secure()
param jumpboxAdminPassword string = ''

@description('Deploy the token usage ledger (Event Hub plus Cosmos DB) behind the gateway.')
param deployUsageLedger bool = true

@description('Require a valid Entra ID token on every gateway call.')
param enableJwtValidation bool = false

@description('Per-subscription request budget enforced by the gateway, in calls per minute.')
param callsPerMinute int = 300

@description('Expose the Anthropic Messages API for Claude models on the gateway. Claude is not available in every region, so this is off by default.')
param deployAnthropicApi bool = false

@description('Legal entity name attested when deploying partner models such as Claude.')
param modelProviderOrganizationName string = 'Contoso'

@description('Industry attested when deploying partner models such as Claude.')
@allowed([
  'education'
  'finance'
  'government'
  'healthcare'
  'manufacturing'
  'media'
  'other'
  'retail'
  'technology'
])
param modelProviderIndustry string = 'technology'

@description('Two-letter ISO 3166-1 country code attested when deploying partner models such as Claude.')
param modelProviderCountryCode string = 'US'

@description('Model deployments created on the hub Foundry account. These are the models the gateway fronts.')
param modelDeployments array = [
  {
    name: 'gpt-4o'
    model: {
      format: 'OpenAI'
      name: 'gpt-4o'
      version: '2024-11-20'
    }
    sku: {
      name: 'Standard'
      capacity: 1
    }
  }
  {
    name: 'text-embedding-3-large'
    model: {
      format: 'OpenAI'
      name: 'text-embedding-3-large'
      version: '1'
    }
    sku: {
      name: 'Standard'
      capacity: 1
    }
  }
]

// ---------------------------------------------------------------------------
// Variables
// ---------------------------------------------------------------------------

var abbrs = loadJsonContent('abbreviations.json')

var baseName = toLower('${environmentName}${substring(uniqueString(subscription().id, environmentName), 0, 4)}')

var baseTags = union(tags, {
  environment: environmentName
  workload: 'ai-platform-lz'
})

// Fixed up front so the gateway can be configured without depending on the ledger module.
var usageEventHubNamespaceName = '${abbrs.eventHubNamespace}aihub${baseName}'
var usageEventHubName = 'ai-usage'

// ---------------------------------------------------------------------------
// Resource groups
// ---------------------------------------------------------------------------

resource networkRg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: '${abbrs.resourceGroup}ai-platform-${environmentName}-network'
  location: location
  tags: baseTags
}

resource spokeAiRg 'Microsoft.Resources/resourceGroups@2024-03-01' = if (deploySpoke) {
  name: '${abbrs.resourceGroup}ai-spoke-${environmentName}-ai'
  location: location
  tags: baseTags
}

resource spokeAppRg 'Microsoft.Resources/resourceGroups@2024-03-01' = if (deploySpoke && deployAppLayer) {
  name: '${abbrs.resourceGroup}ai-spoke-${environmentName}-app'
  location: location
  tags: baseTags
}

resource hubRg 'Microsoft.Resources/resourceGroups@2024-03-01' = if (deployHub) {
  name: '${abbrs.resourceGroup}ai-hub-${environmentName}'
  location: location
  tags: baseTags
}
// ---------------------------------------------------------------------------
// Shared network + private DNS zones (serves both spoke and hub)
// ---------------------------------------------------------------------------

module networking 'modules/networking.bicep' = {
  name: 'ai-platform-networking'
  scope: networkRg
  params: {
    baseName: 'ai-platform-${environmentName}'
    location: location
    tags: baseTags
  }
}

// ---------------------------------------------------------------------------
// AI Spoke — Foundry account + project + associated data services (private)
// ---------------------------------------------------------------------------

module aiSpoke 'modules/ai-spoke.bicep' = if (deploySpoke) {
  name: 'ai-spoke'
  scope: spokeAiRg
  params: {
    baseName: 'aisp${baseName}'
    location: location
    tags: baseTags
    privateEndpointSubnetResourceId: networking.outputs.privateEndpointSubnetResourceId
    agentSubnetResourceId: networking.outputs.agentSubnetResourceId
    aiServicesPrivateDnsZoneResourceId: networking.outputs.aiServicesPrivateDnsZoneResourceId
    cognitiveServicesPrivateDnsZoneResourceId: networking.outputs.cognitiveServicesPrivateDnsZoneResourceId
    openAiPrivateDnsZoneResourceId: networking.outputs.openAiPrivateDnsZoneResourceId
    cosmosPrivateDnsZoneResourceId: networking.outputs.cosmosPrivateDnsZoneResourceId
    searchPrivateDnsZoneResourceId: networking.outputs.searchPrivateDnsZoneResourceId
    blobPrivateDnsZoneResourceId: networking.outputs.blobPrivateDnsZoneResourceId
    keyVaultPrivateDnsZoneResourceId: networking.outputs.keyVaultPrivateDnsZoneResourceId
  }
}

// ---------------------------------------------------------------------------
// AI App layer — self-hosted agent runtime (Container Apps + registry + config)
// ---------------------------------------------------------------------------

module aiApp 'modules/ai-app.bicep' = if (deploySpoke && deployAppLayer) {
  name: 'ai-app'
  scope: spokeAppRg
  params: {
    baseName: 'aiapp${baseName}'
    location: location
    tags: baseTags
    appSubnetResourceId: networking.outputs.appSubnetResourceId
    privateEndpointSubnetResourceId: networking.outputs.privateEndpointSubnetResourceId
    acrPrivateDnsZoneResourceId: networking.outputs.acrPrivateDnsZoneResourceId
    appConfigPrivateDnsZoneResourceId: networking.outputs.appConfigPrivateDnsZoneResourceId
  }
}

// ---------------------------------------------------------------------------
// Jumpbox — the only way into a landing zone with no public endpoints
// ---------------------------------------------------------------------------

module jumpbox 'modules/jumpbox.bicep' = if (deployJumpbox) {
  name: 'ai-jumpbox'
  scope: networkRg
  params: {
    baseName: 'jb${baseName}'
    location: location
    tags: baseTags
    jumpboxSubnetResourceId: networking.outputs.jumpboxSubnetResourceId
    bastionSubnetResourceId: networking.outputs.bastionSubnetResourceId
    adminPassword: jumpboxAdminPassword
  }
}

// ---------------------------------------------------------------------------
// Usage ledger — durable record of gateway consumption for chargeback
// ---------------------------------------------------------------------------

// The gateway publishes usage events with this identity. It is created first because API Management
// verifies it can reach the event hub while creating the logger, so the role assignment has to
// already exist by then.
module usageIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.6.0' = if (deployHub && deployUsageLedger) {
  name: 'ai-usage-identity'
  scope: hubRg
  params: {
    name: '${abbrs.managedIdentity}usage${baseName}'
    location: location
    tags: baseTags
  }
}

// Deployed before the hub, because the gateway's event hub logger fails to validate
// against a namespace that does not exist yet.
module usageLedger 'modules/usage-ledger.bicep' = if (deployHub && deployUsageLedger) {
  name: 'ai-usage-ledger'
  scope: hubRg
  params: {
    baseName: 'led${baseName}'
    location: location
    tags: baseTags
    eventHubNamespaceName: usageEventHubNamespaceName
    eventHubName: usageEventHubName
    privateEndpointSubnetResourceId: networking.outputs.privateEndpointSubnetResourceId
    eventHubPrivateDnsZoneResourceId: networking.outputs.eventHubPrivateDnsZoneResourceId
    cosmosPrivateDnsZoneResourceId: networking.outputs.cosmosPrivateDnsZoneResourceId
    gatewayPrincipalId: usageIdentity!.outputs.principalId
  }
}

// ---------------------------------------------------------------------------
// AI Hub — APIM gateway + observability (private ingress)
// ---------------------------------------------------------------------------

module aiHub 'modules/ai-hub.bicep' = if (deployHub) {
  name: 'ai-hub'
  scope: hubRg
  dependsOn: [
    usageLedger
  ]
  params: {
    baseName: 'aihub${baseName}'
    location: location
    tags: baseTags
    publisherEmail: apimPublisherEmail
    publisherName: apimPublisherName
    modelDeployments: modelDeployments
    deployAnthropicApi: deployAnthropicApi
    modelProviderOrganizationName: modelProviderOrganizationName
    modelProviderIndustry: modelProviderIndustry
    modelProviderCountryCode: modelProviderCountryCode
    enableJwtValidation: enableJwtValidation
    callsPerMinute: callsPerMinute
    usageEventHubNamespaceName: (deployHub && deployUsageLedger) ? usageEventHubNamespaceName : ''
    usageEventHubName: (deployHub && deployUsageLedger) ? usageEventHubName : ''
    usageIdentityResourceId: (deployHub && deployUsageLedger) ? usageIdentity!.outputs.resourceId : ''
    usageIdentityClientId: (deployHub && deployUsageLedger) ? usageIdentity!.outputs.clientId : ''
    privateEndpointSubnetResourceId: networking.outputs.privateEndpointSubnetResourceId
    apimSubnetResourceId: networking.outputs.apimSubnetResourceId
    apimPrivateDnsZoneResourceId: networking.outputs.apimPrivateDnsZoneResourceId
    aiServicesPrivateDnsZoneResourceId: networking.outputs.aiServicesPrivateDnsZoneResourceId
    cognitiveServicesPrivateDnsZoneResourceId: networking.outputs.cognitiveServicesPrivateDnsZoneResourceId
    openAiPrivateDnsZoneResourceId: networking.outputs.openAiPrivateDnsZoneResourceId
  }
}

// ---------------------------------------------------------------------------
// Model gateway connection — lets spoke hosted agents call models via the hub
// ---------------------------------------------------------------------------

// The model gateway connection requires an OpenAI-compatible endpoint, so Anthropic models are excluded.
var connectionModels = [
  for deployment in filter(modelDeployments, deployment => deployment.model.format == 'OpenAI'): {
    name: deployment.name
    properties: {
      model: {
        name: deployment.model.name
        version: deployment.model.version
        format: deployment.model.format
      }
    }
  }
]

module modelConnection 'modules/foundry-model-connection.bicep' = if (deploySpoke && deployHub) {
  name: 'ai-model-connection'
  scope: spokeAiRg
  params: {
    foundryAccountName: aiSpoke!.outputs.aiServicesName
    foundryProjectName: aiSpoke!.outputs.aiProjectName
    gatewayUrl: aiHub!.outputs.openAiGatewayUrl
    apimName: aiHub!.outputs.apimName
    apimResourceGroupName: hubRg.name
    apimSubscriptionName: aiHub!.outputs.foundryConnectionSubscriptionName
    models: connectionModels
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

output networkResourceGroupName string = networkRg.name
output spokeAiResourceGroupName string = deploySpoke ? spokeAiRg.name : ''
output spokeAppResourceGroupName string = (deploySpoke && deployAppLayer) ? spokeAppRg.name : ''
output hubResourceGroupName string = deployHub ? hubRg.name : ''
output vnetResourceId string = networking.outputs.vnetResourceId
output aiServicesName string = deploySpoke ? (aiSpoke.?outputs.aiServicesName ?? '') : ''
output aiProjectName string = deploySpoke ? (aiSpoke.?outputs.aiProjectName ?? '') : ''
output containerAppsEnvironmentResourceId string = (deploySpoke && deployAppLayer) ? (aiApp.?outputs.containerAppsEnvironmentResourceId ?? '') : ''
output containerRegistryLoginServer string = (deploySpoke && deployAppLayer) ? (aiApp.?outputs.containerRegistryLoginServer ?? '') : ''
output agentIdentityPrincipalId string = (deploySpoke && deployAppLayer) ? (aiApp.?outputs.agentIdentityPrincipalId ?? '') : ''
output apimName string = deployHub ? (aiHub.?outputs.apimName ?? '') : ''
output hubFoundryName string = deployHub ? (aiHub.?outputs.hubFoundryName ?? '') : ''
output hubProjectName string = deployHub ? (aiHub.?outputs.hubProjectName ?? '') : ''
output hubProjectEndpoint string = deployHub ? (aiHub.?outputs.hubProjectEndpoint ?? '') : ''
output openAiGatewayUrl string = deployHub ? (aiHub.?outputs.openAiGatewayUrl ?? '') : ''
output anthropicGatewayUrl string = deployHub ? (aiHub.?outputs.anthropicGatewayUrl ?? '') : ''
output bastionName string = deployJumpbox ? (jumpbox.?outputs.bastionName ?? '') : ''
output jumpboxName string = deployJumpbox ? (jumpbox.?outputs.jumpboxName ?? '') : ''
output usageLedgerAccountName string = (deployHub && deployUsageLedger) ? (usageLedger.?outputs.ledgerAccountName ?? '') : ''
output usageEventHubNamespace string = (deployHub && deployUsageLedger) ? (usageLedger.?outputs.eventHubNamespaceName ?? '') : ''
