// ============================================================================
// CPX AI Landing Zone — Phase 2: AI Services Resource Group
// rg-{bu}-aiservices-{env}-{region}-{instance}
//
// Deploys: Key Vault (CMK) → Cosmos DB → Storage → AI Search →
//          AI Foundry Account + Project → PEs → Connections → RBAC →
//          Capability Hosts
//
// Policy-compliant: CMK, no local auth, ZRS, PE-only, ABAC
// AVM modules where available, custom for Foundry-specific resources
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

@description('Deployer principal ID (for initial KV access)')
param deployerPrincipalId string

@description('PE subnet resource ID (from Phase 1)')
param peSubnetId string

@description('Log Analytics Workspace ID (from Phase 1)')
param lawId string

@description('Private DNS Zone IDs (from Phase 1) - ordered: cognitiveservices, openai, services.ai, search, documents, blob, vaultcore')
param dnsZoneIds array

// ──────────────────────────────────────────────────────────────────────────────
// VARIABLES
// ──────────────────────────────────────────────────────────────────────────────

var tags = {
  BusinessUnit: toUpper(bu)
  Environment: env
  Project: 'cpx-ai-landing-zone'
  ManagedBy: 'Bicep-AVM'
}

// DNS Zone index map — must match the order in main-network.bicep privateDnsZones array
var dns = {
  cognitiveServices: 0 // privatelink.cognitiveservices.azure.com
  openAi:            1 // privatelink.openai.azure.com
  aiServices:        2 // privatelink.services.ai.azure.com
  search:            3 // privatelink.search.windows.net
  cosmos:            4 // privatelink.documents.azure.com
  blob:              5 // privatelink.blob.core.windows.net
  keyVault:          6 // privatelink.vaultcore.azure.net
}

var rgName = 'rg-${bu}-aiservices-${env}-${regionAbbr}-${instance}'
var kvName = 'kv-${bu}-fnd-${env}-${regionAbbr}-${instance}'
var cmkKeyName = 'cmk-${bu}-${env}'
var storageName = 'st${bu}fnd${env}${regionAbbr}${instance}'
var cosmosName = 'cosmos-${bu}-fnd-${env}-${regionAbbr}-${instance}'
var searchName = 'srch-${bu}-${env}-${regionAbbr}-${instance}'
var aiAccountName = 'ais-${bu}-${env}-${regionAbbr}-${instance}'
var projectName = 'proj-${bu}-default-${env}-${regionAbbr}-${instance}'
var uamiName = 'id-${bu}-cmk-${env}-${regionAbbr}-${instance}'

// ──────────────────────────────────────────────────────────────────────────────
// RESOURCE GROUP
// ──────────────────────────────────────────────────────────────────────────────

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: rgName
  location: location
  tags: tags
}

// ──────────────────────────────────────────────────────────────────────────────
// STEP 0: USER-ASSIGNED MANAGED IDENTITY (for CMK — used by Storage + AI Account)
// ──────────────────────────────────────────────────────────────────────────────

module cmkIdentity 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.0' = {
  scope: rg
  name: 'deploy-cmk-uami'
  params: {
    name: uamiName
    location: location
    tags: tags
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// STEP 1: KEY VAULT (deploy first — needed for CMK)
// ──────────────────────────────────────────────────────────────────────────────

module keyVault 'br/public:avm/res/key-vault/vault:0.13.3' = {
  scope: rg
  name: 'deploy-kv-foundry'
  params: {
    name: kvName
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
    privateEndpoints: [
      {
        subnetResourceId: peSubnetId
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: dnsZoneIds[dns.keyVault]
            }
          ]
        }
      }
    ]
    diagnosticSettings: [
      {
        workspaceResourceId: lawId
      }
    ]
    // CMK key - on redeploy, existing key is reused
    keys: [
      {
        name: cmkKeyName
        kty: 'RSA'
        keySize: 2048
      }
    ]
    roleAssignments: [
      {
        principalId: deployerPrincipalId
        roleDefinitionIdOrName: 'Key Vault Administrator'
      }
      {
        principalId: cmkIdentity.outputs.principalId
        roleDefinitionIdOrName: 'Key Vault Crypto Service Encryption User'
      }
    ]
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// STEP 2: STORAGE ACCOUNT (ZRS, CMK, no shared key, infra encryption, PE)
// ──────────────────────────────────────────────────────────────────────────────

module storage 'br/public:avm/res/storage/storage-account:0.26.2' = {
  scope: rg
  name: 'deploy-storage-foundry'
  params: {
    name: storageName
    location: location
    tags: tags
    skuName: 'Standard_ZRS'
    kind: 'StorageV2'
    allowSharedKeyAccess: false
    allowBlobPublicAccess: false
    publicNetworkAccess: 'Disabled'
    minimumTlsVersion: 'TLS1_2'
    requireInfrastructureEncryption: true
    managedIdentities: {
      userAssignedResourceIds: [cmkIdentity.outputs.resourceId]
    }
    customerManagedKey: {
      keyVaultResourceId: keyVault.outputs.resourceId
      keyName: cmkKeyName
      userAssignedIdentityResourceId: cmkIdentity.outputs.resourceId
    }
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
    privateEndpoints: [
      {
        subnetResourceId: peSubnetId
        service: 'blob'
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: dnsZoneIds[dns.blob]
            }
          ]
        }
      }
    ]
    diagnosticSettings: [
      {
        workspaceResourceId: lawId
      }
    ]
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// STEP 3: COSMOS DB (CMK, no local auth, serverless, PE) — Raw resource for CMK
// ──────────────────────────────────────────────────────────────────────────────

