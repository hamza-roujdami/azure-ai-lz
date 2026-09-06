metadata description = 'AI Hub: API Management gateway (private ingress) and the Foundry account that hosts the shared model deployments.'

@description('Base name used to derive resource names.')
param baseName string

@description('Location for the hub resources.')
param location string

@description('Tags applied to all resources.')
param tags object = {}

@description('Publisher email for API Management.')
param publisherEmail string

@description('Publisher (organization) name for API Management.')
param publisherName string

@description('API Management SKU. Standard v2 is the default; use Premium/Premium v2 for VNet injection or self-hosted gateways.')
@allowed([
  'StandardV2'
  'PremiumV2'
  'Premium'
  'Developer'
])
param apimSku string = 'StandardV2'

@description('API Management capacity (scale units).')
param apimCapacity int = 1

@description('Name of the API Management API that exposes the hub models.')
param openAiApiName string = 'openai'

@description('URL path of the API Management API that exposes the hub models.')
param openAiApiPath string = 'openai'

@description('Per-subscription token budget enforced by the gateway, in tokens per minute.')
param tokensPerMinute int = 10000

@description('Per-subscription request budget enforced by the gateway, in calls per minute.')
param callsPerMinute int = 300

@description('Require a valid Entra ID token on every gateway call. Needs jwtTenantId and jwtAudience.')
param enableJwtValidation bool = false

@description('Entra ID tenant that issues accepted tokens. Required when enableJwtValidation is true.')
param jwtTenantId string = tenant().tenantId

@description('Audience claim accepted on incoming tokens. Required when enableJwtValidation is true.')
param jwtAudience string = 'https://cognitiveservices.azure.com'

@description('Fully qualified Event Hub namespace that receives usage events. Empty disables usage streaming.')
param usageEventHubNamespaceName string = ''

@description('Event hub that receives usage events.')
param usageEventHubName string = ''

@description('Resource ID of the identity the gateway uses to publish usage events.')
param usageIdentityResourceId string = ''

@description('Client ID of the identity the gateway uses to publish usage events.')
param usageIdentityClientId string = ''

@description('Number of backend failures within the trip interval before the circuit opens.')
param circuitBreakerFailureCount int = 5

@description('Name of the API Management subscription used by the Foundry model connection.')
param foundryConnectionSubscriptionName string = 'foundry-model-connection'

@description('Expose the Anthropic Messages API for Claude models. Claude is not available in every region, so this is off by default.')
param deployAnthropicApi bool = false

@description('Name of the API Management API that exposes Claude models.')
param anthropicApiName string = 'anthropic'

@description('URL path of the API Management API that exposes Claude models.')
param anthropicApiPath string = 'anthropic'

@description('Resource ID of the subnet for the API Management private endpoint.')
param privateEndpointSubnetResourceId string

@description('Resource ID of the subnet delegated to Microsoft.Web/serverFarms, used for API Management outbound VNet integration so the gateway can reach the private Foundry backend.')
param apimSubnetResourceId string

@description('Private DNS zone resource ID for API Management (privatelink.azure-api.net).')
param apimPrivateDnsZoneResourceId string

@description('Private DNS zone resource ID for AI Services.')
param aiServicesPrivateDnsZoneResourceId string

@description('Private DNS zone resource ID for Cognitive Services.')
param cognitiveServicesPrivateDnsZoneResourceId string

@description('Private DNS zone resource ID for OpenAI.')
param openAiPrivateDnsZoneResourceId string

@description('Model deployments created on the hub Foundry account. These are the models the gateway fronts.')
param modelDeployments array = [
  {
    name: 'gpt-4o'
    model: {
      format: 'OpenAI'
      name: 'gpt-4o'
      version: '2024-11-20'
    }
    sku: {
      name: 'Standard'
      capacity: 1
    }
  }
  {
    name: 'text-embedding-3-large'
    model: {
      format: 'OpenAI'
      name: 'text-embedding-3-large'
      version: '1'
    }
    sku: {
      name: 'Standard'
      capacity: 1
    }
  }
]

@description('Legal entity name attested when deploying partner models such as Claude.')
param modelProviderOrganizationName string = 'Contoso'

@description('Industry attested when deploying partner models such as Claude.')
@allowed([
  'education'
  'finance'
  'government'
  'healthcare'
  'manufacturing'
  'media'
  'other'
  'retail'
  'technology'
])
param modelProviderIndustry string = 'technology'

@description('Two-letter ISO 3166-1 country code attested when deploying partner models such as Claude.')
param modelProviderCountryCode string = 'US'

@description('Display name of the hub Foundry project.')
param hubProjectDisplayName string = 'AI Hub Models'

