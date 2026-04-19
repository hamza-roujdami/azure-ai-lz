// ============================================================================
// CMK Encryption — Update AI Account with CMK
// The CMK Key Vault is in the network RG (cross-RG reference).
// KV URI and key name are passed as params — no name-based lookups.
// RBAC for AI Account MI is assigned in main template (Step 5b)
// ============================================================================

@description('AI Foundry Account name')
param aiAccountName string

@description('Key Vault URI (from network RG CMK KV)')
param keyVaultUri string

@description('CMK key name')
param keyName string

@description('Location')
param location string

// Update AI Account with CMK encryption
#disable-next-line BCP081
resource accountCmkUpdate 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' = {
  name: aiAccountName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  properties: {
    encryption: {
      keySource: 'Microsoft.KeyVault'
      keyVaultProperties: {
        keyVaultUri: keyVaultUri
        keyName: keyName
      }
    }
    publicNetworkAccess: 'Disabled'
    allowProjectManagement: true
    customSubDomainName: aiAccountName
    disableLocalAuth: true
    networkAcls: {
      defaultAction: 'Deny'
    }
  }
}
