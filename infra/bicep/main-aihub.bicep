// ============================================================================
// Azure AI Landing Zone — AI Hub Resource Group (separate subscription)
// rg-{org}-aihub-{env}-{region}-{instance}
//
// Self-contained: creates its own VNet, subnets, DNS zones, and LAW.
// Deploys to a SEPARATE subscription from BU spokes.
//
// Deploys: Hub VNet + subnets, ACR Premium (+ PE + DNS), Hub KV, Hub UAMI
//
// Toggleable:
//   - APIM AI Gateway (Premium v2) — deployApim = false
//   - Core42 Compass PE            — deployCompassPe = false
//   - Compass API on APIM          — deployCompassApi = false
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

@description('Organization prefix for resource naming (e.g., cpx, contoso, myorg)')
param org string

@description('Hub VNet address prefix')
param hubVnetAddressPrefix string = '10.100.0.0/22'

@description('Hub PE subnet address prefix')
param hubPeSubnetPrefix string = '10.100.0.0/26'

@description('Hub APIM subnet address prefix (needed when deployApim = true)')
param hubApimSubnetPrefix string = '10.100.1.0/24'

@description('Deploy APIM AI Gateway (Premium v2) — ~$700/mo')
param deployApim bool = false

@description('APIM publisher email (required when deployApim = true)')
param apimPublisherEmail string = 'admin@example.com'

@description('APIM publisher name (required when deployApim = true)')
param apimPublisherName string = 'Platform Team'

@description('Deploy Core42 Compass Private Endpoint — requires Resource ID + group ID from Core42')
param deployCompassPe bool = false

@description('Deploy Compass API configuration on APIM (requires deployApim = true)')
param deployCompassApi bool = false

@description('Core42 Compass API key secret name in Hub Key Vault')
param compassApiKeySecretName string = 'compass-api-key'

@description('Core42 Compass backend URL')
param compassBackendUrl string = 'https://api.core42.ai/openai'

@description('List of Compass model names available via APIM')
param compassModels array = [
  'jais-70b'
  'falcon-180b'
]

@description('Core42 Compass App Gateway resource ID (provided by Compass team)')
param compassResourceId string = ''
// Compass guide value: /subscriptions/194bbe9f-b2fd-4370-b3c5-17d1d90ffee4/resourceGroups/saas-compass-prodapp-rg/providers/Microsoft.Network/applicationGateways/SaaS-cmpss-prod-agw01-agw-uan

@description('Core42 Compass sub-resource / group ID (provided by Compass team)')
param compassGroupId string = 'fep1'

@description('Array of BU identities that need AcrPull on the hub ACR. Each entry: {name: "csd", principalId: "xxx"}')
param buAcrPullPrincipals array = []

// ──────────────────────────────────────────────────────────────────────────────
// VARIABLES
// ──────────────────────────────────────────────────────────────────────────────

var tags = {
  BusinessUnit: 'PLATFORM'
  Environment: env
  Project: 'ai-landing-zone'
  ManagedBy: 'Bicep-AVM'
}

var rgName = 'rg-${org}-aihub-${env}-${regionAbbr}-${instance}'
var hubVnetName = 'vnet-${org}-hub-${env}-${regionAbbr}-${instance}'
var hubLawName = 'law-${org}-hub-${env}-${regionAbbr}-${instance}'
var acrName = 'acr${org}${env}${regionAbbr}${instance}'
var apimName = 'apim-${org}-${env}-${regionAbbr}-${instance}'
var hubKvName = 'kv-${org}-hub-${env}-${regionAbbr}-${instance}'
var hubUamiName = 'id-${org}-hub-cmk-${env}-${regionAbbr}-${instance}'
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
// HUB NETWORK — VNet, subnets, DNS zones, Log Analytics
//
// Self-contained: Hub has its own VNet with PE + APIM subnets.
// BU spokes reach Hub resources through the platform firewall (no VNet peering).
// Private DNS zones are created here and linked to the Hub VNet.
// Platform team must add VNet links to BU spoke VNets for DNS resolution.
// ──────────────────────────────────────────────────────────────────────────────

module hubVnet 'br/public:avm/res/network/virtual-network:0.7.0' = {
  scope: rg
  name: 'deploy-hub-vnet'
  params: {
    name: hubVnetName
    location: location
    tags: tags
    addressPrefixes: [hubVnetAddressPrefix]
    subnets: [
      {
        name: 'snet-pe'
        addressPrefix: hubPeSubnetPrefix
      }
      {
        name: 'snet-apim'
        addressPrefix: hubApimSubnetPrefix
      }
    ]
  }
}

module hubLaw 'br/public:avm/res/operational-insights/workspace:0.12.0' = {
  scope: rg
  name: 'deploy-hub-law'
  params: {
    name: hubLawName
    location: location
    tags: tags
  }
}

module acrDnsZone 'br/public:avm/res/network/private-dns-zone:0.7.0' = {
  scope: rg
  name: 'deploy-dns-acr'
  params: {
    name: 'privatelink.azurecr.io'
    tags: tags
    virtualNetworkLinks: [
      {
        virtualNetworkResourceId: hubVnet.outputs.resourceId
        registrationEnabled: false
      }
    ]
  }
}

