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

@description('Deploy APIM AI Gateway (Premium v2) — ~$700/mo')
param deployApim bool = false

@description('APIM publisher email (required when deployApim = true)')
param apimPublisherEmail string = 'platform@cpx.ae'

@description('APIM publisher name (required when deployApim = true)')
param apimPublisherName string = 'CPX Platform Team'

@description('APIM subnet resource ID for VNet injection (from Phase 1 — snet-apim)')
param apimSubnetId string = ''

@description('Deploy Core42 Compass Private Endpoint — requires Resource ID + group ID from Core42')
param deployCompassPe bool = false

@description('Core42 Compass App Gateway resource ID (provided by Compass team)')
param compassResourceId string = ''
// Compass guide value: /subscriptions/194bbe9f-b2fd-4370-b3c5-17d1d90ffee4/resourceGroups/saas-compass-prodapp-rg/providers/Microsoft.Network/applicationGateways/SaaS-cmpss-prod-agw01-agw-uan

@description('Core42 Compass sub-resource / group ID (provided by Compass team)')
param compassGroupId string = 'fep1'

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
var apimName = 'apim-cpx-${env}-${regionAbbr}-${instance}'
var hubKvName = 'kv-cpx-hub-${env}-${regionAbbr}-${instance}'
var hubUamiName = 'id-cpx-hub-cmk-${env}-${regionAbbr}-${instance}'
var cmkKeyName = 'cmk-hub-${env}'

// ──────────────────────────────────────────────────────────────────────────────
// RESOURCE GROUP
// ──────────────────────────────────────────────────────────────────────────────

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: rgName
  location: location
  tags: tags
}

// ──────────────────────────────────────────────────────────────────────────────
// STEP 1: CMK IDENTITY + KEY VAULT (for ACR encryption)
// ──────────────────────────────────────────────────────────────────────────────

module hubCmkIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.0' = {
  scope: rg
  name: 'deploy-hub-cmk-uami'
  params: {
    name: hubUamiName
    location: location
    tags: tags
  }
}

module hubKeyVault 'br/public:avm/res/key-vault/vault:0.13.3' = {
  scope: rg
  name: 'deploy-hub-kv'
  params: {
    name: hubKvName
    location: location
    tags: tags
    sku: 'standard'
    enableRbacAuthorization: true
    enableSoftDelete: true
    enablePurgeProtection: true
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
    keys: [
      {
        name: cmkKeyName
        kty: 'RSA'
        keySize: 2048
      }
    ]
    roleAssignments: [
      {
        roleDefinitionIdOrName: 'Key Vault Crypto Service Encryption User'
        principalId: hubCmkIdentity.outputs.principalId
        principalType: 'ServicePrincipal'
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
// STEP 2: AZURE CONTAINER REGISTRY (Premium — shared across all BUs)
//
// Premium required for: Private Endpoints, zone redundancy, geo-replication,
// content trust, repo-scoped tokens, retention policies.
// CMK: encrypted with RSA-2048 key from Hub Key Vault via UAMI.
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
    managedIdentities: {
      userAssignedResourceIds: [hubCmkIdentity.outputs.resourceId]
    }
    customerManagedKey: {
      keyVaultResourceId: hubKeyVault.outputs.resourceId
      keyName: cmkKeyName
      userAssignedIdentityResourceId: hubCmkIdentity.outputs.resourceId
    }
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
// STEP 3: CORE42 COMPASS PRIVATE ENDPOINT (manual connection — needs approval)
//
// Core42 Compass uses a cross-tenant PE to their Application Gateway.
// This is a MANUAL connection — after deployment, Compass team reviews and
// approves the PE (up to 24 hours). Until approved, status = 'Pending'.
//
// From Compass guide:
//   Resource ID: /subscriptions/194bbe9f-.../applicationGateways/SaaS-cmpss-prod-agw01-agw-uan
//   Sub-resource: fep1
//
// To enable:
//   deployCompassPe = true
//   compassResourceId = '<Resource ID from Compass team>'
//   compassGroupId = 'fep1'
// ──────────────────────────────────────────────────────────────────────────────

module compassPe 'modules/aihub/compass-pe.bicep' = if (deployCompassPe && !empty(compassResourceId)) {
  scope: rg
  name: 'deploy-pe-compass'
  params: {
    name: 'pe-compass-cpx-${env}-${regionAbbr}-${instance}'
    location: location
    tags: tags
    subnetResourceId: peSubnetId
    compassResourceId: compassResourceId
    compassGroupId: compassGroupId
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// STEP 4: APIM AI GATEWAY (Premium v2 — toggle)
//
// Premium v2: ~$700/mo (vs $2,800 classic Premium)
//   ✓ Workspaces (1 per BU: ws-csd, ws-crs, etc.)
//   ✓ Full VNet injection (no public IP) — in production via main-aihub-cpx.bicep
//   ✓ Availability zones
//   ✓ Private endpoints
//
// In sandbox: deployed without VNet injection (no dedicated APIM subnet).
// In production: main-aihub-cpx.bicep uses snet-apim for full VNet injection.
//
// Workspaces + APIs + backends are configured after deployment (not in IaC).
// ──────────────────────────────────────────────────────────────────────────────

module apim 'modules/aihub/apim-premiumv2.bicep' = if (deployApim) {
  scope: rg
  name: 'deploy-apim'
  params: {
    name: apimName
    location: location
    tags: tags
    publisherEmail: apimPublisherEmail
    publisherName: apimPublisherName
    lawId: lawId
    subnetResourceId: apimSubnetId
  }
}

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

@description('APIM name (empty if not deployed)')
#disable-next-line BCP318
output apimName string = deployApim ? apim.outputs.apimName : ''

@description('APIM gateway URL (empty if not deployed)')
#disable-next-line BCP318
output apimGatewayUrl string = deployApim ? apim.outputs.gatewayUrl : ''
