// ============================================================================
// CPX AI Landing Zone — Phase 3: GenAI App Resource Group
// rg-{bu}-genaiapp-{env}-{region}-{instance}
//
// Deploys: Container Apps Environment → App Key Vault → App Storage
//
// This is the vendor-managed workload layer where AI agent apps run.
// Vendors get Contributor access to this RG (not to network or aiservices).
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

@description('Container Apps subnet resource ID (from Phase 1 — snet-container-apps)')
param acaSubnetId string

@description('Log Analytics Workspace ID (from Phase 1)')
param lawId string

@description('ACR resource ID from AI Hub (Phase 4) — if provided, grants AcrPull to the BU UAMI')
param acrId string = ''

// ──────────────────────────────────────────────────────────────────────────────
// VARIABLES
// ──────────────────────────────────────────────────────────────────────────────

var tags = {
  BusinessUnit: toUpper(bu)
  Environment: env
  Project: 'cpx-ai-landing-zone'
  ManagedBy: 'Bicep-AVM'
}

var rgName = 'rg-${bu}-genaiapp-${env}-${regionAbbr}-${instance}'
var acaEnvName = 'cae-${bu}-${env}-${regionAbbr}-${instance}'
var appKvName = 'kv-${bu}-app-${env}-${regionAbbr}-${instance}'
var appStorageName = 'st${bu}app${env}${regionAbbr}${instance}'
var acaIdentityName = 'id-${bu}-aca-${env}-${regionAbbr}-${instance}'

// ──────────────────────────────────────────────────────────────────────────────
// RESOURCE GROUP
// ──────────────────────────────────────────────────────────────────────────────

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: rgName
  location: location
  tags: tags
}

// ──────────────────────────────────────────────────────────────────────────────
// STEP 1: USER-ASSIGNED MANAGED IDENTITY (shared by all Container Apps in this BU)
//
// Used for: ACR pull (AcrPull role granted on hub ACR), KV access, Storage access.
// One identity per BU — all apps in this BU share it.
// Survives app deletion/recreation, can be pre-granted roles before apps exist.
// ──────────────────────────────────────────────────────────────────────────────

module acaIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.0' = {
  scope: rg
  name: 'deploy-id-aca'
  params: {
    name: acaIdentityName
    location: location
    tags: tags
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// STEP 1b: AcrPull role on shared ACR (self-contained — no hub redeploy needed)
//
// Scoped to the ACR resource. Works cross-RG and cross-subscription as long as
// the deployer has Owner or User Access Administrator on the ACR.
// Skipped if acrId is empty (hub not deployed yet).
// ──────────────────────────────────────────────────────────────────────────────

module acrPullRole 'modules/acr-pull-role.bicep' = if (!empty(acrId)) {
  scope: resourceGroup(split(acrId, '/')[2], split(acrId, '/')[4])
  name: 'deploy-acrpull-${bu}'
  params: {
    acrName: last(split(acrId, '/'))!
    principalId: acaIdentity.outputs.principalId
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// STEP 2: CONTAINER APPS ENVIRONMENT (internal, VNet-integrated)
// ──────────────────────────────────────────────────────────────────────────────

module acaEnv 'br/public:avm/res/app/managed-environment:0.8.0' = {
  scope: rg
  name: 'deploy-aca-env'
  params: {
    name: acaEnvName
    location: location
    tags: tags
    logAnalyticsWorkspaceResourceId: lawId
    internal: true
    infrastructureSubnetId: acaSubnetId
    zoneRedundant: true
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// STEP 3: APP KEY VAULT (vendor-managed secrets — separate from Foundry KV)
// ──────────────────────────────────────────────────────────────────────────────

module appKeyVault 'br/public:avm/res/key-vault/vault:0.13.3' = {
  scope: rg
  name: 'deploy-kv-app'
  params: {
    name: appKvName
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
    diagnosticSettings: [
      {
        workspaceResourceId: lawId
      }
    ]
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// STEP 4: APP STORAGE ACCOUNT (vendor app data — uploads, RAG sources)
// ──────────────────────────────────────────────────────────────────────────────

module appStorage 'br/public:avm/res/storage/storage-account:0.26.2' = {
  scope: rg
  name: 'deploy-storage-app'
  params: {
    name: appStorageName
    location: location
    tags: tags
    skuName: 'Standard_ZRS'
    kind: 'StorageV2'
    allowSharedKeyAccess: false
    allowBlobPublicAccess: false
    publicNetworkAccess: 'Disabled'
    minimumTlsVersion: 'TLS1_2'
    requireInfrastructureEncryption: true
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
    diagnosticSettings: [
      {
        workspaceResourceId: lawId
      }
    ]
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// OUTPUTS
// ──────────────────────────────────────────────────────────────────────────────

output rgName string = rg.name
output acaEnvName string = acaEnv.outputs.name
output acaEnvId string = acaEnv.outputs.resourceId
output appKvName string = appKeyVault.outputs.name
output appStorageName string = appStorage.outputs.name

@description('BU Container Apps UAMI name')
output acaIdentityName string = acaIdentity.outputs.name

@description('BU Container Apps UAMI resource ID — used by Container Apps to reference the identity')
output acaIdentityId string = acaIdentity.outputs.resourceId

@description('BU Container Apps UAMI principal ID')
output acaIdentityPrincipalId string = acaIdentity.outputs.principalId

@description('BU Container Apps UAMI client ID — used in Container App registry config')
output acaIdentityClientId string = acaIdentity.outputs.clientId
