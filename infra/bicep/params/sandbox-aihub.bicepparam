using '../main-aihub.bicep'

// ============================================================================
// Sandbox: AI Hub — Sweden Central
// Requires Phase 1 (network) to be deployed first.
// ============================================================================

param location = 'swedencentral'
param env = 'dev'
param regionAbbr = 'swc'
param instance = '001'
param org = 'cpx'

// Phase 1 outputs
param peSubnetId = '/subscriptions/69770eff-2b73-40a9-abc7-0db9dff6c99d/resourceGroups/rg-csd-network-dev-swc-001/providers/Microsoft.Network/virtualNetworks/vnet-csd-dev-swc-001/subnets/snet-pe'
param lawId = '/subscriptions/69770eff-2b73-40a9-abc7-0db9dff6c99d/resourceGroups/rg-csd-network-dev-swc-001/providers/Microsoft.OperationalInsights/workspaces/law-csd-dev-swc-001'
param acrDnsZoneId = '/subscriptions/69770eff-2b73-40a9-abc7-0db9dff6c99d/resourceGroups/rg-csd-network-dev-swc-001/providers/Microsoft.Network/privateDnsZones/privatelink.azurecr.io'

// APIM — disabled in sandbox (Premium v2 not available in swedencentral)
param deployApim = false

// Compass PE — disabled (Core42 resource in UAE North only)
param deployCompassPe = false
