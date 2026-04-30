// ============================================================================
// Foundry → APIM Connection
//
// Creates a connection in an existing AI Foundry project that points to
// the Compass API on APIM. Agents use this connection to call external LLMs.
//
// Model discovery:
//   - Dynamic (default): Leave staticModels empty. Foundry calls
//     APIM ListDeployments (/compass/deployments) to discover models.
//   - Static: Provide model names directly (skips the API call).
//
// Usage:
//   az deployment group create -g <BU_AISERVICES_RG> \
//     -f foundry-connection.bicep \
//     -p accountName=<FOUNDRY_ACCOUNT> \
//     -p projectName=<FOUNDRY_PROJECT> \
//     -p targetUrl='https://<apim>.azure-api.net/compass' \
//     -p apiKey=<APIM_SUBSCRIPTION_KEY>
// ============================================================================

@description('Existing AI Foundry account name')
param accountName string

@description('Existing AI Foundry project name')
param projectName string

@description('Connection name')
param connectionName string = 'compass-apim'

@description('APIM Compass endpoint URL (e.g., https://<apim-name>.azure-api.net/compass)')
param targetUrl string

@description('APIM subscription key (from the Product subscription)')
@secure()
param apiKey string

@description('Whether deployment name is in URL path')
param deploymentInPath string = 'true'

@description('API version for inference calls')
param inferenceAPIVersion string = '2024-10-21'

@description('Static list of models. Leave empty for dynamic discovery via ListDeployments.')
param staticModels array = []

// ──────────────────────────────────────────────────────────────────────────────
// EXISTING RESOURCES
// ──────────────────────────────────────────────────────────────────────────────

resource account 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: accountName
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' existing = {
  parent: account
  name: projectName
}

// ──────────────────────────────────────────────────────────────────────────────
// CONNECTION
// ──────────────────────────────────────────────────────────────────────────────

resource connection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = {
  parent: project
  name: connectionName
  properties: {
    category: 'ApiManagement'
    target: targetUrl
    authType: 'ApiKey'
    isSharedToAll: true
    credentials: {
      key: apiKey
    }
    metadata: empty(staticModels)
      ? {
          deploymentInPath: deploymentInPath
          inferenceAPIVersion: inferenceAPIVersion
        }
      : {
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
output connectionId string = connection.id

@description('Connection name')
output connectionName string = connection.name