@description('Description of the hub Foundry project.')
param hubProjectDescription string = 'Shared model deployments fronted by the AI gateway.'

var abbrs = loadJsonContent('../abbreviations.json')

// Partner models such as Claude require a provider attestation; OpenAI models must not carry one.
var accountDeployments = [
  for deployment in modelDeployments: deployment.model.format == 'OpenAI'
    ? deployment
    : union(deployment, {
        modelProviderData: {
          industry: modelProviderIndustry
          organizationName: modelProviderOrganizationName
          countryCode: modelProviderCountryCode
        }
      })
]

// Names are fixed up front so the role assignment below can be resolved before deployment starts.
var hubFoundryAccountName = '${abbrs.aiFoundry}${baseName}'
var hubProjectName = '${abbrs.aiFoundryProject}${baseName}'
var apimName = '${abbrs.apiManagement}${baseName}'

// Models only: no agents run here, so this is a plain account with no project or data services.
module hubFoundry 'br/public:avm/res/cognitive-services/account:0.19.0' = {
  name: 'aif-${baseName}'
  params: {
    name: hubFoundryAccountName
    kind: 'AIServices'
    sku: 'S0'
    location: location
    tags: tags
    customSubDomainName: hubFoundryAccountName
    allowProjectManagement: true
    disableLocalAuth: true
    publicNetworkAccess: 'Disabled'
    // The resource provider requires networkAcls whenever public access is disabled.
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
      ipRules: []
      virtualNetworkRules: []
    }
    deployments: accountDeployments
    managedIdentities: {
      systemAssigned: true
    }
    privateEndpoints: [
      {
        subnetResourceId: privateEndpointSubnetResourceId
        service: 'account'
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: aiServicesPrivateDnsZoneResourceId
            }
            {
              privateDnsZoneResourceId: cognitiveServicesPrivateDnsZoneResourceId
            }
            {
              privateDnsZoneResourceId: openAiPrivateDnsZoneResourceId
            }
          ]
        }
      }
    ]
  }
}

module logAnalytics 'br/public:avm/res/operational-insights/workspace:0.16.1' = {
  name: 'law-${baseName}'
  params: {
    name: '${abbrs.logAnalyticsWorkspace}${baseName}'
    location: location
    tags: tags
  }
}

module appInsights 'br/public:avm/res/insights/component:0.8.0' = {
  name: 'appi-${baseName}'
  params: {
    name: '${abbrs.applicationInsights}${baseName}'
    location: location
    tags: tags
    workspaceResourceId: logAnalytics.outputs.resourceId
  }
}

// Optional caller identity check. Left out entirely unless enableJwtValidation is true, because it
// needs a tenant and audience that only the consumer knows.
var jwtPolicy = '''
    <validate-azure-ad-token tenant-id="JWT_TENANT_ID" header-name="Authorization" failed-validation-httpcode="401" failed-validation-error-message="Unauthorized. Provide a valid Entra ID token.">
      <audiences>
        <audience>JWT_AUDIENCE</audience>
      </audiences>
    </validate-azure-ad-token>
'''

// APIM authenticates to Foundry with its own identity, so no keys are stored anywhere.
var apiPolicyTemplate = '''
<policies>
  <inbound>
    <base />
JWT_VALIDATION
    <rate-limit-by-key calls="CALLS_PER_MINUTE" renewal-period="60" counter-key="@(context.Subscription.Id)" remaining-calls-header-name="x-ratelimit-remaining-calls" />
    <authentication-managed-identity resource="https://cognitiveservices.azure.com" output-token-variable-name="msi-access-token" ignore-error="false" />
    <set-header name="Authorization" exists-action="override">
      <value>@("Bearer " + (string)context.Variables["msi-access-token"])</value>
    </set-header>
    <llm-token-limit counter-key="@(context.Subscription.Id)" tokens-per-minute="TOKENS_PER_MINUTE" estimate-prompt-tokens="false" remaining-tokens-header-name="x-ratelimit-remaining-tokens" />
    <llm-emit-token-metric namespace="ai-gateway">
      <dimension name="Subscription" value="@(context.Subscription.Id)" />
      <dimension name="API" value="@(context.Api.Name)" />
    </llm-emit-token-metric>
    <set-backend-service backend-id="BACKEND_ID" />
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
USAGE_LOGGING
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
'''

var streamUsage = !empty(usageEventHubNamespaceName)

