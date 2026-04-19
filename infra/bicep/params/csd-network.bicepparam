using '../main-network.bicep'

// ============================================================================
// CSD Business Unit — Network (Sweden Central)
//
// Deploy: az deployment sub create -l swedencentral -p params/csd-network.bicepparam
// ============================================================================

param location = 'swedencentral'
param bu = 'csd'
param env = 'dev'
param regionAbbr = 'swc'
param instance = '001'

// ACR DNS zone is owned by Hub — BU does not create it
param deployAcrDnsZone = false

// Deployer principal ID for CMK KV admin access
param deployerPrincipalId = readEnvironmentVariable('DEPLOYER_PRINCIPAL_ID', '')
