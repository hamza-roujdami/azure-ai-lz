// ============================================================================
// Compass API Setup on Existing APIM
//
// Configures an existing APIM instance as an OpenAI-compatible proxy
// to Core42 Compass. Does NOT provision APIM, PE, VNet, or KV.
//
// Prerequisites (already done by customer):
//   1. APIM provisioned (portal or IaC) with system-assigned MI enabled
//   2. Compass PE approved (10.0.20.7)
//   3. Hub Key Vault with compass-api-key secret stored
//
// Deploys:
//   Step 1: RBAC — APIM MI → Key Vault Secrets User
//   Step 2: Named Value (compass-api-key → Key Vault reference)
//   Step 3: API (compass-api, path /compass, backend: api.core42.ai/openai)
//   Step 4: 5 Operations + 5 Policies:
//           - ListDeployments  (GET  /deployments)                      → static model list
//           - GetDeployment    (GET  /deployments/{name})               → dynamic model detail
//           - ChatCompletions  (POST /deployments/{id}/chat/completions)→ forward + inject key
//           - Embeddings       (POST /deployments/{id}/embeddings)      → forward + inject key
//           - Score            (POST /deployments/{id}/score)           → forward + inject key
//   Step 5: Product + Subscription (generates APIM key for consumers)
//
// Models (Core42 Compass — April 2026):
//   Chat:       gpt-5.1, gpt-4.1-mini, o4-mini, k2-think-core42
//   Embeddings: text-embedding-3-large
//   Reranker:   qwen3-reranker
//
// Usage:
//   az deployment group create -g <HUB_RG> \
//     -f main.bicep \
//     -p apimName=<APIM_NAME> \
//     -p keyVaultName=<HUB_KV_NAME>
// ============================================================================

// ──────────────────────────────────────────────────────────────────────────────
// PARAMETERS
// ──────────────────────────────────────────────────────────────────────────────

@description('Existing APIM resource name')
param apimName string

@description('Existing Hub Key Vault name (must contain compass-api-key secret)')
param keyVaultName string

@description('Backend URL for Core42 Compass (use PE FQDN or IP if DNS not configured)')
param backendUrl string = 'https://api.core42.ai/openai'

@description('Secret name in Key Vault for the Compass API key')
param compassApiKeySecretName string = 'compass-api-key'

@description('List of Compass model deployment names')
param compassModels array = [
  'gpt-5.1'
  'gpt-4.1-mini'
  'o4-mini'
  'text-embedding-3-large'
  'qwen3-reranker'
  'k2-think-core42'
]

@description('Product name for the APIM subscription')
param productName string = 'cpx-compass'

@description('Product display name')
param productDisplayName string = 'CPX Compass'

@description('APIM system-assigned managed identity principal ID (run: az apim show -n <name> -g <rg> --query identity.principalId -o tsv)')
param apimPrincipalId string

// ──────────────────────────────────────────────────────────────────────────────
// EXISTING RESOURCES
// ──────────────────────────────────────────────────────────────────────────────

resource apim 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimName
}

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

// ──────────────────────────────────────────────────────────────────────────────
// STEP 1: APIM → KV Secrets User (if not already assigned)
// ──────────────────────────────────────────────────────────────────────────────

// Key Vault Secrets User — 4633458b-17de-408a-b874-0445c86b69e6
resource kvSecretsRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(kv.id, apim.id, '4633458b-17de-408a-b874-0445c86b69e6')
  scope: kv
  properties: {
    principalId: apimPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '4633458b-17de-408a-b874-0445c86b69e6'
    )
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// STEP 2: Named Value — Compass API key from Key Vault
// ──────────────────────────────────────────────────────────────────────────────

resource compassApiKeyNamedValue 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apim
  name: 'compass-api-key'
  properties: {
    displayName: 'compass-api-key'
    secret: true
    keyVault: {
      secretIdentifier: '${kv.properties.vaultUri}secrets/${compassApiKeySecretName}'
    }
  }
  dependsOn: [kvSecretsRole]
}

// ──────────────────────────────────────────────────────────────────────────────
// STEP 3: Compass API — OpenAI-compatible proxy
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
// STEP 4: Operations + Policies
// ──────────────────────────────────────────────────────────────────────────────

// --- Build the static model JSON for ListDeployments ---
var modelEntries = [
  for model in compassModels: '{"name":"${model}","properties":{"model":{"format":"OpenAI","name":"${model}","version":""}}}'
]
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
// Returns model details dynamically from the URL path.

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
    value: loadTextContent('policies/get-deployment.xml')
  }
}

// --- ChatCompletions: POST /deployments/{deployment-id}/chat/completions ---
// Forwards to Compass backend, injects API key from Key Vault.

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

var forwardWithKeyPolicy = loadTextContent('policies/forward-with-key.xml')

resource chatCompletionsPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2024-05-01' = {
  parent: chatCompletionsOp
  name: 'policy'
  dependsOn: [compassApiKeyNamedValue]
  properties: {
    format: 'rawxml'
    value: forwardWithKeyPolicy
  }
}

// --- Embeddings: POST /deployments/{deployment-id}/embeddings ---
// Forwards embedding requests to Compass backend, injects API key from KV.

resource embeddingsOp 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  parent: compassApi
  name: 'Embeddings'
  properties: {
    displayName: 'Embeddings'
    method: 'POST'
    urlTemplate: '/deployments/{deployment-id}/embeddings'
    templateParameters: [
      {
        name: 'deployment-id'
        type: 'string'
        required: true
      }
    ]
  }
}

resource embeddingsPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2024-05-01' = {
  parent: embeddingsOp
  name: 'policy'
  dependsOn: [compassApiKeyNamedValue]
  properties: {
    format: 'rawxml'
    value: forwardWithKeyPolicy
  }
}

// --- Score: POST /deployments/{deployment-id}/score ---
// Forwards reranker/scoring requests to Compass backend (e.g., qwen3-reranker).

resource scoreOp 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  parent: compassApi
  name: 'Score'
  properties: {
    displayName: 'Score'
    method: 'POST'
    urlTemplate: '/deployments/{deployment-id}/score'
    templateParameters: [
      {
        name: 'deployment-id'
        type: 'string'
        required: true
      }
    ]
  }
}

resource scorePolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2024-05-01' = {
  parent: scoreOp
  name: 'policy'
  dependsOn: [compassApiKeyNamedValue]
  properties: {
    format: 'rawxml'
    value: forwardWithKeyPolicy
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// STEP 5: Product + Subscription
// ──────────────────────────────────────────────────────────────────────────────

resource product 'Microsoft.ApiManagement/service/products@2024-05-01' = {
  parent: apim
  name: productName
  properties: {
    displayName: productDisplayName
    subscriptionRequired: true
    approvalRequired: false
    state: 'published'
  }
}

resource productApi 'Microsoft.ApiManagement/service/products/apis@2024-05-01' = {
  parent: product
  name: compassApi.name
}

resource subscription 'Microsoft.ApiManagement/service/subscriptions@2024-05-01' = {
  parent: apim
  name: '${productName}-sub'
  properties: {
    displayName: '${productDisplayName} Subscription'
    scope: product.id
    state: 'active'
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// OUTPUTS
// ──────────────────────────────────────────────────────────────────────────────

@description('Compass API endpoint on APIM')
output compassEndpointUrl string = '${apim.properties.gatewayUrl}/${compassApi.properties.path}'

@description('APIM Subscription ID (use to retrieve the key)')
output subscriptionResourceId string = subscription.id

@description('Models configured')
output configuredModels array = compassModels