// One JSON record per call, so a downstream consumer can build the chargeback ledger.
var usageLogPolicy = '''
    <log-to-eventhub logger-id="usage">@{
      return new JObject(
        new JProperty("timestamp", DateTime.UtcNow.ToString("o")),
        new JProperty("subscriptionId", context.Subscription?.Id ?? "none"),
        new JProperty("apiName", context.Api.Name),
        new JProperty("operation", context.Operation.Name),
        new JProperty("responseCode", context.Response.StatusCode),
        new JProperty("elapsedMs", context.Elapsed.TotalMilliseconds)
      ).ToString();
    }</log-to-eventhub>
'''

var jwtSection = enableJwtValidation
  ? replace(replace(jwtPolicy, 'JWT_TENANT_ID', jwtTenantId), 'JWT_AUDIENCE', jwtAudience)
  : ''

var apiPolicy = replace(
  replace(
    replace(
      replace(apiPolicyTemplate, 'TOKENS_PER_MINUTE', string(tokensPerMinute)),
      'CALLS_PER_MINUTE',
      string(callsPerMinute)
    ),
    'JWT_VALIDATION',
    jwtSection
  ),
  'USAGE_LOGGING',
  streamUsage ? usageLogPolicy : ''
)

var openAiBackendName = 'openai-backend'
var anthropicBackendName = 'anthropic-backend'

// Fail fast instead of queueing behind a backend that is already erroring.
var circuitBreakerRules = [
  {
    name: 'backend-failures'
    acceptRetryAfter: true
    failureCondition: {
      count: circuitBreakerFailureCount
      interval: 'PT1M'
      statusCodeRanges: [
        {
          min: 429
          max: 429
        }
        {
          min: 500
          max: 599
        }
      ]
    }
    tripDuration: 'PT1M'
  }
]

var openAiApi = {
  name: openAiApiName
  displayName: 'Azure OpenAI'
  description: 'OpenAI-compatible surface over the hub Foundry account.'
  path: openAiApiPath
  protocols: [
    'https'
  ]
  serviceUrl: 'https://${hubFoundry.outputs.name}.services.ai.azure.com/openai'
  subscriptionRequired: true
  policies: [
    {
      format: 'xml'
      value: replace(apiPolicy, 'BACKEND_ID', openAiBackendName)
    }
  ]
  operations: [
    {
      name: 'chat-completions'
      displayName: 'Chat completions'
      method: 'POST'
      urlTemplate: '/v1/chat/completions'
    }
    {
      name: 'embeddings'
      displayName: 'Embeddings'
      method: 'POST'
      urlTemplate: '/v1/embeddings'
    }
    {
      name: 'responses'
      displayName: 'Responses'
      method: 'POST'
      urlTemplate: '/v1/responses'
    }
  ]
}

// Claude uses the Anthropic Messages schema, not OpenAI chat completions, so it needs its own API.
var anthropicApi = {
  name: anthropicApiName
  displayName: 'Anthropic Claude'
  description: 'Anthropic Messages surface over the hub Foundry account.'
  path: anthropicApiPath
  protocols: [
    'https'
  ]
  serviceUrl: 'https://${hubFoundry.outputs.name}.services.ai.azure.com/anthropic'
  subscriptionRequired: true
  policies: [
    {
      format: 'xml'
      value: replace(apiPolicy, 'BACKEND_ID', anthropicBackendName)
    }
  ]
  operations: [
    {
      name: 'messages'
      displayName: 'Messages'
      method: 'POST'
      urlTemplate: '/v1/messages'
    }
    {
      name: 'count-tokens'
      displayName: 'Count tokens'
      method: 'POST'
      urlTemplate: '/v1/messages/count_tokens'
    }
  ]
}

