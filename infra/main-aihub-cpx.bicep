// ============================================================================
// CPX AI Landing Zone — AI Hub (Production)
// Subscription: cpx-ai-hub
//
// This is the PRODUCTION template for CPX's centralized AI Hub subscription.
// It deploys EVERYTHING in one file: networking + shared services.
//
// Deploys:
//   RG1: rg-cpx-hub-network-{env}-{region}-{instance}
//     - Hub VNet (2 subnets: snet-pe, snet-apim)
//     - NSGs per subnet
//     - Private DNS zones (ACR + APIM)
//     - Log Analytics Workspace
//     - VNet peerings to BU spokes (parameterized)
//
//   RG2: rg-cpx-aihub-{env}-{region}-{instance}
//     - ACR Premium (+ PE + DNS)
//     - Core42 Compass PE (toggle — needs PLS ID from Core42)
//     - APIM Premium (toggle — needs cost approval + backend URL)
//
// For sandbox testing (single sub, no hub VNet), use main-aihub.bicep instead.
// ============================================================================

targetScope = 'subscription'

// ──────────────────────────────────────────────────────────────────────────────
// PARAMETERS — General
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

// ──────────────────────────────────────────────────────────────────────────────
// PARAMETERS — Networking
// ──────────────────────────────────────────────────────────────────────────────

@description('Hub VNet address space')
param hubVnetAddressPrefix string = '10.0.0.0/22'

@description('PE subnet prefix (ACR PE, Compass PE)')
param peSubnetPrefix string = '10.0.0.0/25'

@description('APIM subnet prefix (/24 minimum for VNet injection)')
param apimSubnetPrefix string = '10.0.1.0/24'

@description('BU spoke VNet resource IDs to peer with the hub (array of objects with vnetId and name)')
param spokeVnetPeerings array = []
// Example: [{ vnetId: '/subscriptions/.../virtualNetworks/vnet-csd-dev-uaen-001', name: 'csd' }]

// ──────────────────────────────────────────────────────────────────────────────
// PARAMETERS — Feature Toggles
// ──────────────────────────────────────────────────────────────────────────────

@description('Deploy APIM AI Gateway (Premium) — ~$2,800/mo, requires backend URL')
param deployApim bool = false

@description('Deploy Core42 Compass Private Endpoint — requires Resource ID + group ID from Core42')
param deployCompassPe bool = false

@description('Core42 Compass App Gateway resource ID (provided by Compass team)')
param compassResourceId string = ''
// Compass guide value: /subscriptions/194bbe9f-.../applicationGateways/SaaS-cmpss-prod-agw01-agw-uan

@description('Core42 Compass sub-resource / group ID (provided by Compass team)')
param compassGroupId string = 'fep1'

@description('APIM publisher email (required when deployApim = true)')
param apimPublisherEmail string = 'platform@cpx.ae'

@description('APIM publisher name (required when deployApim = true)')
param apimPublisherName string = 'CPX Platform Team'

// ──────────────────────────────────────────────────────────────────────────────
// VARIABLES
// ──────────────────────────────────────────────────────────────────────────────

var tags = {
  BusinessUnit: 'PLATFORM'
  Environment: env
  Project: 'cpx-ai-landing-zone'
  ManagedBy: 'Bicep-AVM'
}

// Resource Group names
var networkRgName = 'rg-cpx-hub-network-${env}-${regionAbbr}-${instance}'
var hubRgName = 'rg-cpx-aihub-${env}-${regionAbbr}-${instance}'

// Resource names
var vnetName = 'vnet-cpx-hub-${env}-${regionAbbr}-${instance}'
var lawName = 'law-cpx-hub-${env}-${regionAbbr}-${instance}'
var nsgPeName = 'nsg-cpx-hub-pe-${env}-${regionAbbr}-${instance}'
var nsgApimName = 'nsg-cpx-hub-apim-${env}-${regionAbbr}-${instance}'
var acrName = 'acrcpx${env}${regionAbbr}${instance}'
var apimName = 'apim-cpx-${env}-${regionAbbr}-${instance}'
var hubKvName = 'kv-cpx-hub-${env}-${regionAbbr}-${instance}'
var hubUamiName = 'id-cpx-hub-cmk-${env}-${regionAbbr}-${instance}'
var cmkKeyName = 'cmk-hub-${env}'

// Private DNS zones for the hub
var privateDnsZones = [
  'privatelink.azurecr.io'
]

// APIM DNS zone — only created when APIM is deployed
var apimDnsZone = 'privatelink.azure-api.net'

// ============================================================================
// RG1: HUB NETWORKING
// ============================================================================

