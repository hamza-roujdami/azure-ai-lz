// ============================================================================
// Key Vault RBAC Role Assignment for AI Account Managed Identity
// Grants Key Vault Crypto Service Encryption User to enable CMK
// ============================================================================

@description('Key Vault name')
param keyVaultName string

@description('AI Account name (to look up system-assigned managed identity)')
param aiAccountName string

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

#disable-next-line BCP081
resource aiAccount 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: aiAccountName
}

resource kvCryptoRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(kv.id, aiAccount.id, 'e147488a-f6f5-4113-8e2d-b22465e65bf6')
  scope: kv
  properties: {
    principalId: aiAccount.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'e147488a-f6f5-4113-8e2d-b22465e65bf6') // Key Vault Crypto Service Encryption User
  }
}
