// ============================================================================
// AI Foundry Project + Connections — Raw Bicep (NO deployment scripts)
// Creates project with 3 connections (Cosmos, Storage, Search) using AAD auth
// ============================================================================

@description('Project name')
param projectName string

@description('Parent account name')
param accountName string

@description('Cosmos DB account name')
param cosmosName string

@description('Storage account name')
param storageName string

@description('AI Search service name')
param searchName string

@description('Location')
param location string

@description('Tags')
param tags object = {}

resource account 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: accountName
}

resource cosmosDb 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' existing = {
  name: cosmosName
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageName
}

resource searchService 'Microsoft.Search/searchServices@2024-06-01-preview' existing = {
  name: searchName
}

#disable-next-line BCP081
resource project 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' = {
  parent: account
  name: projectName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: projectName
    description: 'AI Foundry project for ${projectName}'
  }
}

#disable-next-line BCP081
resource connectionCosmos 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = {
  parent: project
  name: '${cosmosName}-connection'
  properties: {
    category: 'CosmosDB'
    authType: 'AAD'
    target: cosmosDb.properties.documentEndpoint
    metadata: {
      ApiType: 'Azure'
      ResourceId: cosmosDb.id
    }
  }
}

#disable-next-line BCP081
resource connectionStorage 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = {
  parent: project
  name: '${storageName}-connection'
  properties: {
    category: 'AzureStorageAccount'
    authType: 'AAD'
    target: storageAccount.properties.primaryEndpoints.blob
    metadata: {
      ApiType: 'Azure'
      ResourceId: storageAccount.id
    }
  }
}

#disable-next-line BCP081
resource connectionSearch 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = {
  parent: project
  name: '${searchName}-connection'
  properties: {
    category: 'CognitiveSearch'
    authType: 'AAD'
    target: 'https://${searchService.name}.search.windows.net'
    metadata: {
      ApiType: 'Azure'
      ResourceId: searchService.id
    }
  }
}

output projectPrincipalId string = project.identity.principalId
output projectId string = project.id
output cosmosConnectionName string = connectionCosmos.name
output storageConnectionName string = connectionStorage.name
output searchConnectionName string = connectionSearch.name