module apim 'br/public:avm/res/api-management/service:0.14.4' = {
  name: 'apim-${baseName}'
  params: {
    name: apimName
    location: location
    tags: tags
    publisherEmail: publisherEmail
    publisherName: publisherName
    sku: apimSku
    skuCapacity: apimCapacity
    managedIdentities: {
      systemAssigned: true
      userAssignedResourceIds: streamUsage
        ? [
            usageIdentityResourceId
          ]
        : []
    }
    // Azure rejects creating API Management with public access already disabled, so it stays
    // enabled here and is turned off after the first deployment. See the README.
    publicNetworkAccess: 'Enabled'
    // Outbound VNet integration: without this the gateway calls the Foundry backend from public
    // IPs and is rejected, because the backend has public access disabled.
    subnetResourceId: apimSubnetResourceId
    virtualNetworkType: 'External'
    // Private ingress via a private endpoint. Standard v2 requires public access enabled at
    // creation; disable it post-deploy to make private endpoints the exclusive access method.
    privateEndpoints: [
      {
        subnetResourceId: privateEndpointSubnetResourceId
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: apimPrivateDnsZoneResourceId
            }
          ]
        }
      }
    ]
    loggers: streamUsage
      ? [
          {
            name: 'appinsights'
            type: 'applicationInsights'
            targetResourceId: appInsights.outputs.resourceId
            credentials: {
              instrumentationKey: appInsights.outputs.instrumentationKey
            }
          }
          {
            name: 'usage'
            type: 'azureEventHub'
            description: 'Streams per-call usage events to the ledger.'
            credentials: {
              endpointAddress: '${usageEventHubNamespaceName}.servicebus.windows.net'
              identityClientId: usageIdentityClientId
              name: usageEventHubName
            }
          }
        ]
      : [
          {
            name: 'appinsights'
            type: 'applicationInsights'
            targetResourceId: appInsights.outputs.resourceId
            credentials: {
              instrumentationKey: appInsights.outputs.instrumentationKey
            }
          }
        ]
    apis: deployAnthropicApi ? [openAiApi, anthropicApi] : [openAiApi]
    backends: deployAnthropicApi
      ? [
          {
            name: openAiBackendName
            url: 'https://${hubFoundry.outputs.name}.services.ai.azure.com/openai'
            type: 'Single'
            circuitBreaker: {
              rules: circuitBreakerRules
            }
          }
          {
            name: anthropicBackendName
            url: 'https://${hubFoundry.outputs.name}.services.ai.azure.com/anthropic'
            type: 'Single'
            circuitBreaker: {
              rules: circuitBreakerRules
            }
          }
        ]
      : [
          {
            name: openAiBackendName
            url: 'https://${hubFoundry.outputs.name}.services.ai.azure.com/openai'
            type: 'Single'
            circuitBreaker: {
              rules: circuitBreakerRules
            }
          }
        ]
    subscriptions: [
      {
        name: foundryConnectionSubscriptionName
        displayName: 'Foundry model connection'
        scope: '/apis'
      }
    ]
  }
}

// Lets the gateway call the hub Foundry account without keys.
resource hubFoundryAccount 'Microsoft.CognitiveServices/accounts@2025-06-01' existing = {
  name: hubFoundryAccountName
}

// The account module does not create projects, so the hub project is declared here.
resource hubProject 'Microsoft.CognitiveServices/accounts/projects@2025-06-01' = {
  parent: hubFoundryAccount
  name: hubProjectName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: hubProjectDisplayName
    description: hubProjectDescription
  }
  dependsOn: [
    hubFoundry
  ]
}

resource apimToFoundryRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: hubFoundryAccount
  name: guid(hubFoundryAccount.id, apimName, 'cognitive-services-openai-user')
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
    )
    principalId: apim.outputs.systemAssignedMIPrincipalId!
    principalType: 'ServicePrincipal'
  }
}

// The Anthropic data plane sits outside the OpenAI role's scope, so it needs the broader role.
resource apimToFoundryInferenceRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (deployAnthropicApi) {
  scope: hubFoundryAccount
  name: guid(hubFoundryAccount.id, apimName, 'cognitive-services-user')
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'a97b65f3-24c7-4388-baec-2e87135dc908'
    )
    principalId: apim.outputs.systemAssignedMIPrincipalId!
    principalType: 'ServicePrincipal'
  }
}

@description('Name of the API Management service.')
output apimName string = apim.outputs.name

@description('Resource ID of the API Management service.')
output apimResourceId string = apim.outputs.resourceId

@description('Resource ID of the Log Analytics workspace.')
output logAnalyticsResourceId string = logAnalytics.outputs.resourceId

@description('Resource ID of the Application Insights component.')
output appInsightsResourceId string = appInsights.outputs.resourceId

@description('Name of the hub Foundry (AI Services) account that hosts the shared models.')
output hubFoundryName string = hubFoundry.outputs.name

@description('Principal ID of the gateway system-assigned identity.')
output apimPrincipalId string = apim.outputs.systemAssignedMIPrincipalId!

@description('Name of the hub Foundry project.')
output hubProjectName string = hubProject.name

@description('Foundry API endpoint of the hub project.')
output hubProjectEndpoint string = 'https://${hubFoundryAccountName}.services.ai.azure.com/api/projects/${hubProjectName}'

@description('Base URL of the OpenAI-compatible API exposed by the gateway.')
output openAiGatewayUrl string = 'https://${apim.outputs.name}.azure-api.net/${openAiApiPath}/v1'

@description('Base URL of the Anthropic Messages API exposed by the gateway, empty when not deployed.')
output anthropicGatewayUrl string = deployAnthropicApi
  ? 'https://${apim.outputs.name}.azure-api.net/${anthropicApiPath}/v1'
  : ''

@description('Name of the API Management subscription used by the Foundry model connection.')
output foundryConnectionSubscriptionName string = foundryConnectionSubscriptionName