module kvDnsZone 'br/public:avm/res/network/private-dns-zone:0.7.0' = {
  scope: rg
  name: 'deploy-dns-kv'
  params: {
    name: 'privatelink.vaultcore.azure.net'
    tags: tags
    virtualNetworkLinks: [
      {
        virtualNetworkResourceId: hubVnet.outputs.resourceId
        registrationEnabled: false
      }
    ]
  }
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
        workspaceResourceId: hubLaw.outputs.resourceId
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
        name: 'pe-acr-${org}-${env}-${regionAbbr}-${instance}'
        subnetResourceId: hubVnet.outputs.subnetResourceIds[0] // snet-pe
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: acrDnsZone.outputs.resourceId
            }
          ]
        }
      }
    ]
    diagnosticSettings: [
      {
        workspaceResourceId: hubLaw.outputs.resourceId
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
    name: 'pe-compass-${org}-${env}-${regionAbbr}-${instance}'
    location: location
    tags: tags
    subnetResourceId: hubVnet.outputs.subnetResourceIds[0] // snet-pe
    compassResourceId: compassResourceId
    compassGroupId: compassGroupId
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// STEP 4: APIM AI GATEWAY (Premium v2 — toggle)
//
// Premium v2: ~$700/mo (vs $2,800 classic Premium)
//   ✓ Workspaces (1 per BU)
//   ✓ Full VNet injection (no public IP)
//   ✓ Availability zones
//   ✓ Private endpoints
//
// VNet injection uses snet-apim from the Hub VNet.
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
    lawId: hubLaw.outputs.resourceId
    subnetResourceId: hubVnet.outputs.subnetResourceIds[1] // snet-apim
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// STEP 5: COMPASS API ON APIM (operations + policies)
//
// Configures APIM as an OpenAI-compatible proxy to Core42 Compass:
//   - ListDeployments: returns available models (static JSON)
//   - GetDeployment: returns model details (dynamic from URL)
//   - ChatCompletions: forwards to Compass, injects API key from KV
//
// Requires: Compass API key stored in Hub Key Vault as a secret.
// APIM reads it via Named Value (Key Vault reference, system MI).
//
// Prerequisites:
//   1. Store Compass API key: az keyvault secret set --vault-name <hubKv> --name compass-api-key --value <key>
//   2. APIM system MI needs Key Vault Secrets User role on Hub KV
// ──────────────────────────────────────────────────────────────────────────────

// Grant APIM system MI read access to Hub KV secrets (for Named Value)
module apimKvRole 'modules/aihub/apim-kv-role.bicep' = if (deployApim && deployCompassApi) {
  scope: rg
  name: 'deploy-apim-kv-secrets-role'
  params: {
    keyVaultName: hubKvName
    #disable-next-line BCP318
    principalId: apim.outputs.principalId
  }
  dependsOn: [hubKeyVault]
}

module compassApi 'modules/aihub/apim-compass-api.bicep' = if (deployApim && deployCompassApi) {
  scope: rg
  name: 'deploy-apim-compass-api'
  params: {
    #disable-next-line BCP318
    apimName: apim.outputs.apimName
    backendUrl: compassBackendUrl
    keyVaultUri: hubKeyVault.outputs.uri
    compassApiKeySecretName: compassApiKeySecretName
    models: compassModels
  }
  dependsOn: [apimKvRole]
}

// ──────────────────────────────────────────────────────────────────────────────
// STEP 6: ACR PULL ROLE ASSIGNMENTS (BU identities → hub ACR)
//
// Each BU subscription creates a UAMI for Container Apps (id-{bu}-aca).
// That UAMI needs AcrPull on the hub ACR to pull container images.
//
// In a firewall-routed hub-spoke topology (no VNet peering), traffic flows:
//   BU spoke ACA → UDR → Platform Firewall → AI Hub ACR PE (port 443)
//
// The platform firewall must allow:
//   Source: snet-aca / snet-foundry-agents (BU spokes)
//   Destination: ACR PE private IP (AI Hub snet-pe)
//   Port: 443 (TCP)
//
// Docs:
//   - ACR Private Link: https://learn.microsoft.com/azure/container-registry/container-registry-private-link
//   - ACR Firewall rules: https://learn.microsoft.com/azure/container-registry/container-registry-firewall-access-rules
//   - Container Apps networking: https://learn.microsoft.com/azure/container-apps/networking
// ──────────────────────────────────────────────────────────────────────────────

module acrPullRoles 'modules/aihub/acr-pull-role.bicep' = [for p in buAcrPullPrincipals: {
  scope: rg
  name: 'acr-pull-${p.name}'
  params: {
    acrName: acr.outputs.name
    principalId: p.principalId
  }
}]

// ──────────────────────────────────────────────────────────────────────────────
// OUTPUTS
// ──────────────────────────────────────────────────────────────────────────────

@description('AI Hub Resource Group name')
output rgName string = rg.name

@description('Hub VNet resource ID')
output hubVnetId string = hubVnet.outputs.resourceId

@description('Hub PE subnet resource ID')
output hubPeSubnetId string = hubVnet.outputs.subnetResourceIds[0]

@description('Hub LAW resource ID')
output hubLawId string = hubLaw.outputs.resourceId

@description('ACR name')
output acrName string = acr.outputs.name

@description('ACR resource ID')
output acrId string = acr.outputs.resourceId

@description('ACR login server (e.g., acrorgdevswc001.azurecr.io)')
output acrLoginServer string = acr.outputs.loginServer

@description('APIM name (empty if not deployed)')
#disable-next-line BCP318
output apimName string = deployApim ? apim.outputs.apimName : ''

@description('APIM gateway URL (empty if not deployed)')
#disable-next-line BCP318
output apimGatewayUrl string = deployApim ? apim.outputs.gatewayUrl : ''

@description('Compass API endpoint on APIM (empty if not deployed)')
#disable-next-line BCP318
output compassEndpointUrl string = (deployApim && deployCompassApi) ? compassApi.outputs.compassEndpointUrl : ''
