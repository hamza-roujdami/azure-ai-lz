// ============================================================================
// APIM Compass API — Configures OpenAI-compatible proxy for Core42 Compass
//
// Creates on an existing APIM instance:
//   - Named Value (Compass API key from Key Vault)
//   - API (compass-api, path /compass)
//   - 3 Operations: ListDeployments, GetDeployment, ChatCompletions
//   - 3 Policies: static model list, static model detail, forward + inject key
//
// Foundry Agent Service requires these 3 endpoints to discover and call
// external LLM models via an ApiManagement connection.
//
// Reference: https://github.com/nstijepovic/sample-foundry-apim
// ============================================================================

@description('Existing APIM resource name')
param apimName string

@description('Backend URL for the external LLM provider')
param backendUrl string = 'https://api.core42.ai/openai'

@description('Key Vault URI containing the Compass API key secret')
param keyVaultUri string

@description('Secret name in Key Vault for the Compass API key')
param compassApiKeySecretName string = 'compass-api-key'

@description('List of available model names (returned by ListDeployments)')
param models array = [
  'jais-70b'
  'falcon-180b'
]

// ──────────────────────────────────────────────────────────────────────────────
// EXISTING APIM
// ──────────────────────────────────────────────────────────────────────────────

resource apim 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimName
}

// ──────────────────────────────────────────────────────────────────────────────
// NAMED VALUE — Compass API key from Key Vault (not hardcoded)
// ──────────────────────────────────────────────────────────────────────────────

resource compassApiKeyNamedValue 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apim
  name: 'compass-api-key'
  properties: {
    displayName: 'compass-api-key'
    secret: true
    keyVault: {
      secretIdentifier: '${keyVaultUri}secrets/${compassApiKeySecretName}'
    }
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// API — OpenAI-compatible proxy to Compass
// subscription-key-header-name = 'api-key' is REQUIRED for Foundry compatibility
// ──────────────────────────────────────────────────────────────────────────────

resource compassApi 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apim
  name: 'compass-api'
  properties: {
    displayName: 'Compass API'
    path: 'compass'
    serviceUrl: backendUrl
    protocols: ['https']
    subscriptionRequired: true
    subscriptionKeyParameterNames: {
      header: 'api-key'
      query: 'api-key'
    }
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// OPERATIONS + POLICIES
// ──────────────────────────────────────────────────────────────────────────────

// --- Build the static model JSON for ListDeployments ---
var modelEntries = [for model in models: '{"name":"${model}","properties":{"model":{"format":"OpenAI","name":"${model}","version":""}}}']
var modelListJson = '{"value":[${join(modelEntries, ',')}]}'

// --- ListDeployments: GET /deployments ---
// Returns a static list of available models. Foundry calls this to discover models.

resource listDeploymentsOp 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  parent: compassApi
  name: 'ListDeployments'
  properties: {
    displayName: 'ListDeployments'
    method: 'GET'
    urlTemplate: '/deployments'
  }
}

resource listDeploymentsPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2024-05-01' = {
  parent: listDeploymentsOp
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '<policies><inbound><base /><return-response><set-status code="200" reason="OK" /><set-header name="Content-Type" exists-action="override"><value>application/json</value></set-header><set-body>${modelListJson}</set-body></return-response></inbound><backend><base /></backend><outbound><base /></outbound><on-error><base /></on-error></policies>'
  }
}

// --- GetDeployment: GET /deployments/{deploymentName} ---
// Returns model details. Foundry calls this to validate a model exists.
// Uses a C# expression to dynamically return the requested model name.

resource getDeploymentOp 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  parent: compassApi
  name: 'GetDeployment'
  properties: {
    displayName: 'GetDeployment'
    method: 'GET'
    urlTemplate: '/deployments/{deploymentName}'
    templateParameters: [
      {
        name: 'deploymentName'
        type: 'string'
        required: true
      }
    ]
  }
}

resource getDeploymentPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2024-05-01' = {
  parent: getDeploymentOp
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '<policies><inbound><base /><return-response><set-status code="200" reason="OK" /><set-header name="Content-Type" exists-action="override"><value>application/json</value></set-header><set-body>@{var name = context.Request.MatchedParameters["deploymentName"]; return $"{{\\"name\\": \\"{name}\\", \\"properties\\": {{\\"model\\": {{\\"format\\": \\"OpenAI\\", \\"name\\": \\"{name}\\", \\"version\\": \\"\\"}}}}}}";};</set-body></return-response></inbound><backend><base /></backend><outbound><base /></outbound><on-error><base /></on-error></policies>'
  }
}

// --- ChatCompletions: POST /deployments/{deployment-id}/chat/completions ---
// Forwards the request to Compass backend and injects the API key.
// API key is read from Key Vault via Named Value (not hardcoded).

resource chatCompletionsOp 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  parent: compassApi
  name: 'ChatCompletions'
  properties: {
    displayName: 'ChatCompletions'
    method: 'POST'
    urlTemplate: '/deployments/{deployment-id}/chat/completions'
    templateParameters: [
      {
        name: 'deployment-id'
        type: 'string'
        required: true
      }
    ]
  }
}

resource chatCompletionsPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2024-05-01' = {
  parent: chatCompletionsOp
  name: 'policy'
  dependsOn: [compassApiKeyNamedValue]
  properties: {
    format: 'rawxml'
    value: '<policies><inbound><base /><set-header name="api-key" exists-action="override"><value>{{compass-api-key}}</value></set-header></inbound><backend><base /></backend><outbound><base /></outbound><on-error><base /></on-error></policies>'
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// OUTPUTS
// ──────────────────────────────────────────────────────────────────────────────

@description('APIM Compass API path')
output apiPath string = compassApi.properties.path

@description('Full Compass endpoint URL on APIM')
output compassEndpointUrl string = '${apim.properties.gatewayUrl}/${compassApi.properties.path}'
