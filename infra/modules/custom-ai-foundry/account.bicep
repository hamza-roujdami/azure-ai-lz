// ============================================================================
// AI Foundry Account — Raw Bicep (NO deployment scripts, policy-safe)
// Replaces avm/ptn/ai-ml/ai-foundry for environments where Azure Policy
// blocks deployment scripts (zone-resilient, MCSB v2)
// ============================================================================

@description('Account name')
param name string

@description('Azure region')
param location string

@description('Tags')
param tags object = {}

@description('PE subnet resource ID')
param peSubnetId string

@description('DNS zone IDs: [cognitiveservices, openai, services.ai]')
param dnsZoneIds array

resource aiAccount 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' = {
  name: name
  location: location
  tags: tags
  kind: 'AIServices'
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: name
    publicNetworkAccess: 'Disabled'
    disableLocalAuth: true
    allowProjectManagement: true
    networkAcls: {
      defaultAction: 'Deny'
    }
  }
}

resource pe 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${name}'
  location: location
  tags: tags
  properties: {
    subnet: {
      id: peSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'pe-${name}-connection'
        properties: {
          privateLinkServiceId: aiAccount.id
          groupIds: ['account']
        }
      }
    ]
  }
}

resource dnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  name: 'default'
  parent: pe
  properties: {
    privateDnsZoneConfigs: [for (zoneId, i) in dnsZoneIds: {
      name: 'zone-${i}'
      properties: {
        privateDnsZoneId: zoneId
      }
    }]
  }
}

output name string = aiAccount.name
output id string = aiAccount.id
output principalId string = aiAccount.identity.principalId
