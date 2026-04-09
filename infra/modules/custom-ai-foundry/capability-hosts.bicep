// ============================================================================
// Capability Hosts — Account + Project level (NO deployment scripts)
// Enables Agent Service and wires project to data stores
// ============================================================================

@description('AI Foundry Account name')
param accountName string

@description('AI Foundry Project name')
param projectName string

@description('Cosmos DB connection name (from project connections)')
param cosmosConnectionName string

@description('Storage connection name (from project connections)')
param storageConnectionName string

@description('AI Search connection name (from project connections)')
param searchConnectionName string

#disable-next-line BCP081
resource account 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: accountName
}

#disable-next-line BCP081
resource project 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' existing = {
  name: projectName
  parent: account
}

// Account-level capability host — enables Agent Service
#disable-next-line BCP081
resource accountCapabilityHost 'Microsoft.CognitiveServices/accounts/capabilityHosts@2025-04-01-preview' = {
  name: 'caphost-account'
  parent: account
  properties: {
    capabilityHostKind: 'Agents'
  }
}

// Project-level capability host — wires data stores
#disable-next-line BCP081
resource projectCapabilityHost 'Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-04-01-preview' = {
  name: 'caphost-project'
  parent: project
  properties: {
    capabilityHostKind: 'Agents'
    vectorStoreConnections: [searchConnectionName]
    storageConnections: [storageConnectionName]
    threadStorageConnections: [cosmosConnectionName]
  }
  dependsOn: [accountCapabilityHost]
}