module cosmosDb 'modules/aiservices/cosmos-db-account.bicep' = {
  scope: rg
  name: 'deploy-cosmos-foundry'
  params: {
    name: cosmosName
    location: location
    tags: tags
    keyVaultKeyUri: '${keyVault.outputs.uri}keys/${cmkKeyName}'
    uamiResourceId: cmkIdentity.outputs.resourceId
    peSubnetId: peSubnetId
    cosmosDnsZoneId: dnsZoneIds[dns.cosmos]
    lawId: lawId
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// STEP 4: AI SEARCH (CMK enforcement, PE)
// ──────────────────────────────────────────────────────────────────────────────

module search 'br/public:avm/res/search/search-service:0.11.1' = {
  scope: rg
  name: 'deploy-search-foundry'
  params: {
    name: searchName
    location: location
    tags: tags
    sku: 'basic'
    replicaCount: 1
    partitionCount: 1
    publicNetworkAccess: 'Disabled'
    cmkEnforcement: 'Enabled'
    managedIdentities: {
      systemAssigned: true
    }
    disableLocalAuth: false // Agent Service may need API keys internally
    authOptions: {
      aadOrApiKey: {
        aadAuthFailureMode: 'http401WithBearerChallenge'
      }
    }
    privateEndpoints: [
      {
        subnetResourceId: peSubnetId
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: dnsZoneIds[dns.search]
            }
          ]
        }
      }
    ]
    diagnosticSettings: [
      {
        workspaceResourceId: lawId
      }
    ]
  }
}


// ──────────────────────────────────────────────────────────────────────────────
// STEP 5: AI FOUNDRY ACCOUNT (custom modules — NO deployment scripts, policy-safe)
// ──────────────────────────────────────────────────────────────────────────────

module aiAccount 'modules/aiservices/ai-foundry-account.bicep' = {
  scope: rg
  name: 'deploy-ai-account'
  params: {
    name: aiAccountName
    location: location
    tags: tags
    peSubnetId: peSubnetId
    dnsZoneIds: [dnsZoneIds[dns.cognitiveServices], dnsZoneIds[dns.openAi], dnsZoneIds[dns.aiServices]]
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// STEP 6: Grant AI Account MI KV Crypto role (must propagate before CMK step)
// ──────────────────────────────────────────────────────────────────────────────

module aiAccountKvRole 'modules/aiservices/kv-role-assignment.bicep' = {
  scope: rg
  name: 'deploy-ai-account-kv-role'
  params: {
    keyVaultName: kvName
    aiAccountName: aiAccountName
  }
  dependsOn: [keyVault, aiAccount]
}

// ──────────────────────────────────────────────────────────────────────────────
// STEP 7: CMK — Update AI Account with CMK encryption
// ──────────────────────────────────────────────────────────────────────────────

module cmkSetup 'modules/aiservices/cmk-encryption.bicep' = {
  scope: rg
  name: 'deploy-cmk-setup'
  params: {
    aiAccountName: aiAccountName
    keyVaultName: kvName
    keyName: cmkKeyName
    location: location
  }
  dependsOn: [keyVault, aiAccountKvRole]
}

// ──────────────────────────────────────────────────────────────────────────────
// STEP 8: AI FOUNDRY PROJECT + CONNECTIONS
// ──────────────────────────────────────────────────────────────────────────────

module aiProject 'modules/aiservices/ai-foundry-project.bicep' = {
  scope: rg
  name: 'deploy-ai-project'
  params: {
    projectName: projectName
    accountName: aiAccount.outputs.name
    cosmosName: cosmosDb.outputs.name
    storageName: storage.outputs.name
    searchName: search.outputs.name
    location: location
    tags: tags
  }
  dependsOn: [cmkSetup]
}

// ──────────────────────────────────────────────────────────────────────────────
// STEP 9: RBAC — Project identity → backing stores
// ──────────────────────────────────────────────────────────────────────────────

module rbacAssignments 'modules/aiservices/ai-foundry-rbac.bicep' = {
  scope: rg
  name: 'deploy-rbac'
  params: {
    projectPrincipalId: aiProject.outputs.projectPrincipalId
    storageAccountName: storage.outputs.name
    cosmosAccountName: cosmosDb.outputs.name
    searchServiceName: search.outputs.name
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// STEP 10: CAPABILITY HOSTS (account + project — NO deployment scripts)
// ──────────────────────────────────────────────────────────────────────────────

module capabilityHosts 'modules/aiservices/ai-foundry-capability-hosts.bicep' = {
  scope: rg
  name: 'deploy-capability-hosts'
  params: {
    accountName: aiAccount.outputs.name
    projectName: projectName
    cosmosConnectionName: aiProject.outputs.cosmosConnectionName
    storageConnectionName: aiProject.outputs.storageConnectionName
    searchConnectionName: aiProject.outputs.searchConnectionName
  }
  dependsOn: [rbacAssignments]
}

// ──────────────────────────────────────────────────────────────────────────────
// OUTPUTS
// ──────────────────────────────────────────────────────────────────────────────

output rgName string = rg.name
output aiAccountName string = aiAccount.outputs.name
output aiAccountId string = aiAccount.outputs.id
output projectName string = projectName
output kvName string = kvName
output cosmosName string = cosmosDb.outputs.name
output storageName string = storage.outputs.name
output searchName string = search.outputs.name
