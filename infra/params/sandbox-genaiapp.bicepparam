using 'main-genaiapp.bicep'

// ============================================================================
// Sandbox: CSD Business Unit — Sweden Central
// Requires Phase 1 (network) and Phase 4 (hub) to be deployed first.
// ============================================================================

param location = 'swedencentral'
param bu = 'csd'
param env = 'dev'
param regionAbbr = 'swc'
param instance = '001'

// Phase 1 outputs
param acaSubnetId = '/subscriptions/69770eff-2b73-40a9-abc7-0db9dff6c99d/resourceGroups/rg-csd-network-dev-swc-001/providers/Microsoft.Network/virtualNetworks/vnet-csd-dev-swc-001/subnets/snet-container-apps'
param lawId = '/subscriptions/69770eff-2b73-40a9-abc7-0db9dff6c99d/resourceGroups/rg-csd-network-dev-swc-001/providers/Microsoft.OperationalInsights/workspaces/law-csd-dev-swc-001'

// Phase 4 (hub) output — ACR resource ID for AcrPull role
param acrId = '/subscriptions/69770eff-2b73-40a9-abc7-0db9dff6c99d/resourceGroups/rg-cpx-aihub-dev-swc-001/providers/Microsoft.ContainerRegistry/registries/acrcpxdevswc001'

// CMK — reuse BU Foundry KV key (from Phase 2)
param cmkKeyVaultId = '/subscriptions/69770eff-2b73-40a9-abc7-0db9dff6c99d/resourceGroups/rg-csd-aiservices-dev-swc-001/providers/Microsoft.KeyVault/vaults/kv-csd-fnd-dev-swc-001'
param cmkKeyName = 'cmk-csd-dev'
param cmkIdentityId = '/subscriptions/69770eff-2b73-40a9-abc7-0db9dff6c99d/resourceGroups/rg-csd-aiservices-dev-swc-001/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-csd-cmk-dev-swc-001'
