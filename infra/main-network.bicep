// ============================================================================
// CPX AI Landing Zone — Phase 1: Network Resource Group
// rg-{bu}-network-{env}-{region}-{instance}
//
// Deploys: VNet + 3 Subnets (with NSGs), 7 Private DNS Zones, Monitoring
// Uses Azure Verified Modules (AVM) aligned with bicep-ptn-aiml-landing-zone
// ============================================================================

targetScope = 'subscription'

// ──────────────────────────────────────────────────────────────────────────────
// PARAMETERS
// ──────────────────────────────────────────────────────────────────────────────

@description('Azure region (e.g., uaenorth, swedencentral)')
param location string

@description('Business Unit identifier (e.g., csd, cte, cdo)')
param bu string

@description('Environment')
@allowed(['dev', 'tst', 'prd'])
param env string = 'dev'

@description('Region abbreviation for naming (e.g., uaen, swc)')
param regionAbbr string

@description('Instance number')
param instance string = '001'

@description('VNet address space')
param vnetAddressPrefix string = '192.168.0.0/22'

@description('PE subnet prefix')
param peSubnetPrefix string = '192.168.0.0/25'

@description('AI Foundry Agent subnet prefix (/24 recommended by Microsoft)')
param agentSubnetPrefix string = '192.168.1.0/24'

@description('Container Apps subnet prefix')
param acaSubnetPrefix string = '192.168.2.0/24'

// ──────────────────────────────────────────────────────────────────────────────
// VARIABLES
// ──────────────────────────────────────────────────────────────────────────────

var tags = {
  BusinessUnit: toUpper(bu)
  Environment: env
  Project: 'cpx-ai-landing-zone'
  ManagedBy: 'Bicep-AVM'
}

// Naming convention: {type}-{bu}-{function}-{env}-{region}-{instance}
var rgName = 'rg-${bu}-network-${env}-${regionAbbr}-${instance}'
var vnetName = 'vnet-${bu}-${env}-${regionAbbr}-${instance}'
var lawName = 'law-${bu}-${env}-${regionAbbr}-${instance}'
var appiName = 'appi-${bu}-${env}-${regionAbbr}-${instance}'

// NSG names
var nsgPeName = 'nsg-${bu}-pe-${env}-${regionAbbr}-${instance}'
var nsgAgentName = 'nsg-${bu}-agent-${env}-${regionAbbr}-${instance}'
var nsgAcaName = 'nsg-${bu}-aca-${env}-${regionAbbr}-${instance}'

// Private DNS zone names
var privateDnsZones = [
  'privatelink.cognitiveservices.azure.com'
  'privatelink.openai.azure.com'
  'privatelink.services.ai.azure.com'
  'privatelink.search.windows.net'
  'privatelink.documents.azure.com'
  'privatelink.blob.${environment().suffixes.storage}'
  'privatelink.vaultcore.azure.net'
]

// ──────────────────────────────────────────────────────────────────────────────
// RESOURCE GROUP
// ──────────────────────────────────────────────────────────────────────────────

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: rgName
  location: location
  tags: tags
}

// ──────────────────────────────────────────────────────────────────────────────
// NSGs (deploy before VNet so subnets can reference them)
// ──────────────────────────────────────────────────────────────────────────────

module nsgPe 'br/public:avm/res/network/network-security-group:0.5.0' = {
  scope: rg
  name: 'deploy-nsg-pe'
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

module nsgAgent 'br/public:avm/res/network/network-security-group:0.5.0' = {
  scope: rg
  name: 'deploy-nsg-agent'
  params: {
    name: nsgAgentName
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

module nsgAca 'br/public:avm/res/network/network-security-group:0.5.0' = {
  scope: rg
  name: 'deploy-nsg-aca'
  params: {
    name: nsgAcaName
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

// ──────────────────────────────────────────────────────────────────────────────
// VIRTUAL NETWORK + 3 SUBNETS (with NSG association)
// ──────────────────────────────────────────────────────────────────────────────

module vnet 'br/public:avm/res/network/virtual-network:0.7.0' = {
  scope: rg
  name: 'deploy-vnet'
  params: {
    name: vnetName
    location: location
    tags: tags
    addressPrefixes: [vnetAddressPrefix]
    subnets: [
      {
        name: 'snet-pe'
        addressPrefix: peSubnetPrefix
        networkSecurityGroupResourceId: nsgPe.outputs.resourceId
        privateEndpointNetworkPolicies: 'Enabled'
      }
      {
        name: 'snet-foundry-agents'
        addressPrefix: agentSubnetPrefix
        networkSecurityGroupResourceId: nsgAgent.outputs.resourceId
        delegation: 'Microsoft.App/environments'
      }
      {
        name: 'snet-container-apps'
        addressPrefix: acaSubnetPrefix
        networkSecurityGroupResourceId: nsgAca.outputs.resourceId
        delegation: 'Microsoft.App/environments'
      }
    ]
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// PRIVATE DNS ZONES (7 zones, linked to VNet)
// ──────────────────────────────────────────────────────────────────────────────

@batchSize(1)
module dnsZones 'br/public:avm/res/network/private-dns-zone:0.7.0' = [for zone in privateDnsZones: {
  scope: rg
  name: 'deploy-dns-${replace(zone, '.', '-')}'
  params: {
    name: zone
    location: 'global'
    tags: tags
    virtualNetworkLinks: [
      {
        virtualNetworkResourceId: vnet.outputs.resourceId
        registrationEnabled: false
      }
    ]
  }
}]

// ──────────────────────────────────────────────────────────────────────────────
// LOG ANALYTICS WORKSPACE
// ──────────────────────────────────────────────────────────────────────────────

module logAnalytics 'br/public:avm/res/operational-insights/workspace:0.12.0' = {
  scope: rg
  name: 'deploy-law'
  params: {
    name: lawName
    location: location
    tags: tags
    skuName: 'PerGB2018'
    dataRetention: env == 'prd' ? 90 : 30
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// APPLICATION INSIGHTS (linked to LAW)
// ──────────────────────────────────────────────────────────────────────────────

module appInsights 'br/public:avm/res/insights/component:0.6.0' = {
  scope: rg
  name: 'deploy-appi'
  params: {
    name: appiName
    location: location
    tags: tags
    workspaceResourceId: logAnalytics.outputs.resourceId
    kind: 'web'
    applicationType: 'web'
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// OUTPUTS (consumed by Phase 2 and Phase 3)
// ──────────────────────────────────────────────────────────────────────────────

@description('Network Resource Group name')
output rgName string = rg.name

@description('VNet Resource ID')
output vnetId string = vnet.outputs.resourceId

@description('VNet name')
output vnetName string = vnet.outputs.name

@description('PE subnet Resource ID')
output peSubnetId string = vnet.outputs.subnetResourceIds[0]

@description('Foundry Agent subnet Resource ID')
output agentSubnetId string = vnet.outputs.subnetResourceIds[1]

@description('Container Apps subnet Resource ID')
output acaSubnetId string = vnet.outputs.subnetResourceIds[2]

@description('Log Analytics Workspace Resource ID')
output lawId string = logAnalytics.outputs.resourceId

@description('Log Analytics Workspace name')
output lawName string = logAnalytics.outputs.name

@description('Application Insights Connection String')
output appInsightsConnectionString string = appInsights.outputs.connectionString

@description('Application Insights Instrumentation Key')
output appInsightsInstrumentationKey string = appInsights.outputs.instrumentationKey

@description('Private DNS Zone Resource IDs')
output dnsZoneIds array = [for (zone, i) in privateDnsZones: dnsZones[i].outputs.resourceId]
