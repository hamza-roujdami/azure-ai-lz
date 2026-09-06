metadata description = 'AI Spoke: private Azure AI Foundry account + project with private associated data services.'

@description('Base name used to derive resource names.')
param baseName string

@description('Location for the spoke resources.')
param location string

@description('Tags applied to all resources.')
param tags object = {}

@description('Model deployments to create on the Foundry account. Empty by default — models and MCP tools are served through the AI gateway (phase 2 hub), not deployed on the spoke.')
param aiModelDeployments array = []

@description('Resource ID of the subnet for private endpoints.')
param privateEndpointSubnetResourceId string

@description('Resource ID of the subnet delegated to the agent service.')
param agentSubnetResourceId string

@description('Private DNS zone resource ID for AI Services.')
param aiServicesPrivateDnsZoneResourceId string

@description('Private DNS zone resource ID for Cognitive Services.')
param cognitiveServicesPrivateDnsZoneResourceId string

@description('Private DNS zone resource ID for OpenAI.')
param openAiPrivateDnsZoneResourceId string

@description('Private DNS zone resource ID for Cosmos DB.')
param cosmosPrivateDnsZoneResourceId string

@description('Private DNS zone resource ID for AI Search.')
param searchPrivateDnsZoneResourceId string

@description('Private DNS zone resource ID for Storage blob.')
param blobPrivateDnsZoneResourceId string

@description('Private DNS zone resource ID for Key Vault.')
param keyVaultPrivateDnsZoneResourceId string

module aiFoundry 'br/public:avm/ptn/ai-ml/ai-foundry:0.7.0' = {
  name: 'aifoundry-${baseName}'
  params: {
    baseName: baseName
    location: location
    tags: tags
    includeAssociatedResources: true
    aiModelDeployments: aiModelDeployments
    privateEndpointSubnetResourceId: privateEndpointSubnetResourceId
    aiFoundryConfiguration: {
      allowProjectManagement: true
      createCapabilityHosts: true
      networking: {
        agentServiceSubnetResourceId: agentSubnetResourceId
        aiServicesPrivateDnsZoneResourceId: aiServicesPrivateDnsZoneResourceId
        cognitiveServicesPrivateDnsZoneResourceId: cognitiveServicesPrivateDnsZoneResourceId
        openAiPrivateDnsZoneResourceId: openAiPrivateDnsZoneResourceId
      }
    }
    aiSearchConfiguration: {
      privateDnsZoneResourceId: searchPrivateDnsZoneResourceId
    }
    cosmosDbConfiguration: {
      privateDnsZoneResourceId: cosmosPrivateDnsZoneResourceId
    }
    keyVaultConfiguration: {
      privateDnsZoneResourceId: keyVaultPrivateDnsZoneResourceId
    }
    storageAccountConfiguration: {
      blobPrivateDnsZoneResourceId: blobPrivateDnsZoneResourceId
    }
  }
}

@description('Name of the AI Foundry (AI Services) account.')
output aiServicesName string = aiFoundry.outputs.aiServicesName

@description('Name of the AI Foundry project.')
output aiProjectName string = aiFoundry.outputs.aiProjectName

@description('Name of the AI Search service.')
output aiSearchName string = aiFoundry.outputs.aiSearchName

@description('Name of the Cosmos DB account.')
output cosmosAccountName string = aiFoundry.outputs.cosmosAccountName

@description('Name of the Key Vault.')
output keyVaultName string = aiFoundry.outputs.keyVaultName

@description('Name of the Storage account.')
output storageAccountName string = aiFoundry.outputs.storageAccountName
