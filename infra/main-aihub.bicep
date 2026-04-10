// ============================================================================
// CPX AI Landing Zone — AI Hub Resource Group
// rg-cpx-aihub-{env}-{region}-{instance}
//
// Deploys: ACR Premium (+ PE + DNS) — shared across all BU subscriptions
//
// Deferred (parameterized toggles):
//   - APIM AI Gateway (Premium) — deployApim = false
//   - Core42 Compass PE          — deployCompassPe = false
//
// In production this deploys to the cpx-ai-hub subscription.
// In sandbox it deploys to the same subscription used for BU testing.
// ============================================================================

targetScope = 'subscription'

// ──────────────────────────────────────────────────────────────────────────────
// PARAMETERS
// ──────────────────────────────────────────────────────────────────────────────

@description('Azure region (e.g., uaenorth, swedencentral)')
param location string

@description('Environment')
@allowed(['dev', 'tst', 'prd'])
param env string = 'dev'

@description('Region abbreviation for naming (e.g., uaen, swc)')
param regionAbbr string

@description('Instance number')
param instance string = '001'

@description('PE subnet resource ID (from BU spoke or hub VNet) for ACR Private Endpoint')
param peSubnetId string

@description('Log Analytics Workspace resource ID for diagnostics')
param lawId string

@description('Resource ID of the privatelink.azurecr.io DNS zone (from BU network RG)')
param acrDnsZoneId string

@description('Deploy APIM AI Gateway (Premium) — requires backend URL configuration')
param deployApim bool = false

@description('Deploy Core42 Compass Private Endpoint — requires PLS resource ID from Core42')
param deployCompassPe bool = false

@description('Core42 Compass Private Link Service resource ID (required when deployCompassPe = true)')
param compassPlsId string = ''

@description('BU managed identity principal IDs that need AcrPull on the shared ACR. Array of objects: [{principalId, name}]')
param acrPullPrincipalIds array = []
// Example: [{ principalId: 'xxxxxxxx-...', name: 'csd-cae' }]

// ──────────────────────────────────────────────────────────────────────────────
// VARIABLES
// ──────────────────────────────────────────────────────────────────────────────

var tags = {
  BusinessUnit: 'PLATFORM'
  Environment: env
  Project: 'cpx-ai-landing-zone'
  ManagedBy: 'Bicep-AVM'
}

var rgName = 'rg-cpx-aihub-${env}-${regionAbbr}-${instance}'
var acrName = 'acrcpx${env}${regionAbbr}${instance}'

// ──────────────────────────────────────────────────────────────────────────────
// RESOURCE GROUP
// ──────────────────────────────────────────────────────────────────────────────

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: rgName
  location: location
  tags: tags
}

// ──────────────────────────────────────────────────────────────────────────────
// STEP 1: AZURE CONTAINER REGISTRY (Premium — shared across all BUs)
//
// Premium required for: Private Endpoints, zone redundancy, geo-replication,
// content trust, repo-scoped tokens, retention policies.
// ──────────────────────────────────────────────────────────────────────────────

module acr 'br/public:avm/res/container-registry/registry:0.12.0' = {
  scope: rg
  name: 'deploy-acr'
  params: {
    name: acrName
    location: location
    tags: tags
    acrSku: 'Premium'
    acrAdminUserEnabled: false
    anonymousPullEnabled: false
    publicNetworkAccess: 'Disabled'
    networkRuleBypassOptions: 'AzureServices'
    networkRuleSetDefaultAction: 'Deny'
    zoneRedundancy: 'Enabled'
    exportPolicyStatus: 'disabled'
    retentionPolicyStatus: 'enabled'
    retentionPolicyDays: 30
    roleAssignments: [for identity in acrPullPrincipalIds: {
      roleDefinitionIdOrName: 'AcrPull'
      principalId: identity.principalId
      principalType: 'ServicePrincipal'
    }]
    privateEndpoints: [
      {
        name: 'pe-acr-cpx-${env}-${regionAbbr}-${instance}'
        subnetResourceId: peSubnetId
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: acrDnsZoneId
            }
          ]
        }
      }
    ]
    diagnosticSettings: [
      {
        workspaceResourceId: lawId
      }
    ]
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// STEP 2: CORE42 COMPASS PRIVATE ENDPOINT (deferred — needs PLS ID from Core42)
//
// Once Core42 provides the Private Link Service resource ID, set:
//   deployCompassPe = true
//   compassPlsId = '/subscriptions/.../providers/Microsoft.Network/privateLinkServices/...'
// ──────────────────────────────────────────────────────────────────────────────

module compassPe 'br/public:avm/res/network/private-endpoint:0.12.0' = if (deployCompassPe && !empty(compassPlsId)) {
  scope: rg
  name: 'deploy-pe-compass'
  params: {
    name: 'pe-compass-cpx-${env}-${regionAbbr}-${instance}'
    location: location
    tags: tags
    subnetResourceId: peSubnetId
    privateLinkServiceConnections: [
      {
        name: 'pls-compass-cpx-${env}-${regionAbbr}-${instance}'
        properties: {
          privateLinkServiceId: compassPlsId
        }
      }
    ]
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// APIM AI GATEWAY — PLACEHOLDER
//
// APIM Premium (~$2,800/mo) is deferred until:
//   1. Core42 Compass backend URL is confirmed
//   2. Cost approval from CPX
//   3. APIM workspace design is finalized (9 BU workspaces)
//
// When ready, set deployApim = true and add APIM module here.
// ──────────────────────────────────────────────────────────────────────────────

// ──────────────────────────────────────────────────────────────────────────────
// OUTPUTS
// ──────────────────────────────────────────────────────────────────────────────

@description('AI Hub Resource Group name')
output rgName string = rg.name

@description('ACR name')
output acrName string = acr.outputs.name

@description('ACR resource ID')
output acrId string = acr.outputs.resourceId

@description('ACR login server (e.g., acrcpxdevswc001.azurecr.io)')
output acrLoginServer string = acr.outputs.loginServer
