// ============================================================================
// Foundry APIM Connection — Connects AI Foundry project to external LLM via APIM
//
// Creates an ApiManagement category connection on the Foundry project.
// Foundry Agent Service uses this to discover and call models through APIM.
//
// Model discovery:
//   - Dynamic (default): staticModels = [] → Foundry calls APIM ListDeployments
//   - Static: staticModels = ['jais-70b'] → models stored in connection metadata
//
// Reference: https://github.com/nstijepovic/sample-foundry-apim
// ============================================================================

@description('Parent AI Foundry Account name')
param accountName string

@description('Foundry Project name')
param projectName string

@description('Connection name (agents reference models as {connectionName}/{modelName})')
param connectionName string = 'compass-connection'

@description('APIM endpoint URL (e.g., https://myapim.azure-api.net/compass)')
param targetUrl string

@description('APIM subscription key for the Compass API')
@secure()
param apimSubscriptionKey string

@description('Whether deployment name is in URL path')
param deploymentInPath string = 'true'

@description('API version for inference calls')
param inferenceAPIVersion string = '2024-10-21'

@description('Static list of models. Leave empty for dynamic discovery via APIM ListDeployments.')
param staticModels array = []

// ──────────────────────────────────────────────────────────────────────────────
// EXISTING RESOURCES
// ──────────────────────────────────────────────────────────────────────────────

#disable-next-line BCP081
resource account 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: accountName
}

#disable-next-line BCP081
resource project 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' existing = {
  parent: account
  name: projectName
}

// ──────────────────────────────────────────────────────────────────────────────
// APIM CONNECTION
// ──────────────────────────────────────────────────────────────────────────────

#disable-next-line BCP081
resource apimConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = {
  parent: project
  name: connectionName
  properties: {
    category: 'ApiManagement'
    target: targetUrl
    authType: 'ApiKey'
    isSharedToAll: true
    credentials: {
      key: apimSubscriptionKey
    }
    metadata: empty(staticModels) ? {
      deploymentInPath: deploymentInPath
      inferenceAPIVersion: inferenceAPIVersion
    } : {
      deploymentInPath: deploymentInPath
      inferenceAPIVersion: inferenceAPIVersion
      models: string(staticModels)
    }
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// OUTPUTS
// ──────────────────────────────────────────────────────────────────────────────

@description('Connection resource ID')
output connectionId string = apimConnection.id

@description('Connection name (use as {connectionName}/{modelName} in agents)')
output connectionName string = apimConnection.name
