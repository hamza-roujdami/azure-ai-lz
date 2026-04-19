using '../main-aiservices.bicep'

// ============================================================================
// CSD Business Unit — AI Services (Sweden Central)
//
// Requires Phase 1 (network) deployed first.
//
// Deploy: az deployment sub create -l swedencentral -p params/csd-aiservices.bicepparam
// ============================================================================

param location = 'swedencentral'
param bu = 'csd'
param env = 'dev'
param regionAbbr = 'swc'
param instance = '001'

param deployerPrincipalId = readEnvironmentVariable('DEPLOYER_PRINCIPAL_ID', '')

// Phase 1 outputs
param peSubnetId = '/subscriptions/69770eff-2b73-40a9-abc7-0db9dff6c99d/resourceGroups/rg-csd-network-dev-swc-001/providers/Microsoft.Network/virtualNetworks/vnet-csd-dev-swc-001/subnets/snet-pe'
param lawId = '/subscriptions/69770eff-2b73-40a9-abc7-0db9dff6c99d/resourceGroups/rg-csd-network-dev-swc-001/providers/Microsoft.OperationalInsights/workspaces/law-csd-dev-swc-001'
param dnsZoneIds = [
  '/subscriptions/69770eff-2b73-40a9-abc7-0db9dff6c99d/resourceGroups/rg-csd-network-dev-swc-001/providers/Microsoft.Network/privateDnsZones/privatelink.cognitiveservices.azure.com'
  '/subscriptions/69770eff-2b73-40a9-abc7-0db9dff6c99d/resourceGroups/rg-csd-network-dev-swc-001/providers/Microsoft.Network/privateDnsZones/privatelink.openai.azure.com'
  '/subscriptions/69770eff-2b73-40a9-abc7-0db9dff6c99d/resourceGroups/rg-csd-network-dev-swc-001/providers/Microsoft.Network/privateDnsZones/privatelink.services.ai.azure.com'
  '/subscriptions/69770eff-2b73-40a9-abc7-0db9dff6c99d/resourceGroups/rg-csd-network-dev-swc-001/providers/Microsoft.Network/privateDnsZones/privatelink.search.windows.net'
  '/subscriptions/69770eff-2b73-40a9-abc7-0db9dff6c99d/resourceGroups/rg-csd-network-dev-swc-001/providers/Microsoft.Network/privateDnsZones/privatelink.documents.azure.com'
  '/subscriptions/69770eff-2b73-40a9-abc7-0db9dff6c99d/resourceGroups/rg-csd-network-dev-swc-001/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net'
  '/subscriptions/69770eff-2b73-40a9-abc7-0db9dff6c99d/resourceGroups/rg-csd-network-dev-swc-001/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net'
]

// Phase 1 CMK outputs — update with actual Phase 1 deployment outputs
param cmkKeyVaultId = '/subscriptions/69770eff-2b73-40a9-abc7-0db9dff6c99d/resourceGroups/rg-csd-network-dev-swc-001/providers/Microsoft.KeyVault/vaults/kv-csd-cmk-dev-swc-001'
param cmkKeyVaultUri = 'https://kv-csd-cmk-dev-swc-001.vault.azure.net/'
param cmkKeyName = 'cmk-csd-dev'
param cmkIdentityId = '/subscriptions/69770eff-2b73-40a9-abc7-0db9dff6c99d/resourceGroups/rg-csd-network-dev-swc-001/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-csd-cmk-dev-swc-001'
