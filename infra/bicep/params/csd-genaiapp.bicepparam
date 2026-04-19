using '../main-genaiapp.bicep'

// ============================================================================
// CSD Business Unit — GenAI App (Sweden Central)
//
// Requires Phase 1 (network) and Phase 2 (aiservices) deployed first.
//
// Deploy: az deployment sub create -l swedencentral -p params/csd-genaiapp.bicepparam
// ============================================================================

param location = 'swedencentral'
param bu = 'csd'
param env = 'dev'
param regionAbbr = 'swc'
param instance = '001'

// Phase 1 outputs
param acaSubnetId = '/subscriptions/69770eff-2b73-40a9-abc7-0db9dff6c99d/resourceGroups/rg-csd-network-dev-swc-001/providers/Microsoft.Network/virtualNetworks/vnet-csd-dev-swc-001/subnets/snet-container-apps'
param lawId = '/subscriptions/69770eff-2b73-40a9-abc7-0db9dff6c99d/resourceGroups/rg-csd-network-dev-swc-001/providers/Microsoft.OperationalInsights/workspaces/law-csd-dev-swc-001'

// AcrPull is granted from Hub (main-aihub.bicep → buAcrPullPrincipals)
// After deploying this phase, pass acaIdentityPrincipalId output to the Hub deployment.

// CMK — from Phase 1 (network RG)
param cmkKeyVaultId = '/subscriptions/69770eff-2b73-40a9-abc7-0db9dff6c99d/resourceGroups/rg-csd-network-dev-swc-001/providers/Microsoft.KeyVault/vaults/kv-csd-cmk-dev-swc-001'
param cmkKeyName = 'cmk-csd-dev'
param cmkIdentityId = '/subscriptions/69770eff-2b73-40a9-abc7-0db9dff6c99d/resourceGroups/rg-csd-network-dev-swc-001/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-csd-cmk-dev-swc-001'
