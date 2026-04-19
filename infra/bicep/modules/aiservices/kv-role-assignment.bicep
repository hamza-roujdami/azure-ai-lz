// ============================================================================
// Key Vault RBAC Role Assignment for AI Account Managed Identity
// Grants Key Vault Crypto Service Encryption User to enable CMK
// Deployed at the KV's resource group scope (network RG)
// ============================================================================

@description('Key Vault name')
param keyVaultName string

@description('Principal ID of the AI Account system MI')
param principalId string

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource kvCryptoRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(kv.id, principalId, 'e147488a-f6f5-4113-8e2d-b22465e65bf6')
  scope: kv
  properties: {
    principalId: principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'e147488a-f6f5-4113-8e2d-b22465e65bf6') // Key Vault Crypto Service Encryption User
  }
}
