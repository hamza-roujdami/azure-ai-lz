using '../main-aihub.bicep'

// ============================================================================
// AI Hub — Sweden Central
//
// Self-contained: creates its own VNet, subnets, DNS zones, and LAW.
// In production, deploy to a separate Hub subscription.
//
// Deploy:
//   az deployment sub create -l swedencentral -p params/aihub.bicepparam
// ============================================================================

param location = 'swedencentral'
param env = 'dev'
param regionAbbr = 'swc'
param instance = '002'
param org = 'cpx'

// Hub network — own VNet + subnets
param hubVnetAddressPrefix = '10.100.0.0/22'
param hubPeSubnetPrefix = '10.100.0.0/26'
param hubApimSubnetPrefix = '10.100.1.0/24'

// APIM — disabled for now (enable when ready)
param deployApim = false

// Compass PE — disabled (enable when Core42 provides Resource ID)
param deployCompassPe = false
