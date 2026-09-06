metadata description = 'Model gateway connection that lets Foundry hosted agents in the spoke call models through the API Management gateway.'

@description('Name of the connection as it appears in the Foundry portal.')
param connectionName string = 'ai-gateway'

@description('Name of the spoke Foundry (AIServices) account that hosts the project.')
param foundryAccountName string

@description('Name of the spoke Foundry project the connection is attached to.')
param foundryProjectName string

@description('Base URL of the OpenAI-compatible API exposed by the gateway, without a trailing slash. Foundry appends the request route.')
param gatewayUrl string

@description('Name of the API Management service that fronts the models.')
param apimName string

@description('Resource group of the API Management service.')
param apimResourceGroupName string

@description('Name of the API Management subscription whose key the connection uses.')
param apimSubscriptionName string

@description('Models exposed through the connection. Each entry must match a deployment on the hub Foundry account.')
param models array

@description('Make the connection available to every project on the account.')
param isSharedToAll bool = true

resource apimService 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimName
  scope: resourceGroup(apimResourceGroupName)

  resource gatewaySubscription 'subscriptions' existing = {
    name: apimSubscriptionName
  }
}

resource foundryAccount 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: foundryAccountName

  resource project 'projects' existing = {
    name: foundryProjectName
  }
}

// Field names and formats are fixed by the ModelGateway connection contract.
resource connection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = {
  name: connectionName
  parent: foundryAccount::project
  properties: {
    category: 'ModelGateway'
    target: gatewayUrl
    authType: 'ApiKey'
    isSharedToAll: isSharedToAll
    credentials: {
      key: apimService::gatewaySubscription.listSecrets().primaryKey
    }
    metadata: {
      models: string(models)
      deploymentInPath: 'false'
      authHeaderName: 'Ocp-Apim-Subscription-Key'
      authHeaderFormat: '{api_key}'
      customHeaders: '{}'
    }
  }
}

@description('Resource ID of the model gateway connection.')
output connectionResourceId string = connection.id

@description('Reference agents use to select a model, in the form connection/model.')
output modelReferencePrefix string = '${connectionName}/'