resource networkRg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: networkRgName
  location: location
  tags: tags
}

// ──────────────────────────────────────────────────────────────────────────────
// NSGs
// ──────────────────────────────────────────────────────────────────────────────

module nsgPe 'br/public:avm/res/network/network-security-group:0.5.0' = {
  scope: networkRg
  name: 'deploy-nsg-hub-pe'
  params: {
    name: nsgPeName
    location: location
    tags: tags
    securityRules: [
      {
        name: 'DenyAllInbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

module nsgApim 'br/public:avm/res/network/network-security-group:0.5.0' = {
  scope: networkRg
  name: 'deploy-nsg-hub-apim'
  params: {
    name: nsgApimName
    location: location
    tags: tags
    securityRules: [
      // APIM management endpoint — required for VNet-injected APIM
      {
        name: 'AllowApimManagement'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'ApiManagement'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '3443'
        }
      }
      // Azure Load Balancer health probes
      {
        name: 'AllowAzureLoadBalancer'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '6390'
        }
      }
      // Inbound from spoke VNets to APIM (HTTPS)
      {
        name: 'AllowVNetInbound443'
        properties: {
          priority: 200
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '443'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// HUB VNET + 2 SUBNETS
// ──────────────────────────────────────────────────────────────────────────────

module hubVnet 'br/public:avm/res/network/virtual-network:0.7.0' = {
  scope: networkRg
  name: 'deploy-hub-vnet'
  params: {
    name: vnetName
    location: location
    tags: tags
    addressPrefixes: [hubVnetAddressPrefix]
    subnets: [
      {
        name: 'snet-pe'
        addressPrefix: peSubnetPrefix
        networkSecurityGroupResourceId: nsgPe.outputs.resourceId
        privateEndpointNetworkPolicies: 'Enabled'
      }
      {
        name: 'snet-apim'
        addressPrefix: apimSubnetPrefix
        networkSecurityGroupResourceId: nsgApim.outputs.resourceId
      }
    ]
    // Hub-to-spoke peerings
    peerings: [for (spoke, i) in spokeVnetPeerings: {
      name: 'peer-hub-to-${spoke.name}'
      remoteVirtualNetworkResourceId: spoke.vnetId
      allowForwardedTraffic: true
      allowGatewayTransit: true
      allowVirtualNetworkAccess: true
    }]
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// PRIVATE DNS ZONES (linked to hub VNet + all spoke VNets)
//
// DNS zones live in the hub. Every spoke VNet is linked so that PEs in the
// hub resolve correctly from spoke workloads.
// ──────────────────────────────────────────────────────────────────────────────

// VNet links for DNS zones: hub VNet + all spoke VNets
var hubVnetLink = [
  {
    virtualNetworkResourceId: hubVnet.outputs.resourceId
    registrationEnabled: false
  }
]
var spokeLinks = map(spokeVnetPeerings, spoke => {
  virtualNetworkResourceId: spoke.vnetId
  registrationEnabled: false
})
var allVnetLinks = concat(hubVnetLink, spokeLinks)

@batchSize(1)
module dnsZones 'br/public:avm/res/network/private-dns-zone:0.7.0' = [for zone in privateDnsZones: {
  scope: networkRg
  name: 'deploy-dns-${replace(zone, '.', '-')}'
  params: {
    name: zone
    location: 'global'
    tags: tags
    virtualNetworkLinks: allVnetLinks
  }
}]

// APIM DNS zone — only when APIM is deployed
module dnsZoneApim 'br/public:avm/res/network/private-dns-zone:0.7.0' = if (deployApim) {
  scope: networkRg
  name: 'deploy-dns-${replace(apimDnsZone, '.', '-')}'
  params: {
    name: apimDnsZone
    location: 'global'
    tags: tags
    virtualNetworkLinks: allVnetLinks
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// LOG ANALYTICS WORKSPACE (Hub diagnostics)
// ──────────────────────────────────────────────────────────────────────────────

module logAnalytics 'br/public:avm/res/operational-insights/workspace:0.12.0' = {
  scope: networkRg
  name: 'deploy-hub-law'
  params: {
    name: lawName
    location: location
    tags: tags
    skuName: 'PerGB2018'
    dataRetention: env == 'prd' ? 90 : 30
  }
}

// ============================================================================
// RG2: HUB RESOURCES (ACR, APIM, Compass PE)
// ============================================================================

resource hubRg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: hubRgName
  location: location
  tags: tags
}

// ──────────────────────────────────────────────────────────────────────────────
// CMK IDENTITY + KEY VAULT (for ACR encryption)
// ──────────────────────────────────────────────────────────────────────────────

module hubCmkIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.0' = {
  scope: hubRg
  name: 'deploy-hub-cmk-uami'
  params: {
    name: hubUamiName
    location: location
    tags: tags
  }
}

module hubKeyVault 'br/public:avm/res/key-vault/vault:0.13.3' = {
  scope: hubRg
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
        workspaceResourceId: logAnalytics.outputs.resourceId
      }
    ]
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// ACR PREMIUM (shared across all BU subscriptions)
//
// Premium required for: Private Endpoints, zone redundancy, geo-replication,
// content trust, repo-scoped tokens, retention policies.
// CMK: encrypted with RSA-2048 key from Hub Key Vault via UAMI.
//
// BU Container Apps pull images via: VNet peering → hub PE → ACR
// Access controlled by AcrPull role per BU managed identity.
// ──────────────────────────────────────────────────────────────────────────────

module acr 'br/public:avm/res/container-registry/registry:0.12.0' = {
  scope: hubRg
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
        subnetResourceId: hubVnet.outputs.subnetResourceIds[0] // snet-pe
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: dnsZones[0].outputs.resourceId // privatelink.azurecr.io
            }
          ]
        }
      }
    ]
    diagnosticSettings: [
      {
        workspaceResourceId: logAnalytics.outputs.resourceId
      }
    ]
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// CORE42 COMPASS PRIVATE ENDPOINT (manual connection — needs Compass approval)
//
// Core42 Compass uses a cross-tenant PE to their Application Gateway.
// This is a MANUAL connection — after deployment, Compass team reviews and
// approves the PE (up to 24 hours). Until approved, status = 'Pending'.
//
// To enable:
//   deployCompassPe = true
//   compassResourceId = '<Resource ID from Compass team>'
//   compassGroupId = 'fep1'
// ──────────────────────────────────────────────────────────────────────────────

module compassPe 'modules/compass-pe.bicep' = if (deployCompassPe && !empty(compassResourceId)) {
  scope: hubRg
  name: 'deploy-pe-compass'
  params: {
    name: 'pe-compass-cpx-${env}-${regionAbbr}-${instance}'
    location: location
    tags: tags
    subnetResourceId: hubVnet.outputs.subnetResourceIds[0] // snet-pe
    compassResourceId: compassResourceId
    compassGroupId: compassGroupId
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// APIM AI GATEWAY (toggle — Premium, VNet-injected in snet-apim)
//
// Internal mode: only reachable from peered VNets (spokes).
// 9 APIM Workspaces (one per BU): ws-csd, ws-crs, ws-com, etc.
// Rate limits, JWT validation, token counting per workspace.
//
// To enable:
//   deployApim = true
//   apimPublisherEmail / apimPublisherName configured
//
// Cost: ~$2,800/mo (Premium, 1 unit)
// ──────────────────────────────────────────────────────────────────────────────

module apim 'br/public:avm/res/api-management/service:0.12.0' = if (deployApim) {
  scope: hubRg
  name: 'deploy-apim'
  params: {
    name: apimName
    location: location
    tags: tags
    sku: 'Premium'
    skuCapacity: 1
    publisherEmail: apimPublisherEmail
    publisherName: apimPublisherName
    virtualNetworkType: 'Internal'
    subnetResourceId: hubVnet.outputs.subnetResourceIds[1] // snet-apim
    diagnosticSettings: [
      {
        workspaceResourceId: logAnalytics.outputs.resourceId
      }
    ]
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// OUTPUTS
// ──────────────────────────────────────────────────────────────────────────────

// Networking
@description('Hub Network RG name')
output networkRgName string = networkRg.name

@description('Hub VNet resource ID')
output hubVnetId string = hubVnet.outputs.resourceId

@description('Hub VNet name')
output hubVnetName string = hubVnet.outputs.name

@description('Hub PE subnet resource ID')
output peSubnetId string = hubVnet.outputs.subnetResourceIds[0]

@description('Hub APIM subnet resource ID')
output apimSubnetId string = hubVnet.outputs.subnetResourceIds[1]

@description('Hub LAW resource ID')
output lawId string = logAnalytics.outputs.resourceId

@description('ACR DNS zone resource ID')
output acrDnsZoneId string = dnsZones[0].outputs.resourceId

// Hub resources
@description('AI Hub RG name')
output hubRgName string = hubRg.name

@description('ACR name')
output acrName string = acr.outputs.name

@description('ACR resource ID')
output acrId string = acr.outputs.resourceId

@description('ACR login server')
output acrLoginServer string = acr.outputs.loginServer

@description('APIM name (empty if not deployed)')
#disable-next-line BCP318
output apimName string = deployApim ? apim.outputs.name : ''
