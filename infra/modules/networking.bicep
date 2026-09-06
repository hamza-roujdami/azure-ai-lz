metadata description = 'Shared virtual network, subnets, and private DNS zones for a private AI platform unit (hub or spoke).'

@description('Base name used to derive resource names.')
param baseName string

@description('Location for the network resources.')
param location string

@description('Address space for the virtual network.')
param addressPrefix string = '10.10.0.0/23'

@description('Tags applied to all resources.')
param tags object = {}

var abbrs = loadJsonContent('../abbreviations.json')

// /23 split into functional /26 and /27 subnets.
var subnets = [
  {
    name: 'snet-apim'
    addressPrefix: '10.10.0.0/27'
    // Outbound VNet integration for API Management v2 requires this delegation.
    delegation: 'Microsoft.Web/serverFarms'
    attachNsg: true
  }
  {
    name: 'snet-privateendpoints'
    addressPrefix: '10.10.0.32/27'
    delegation: ''
    attachNsg: true
  }
  {
    name: 'snet-app'
    addressPrefix: '10.10.0.128/26'
    delegation: 'Microsoft.App/environments'
    attachNsg: true
  }
  {
    name: 'snet-agent'
    addressPrefix: '10.10.1.0/26'
    delegation: 'Microsoft.App/environments'
    attachNsg: true
  }
  {
    name: 'snet-jumpbox'
    addressPrefix: '10.10.0.64/27'
    delegation: ''
    attachNsg: true
  }
  {
    // Azure requires this exact name and a /26 or larger. It also rejects any NSG that lacks the
    // Bastion-specific rule set, so no NSG is attached here.
    name: 'AzureBastionSubnet'
    addressPrefix: '10.10.1.64/26'
    delegation: ''
    attachNsg: false
  }
]

// Private DNS zones required for the private endpoints created by the spoke and hub.
var privateDnsZoneNames = [
  'privatelink.services.ai.azure.com' // 0 - AI Services
  'privatelink.cognitiveservices.azure.com' // 1 - Cognitive Services
  'privatelink.openai.azure.com' // 2 - OpenAI
  'privatelink.documents.azure.com' // 3 - Cosmos DB (SQL)
  'privatelink.search.windows.net' // 4 - AI Search
  'privatelink.blob.${environment().suffixes.storage}' // 5 - Storage blob
  'privatelink.vaultcore.azure.net' // 6 - Key Vault
  'privatelink.azure-api.net' // 7 - API Management
  'privatelink.azurecr.io' // 8 - Container Registry
  'privatelink.azconfig.io' // 9 - App Configuration
  'privatelink.servicebus.windows.net' // 10 - Event Hub
]

module nsg 'br/public:avm/res/network/network-security-group:0.5.3' = {
  name: 'nsg-${baseName}'
  params: {
    name: '${abbrs.networkSecurityGroup}${baseName}'
    location: location
    tags: tags
  }
}

module vnet 'br/public:avm/res/network/virtual-network:0.10.2' = {
  name: 'vnet-${baseName}'
  params: {
    name: '${abbrs.virtualNetwork}${baseName}'
    location: location
    tags: tags
    addressPrefixes: [
      addressPrefix
    ]
    subnets: [
      for subnet in subnets: {
        name: subnet.name
        addressPrefix: subnet.addressPrefix
        networkSecurityGroupResourceId: subnet.attachNsg ? nsg.outputs.resourceId : null
        delegation: empty(subnet.delegation) ? null : subnet.delegation
      }
    ]
  }
}

module privateDnsZones 'br/public:avm/res/network/private-dns-zone:0.8.1' = [
  for (zoneName, i) in privateDnsZoneNames: {
    name: 'pdns-${i}-${baseName}'
    params: {
      name: zoneName
      tags: tags
      virtualNetworkLinks: [
        {
          virtualNetworkResourceId: vnet.outputs.resourceId
          registrationEnabled: false
        }
      ]
    }
  }
]

@description('Resource ID of the virtual network.')
output vnetResourceId string = vnet.outputs.resourceId

@description('Resource ID of the API Management subnet.')
output apimSubnetResourceId string = vnet.outputs.subnetResourceIds[0]

@description('Resource ID of the private endpoint subnet.')
output privateEndpointSubnetResourceId string = vnet.outputs.subnetResourceIds[1]

@description('Resource ID of the application (Container Apps) subnet.')
output appSubnetResourceId string = vnet.outputs.subnetResourceIds[2]

@description('Resource ID of the agent subnet.')
output agentSubnetResourceId string = vnet.outputs.subnetResourceIds[3]

@description('Private DNS zone resource ID for AI Services.')
output aiServicesPrivateDnsZoneResourceId string = privateDnsZones[0].outputs.resourceId

@description('Private DNS zone resource ID for Cognitive Services.')
output cognitiveServicesPrivateDnsZoneResourceId string = privateDnsZones[1].outputs.resourceId

@description('Private DNS zone resource ID for OpenAI.')
output openAiPrivateDnsZoneResourceId string = privateDnsZones[2].outputs.resourceId

@description('Private DNS zone resource ID for Cosmos DB.')
output cosmosPrivateDnsZoneResourceId string = privateDnsZones[3].outputs.resourceId

@description('Private DNS zone resource ID for AI Search.')
output searchPrivateDnsZoneResourceId string = privateDnsZones[4].outputs.resourceId

@description('Private DNS zone resource ID for Storage blob.')
output blobPrivateDnsZoneResourceId string = privateDnsZones[5].outputs.resourceId

@description('Private DNS zone resource ID for Key Vault.')
output keyVaultPrivateDnsZoneResourceId string = privateDnsZones[6].outputs.resourceId

@description('Private DNS zone resource ID for API Management.')
output apimPrivateDnsZoneResourceId string = privateDnsZones[7].outputs.resourceId

@description('Private DNS zone resource ID for Container Registry.')
output acrPrivateDnsZoneResourceId string = privateDnsZones[8].outputs.resourceId

@description('Private DNS zone resource ID for App Configuration.')
output appConfigPrivateDnsZoneResourceId string = privateDnsZones[9].outputs.resourceId

@description('Private DNS zone resource ID for Event Hub.')
output eventHubPrivateDnsZoneResourceId string = privateDnsZones[10].outputs.resourceId

@description('Resource ID of the jumpbox subnet.')
output jumpboxSubnetResourceId string = vnet.outputs.subnetResourceIds[4]

@description('Resource ID of the Azure Bastion subnet.')
output bastionSubnetResourceId string = vnet.outputs.subnetResourceIds[5]
