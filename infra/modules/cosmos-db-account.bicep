// ============================================================================
// Cosmos DB Account — Raw resource with CMK, serverless, no local auth, PE
// Uses raw Bicep because AVM v0.18.0 doesn't support customerManagedKey yet
// ============================================================================

@description('Account name')
param name string

@description('Azure region')
param location string

@description('Tags')
param tags object = {}

@description('Key Vault key URI (without version) for CMK encryption')
param keyVaultKeyUri string

@description('User-Assigned Managed Identity resource ID for CMK access')
param uamiResourceId string

@description('PE subnet resource ID')
param peSubnetId string

@description('Cosmos DB Private DNS Zone resource ID')
param cosmosDnsZoneId string

@description('Log Analytics Workspace resource ID')
param lawId string

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' = {
  name: name
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uamiResourceId}': {}
    }
  }
  properties: {
    databaseAccountOfferType: 'Standard'
    defaultIdentity: 'UserAssignedIdentity=${uamiResourceId}'
    keyVaultKeyUri: keyVaultKeyUri
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: true
      }
    ]
    capabilities: [
      { name: 'EnableServerless' }
    ]
    disableLocalAuth: true
    disableKeyBasedMetadataWriteAccess: true
    publicNetworkAccess: 'Disabled'
    networkAclBypass: 'None'
    minimalTlsVersion: 'Tls12'
    enableAutomaticFailover: true
    enableFreeTier: false
    isVirtualNetworkFilterEnabled: false
  }
}

// Private Endpoint
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
        name: 'pe-${name}-sql'
        properties: {
          privateLinkServiceId: cosmosAccount.id
          groupIds: ['Sql']
        }
      }
    ]
  }
}

resource dnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  name: 'default'
  parent: pe
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'cosmos-dns'
        properties: {
          privateDnsZoneId: cosmosDnsZoneId
        }
      }
    ]
  }
}

// Diagnostic settings
resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'cosmos-diag'
  scope: cosmosAccount
  properties: {
    workspaceId: lawId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'Requests'
        enabled: true
      }
    ]
  }
}

@description('Cosmos DB account name')
output name string = cosmosAccount.name

@description('Cosmos DB account resource ID')
output resourceId string = cosmosAccount.id

@description('Cosmos DB document endpoint')
output documentEndpoint string = cosmosAccount.properties.documentEndpoint
