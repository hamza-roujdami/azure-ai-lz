// ============================================================================
// Key Vault Secrets User role assignment for APIM system MI
// Allows APIM to read secrets via Named Values (Key Vault reference)
// ============================================================================

@description('Key Vault name')
param keyVaultName string

@description('Principal ID to grant access (APIM system MI)')
param principalId string

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

// Key Vault Secrets User — 4633458b-17de-408a-b874-0445c86b69e6
resource kvSecretsRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(kv.id, principalId, '4633458b-17de-408a-b874-0445c86b69e6')
  scope: kv
  properties: {
    principalId: principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
  }
}
