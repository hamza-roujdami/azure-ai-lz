// ============================================================================
// CMK Encryption — Update AI Account with CMK
// RBAC for AI Account MI is assigned in main template (Step 5b)
// ============================================================================

@description('AI Foundry Account name')
param aiAccountName string

@description('Key Vault name')
param keyVaultName string

@description('CMK key name')
param keyName string

@description('Location')
param location string

// Reference existing Key Vault
resource kv 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

// Reference existing key to get version
resource key 'Microsoft.KeyVault/vaults/keys@2023-07-01' existing = {
  parent: kv
  name: keyName
}

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
        keyVaultUri: kv.properties.vaultUri
        keyName: keyName
        keyVersion: last(split(key.properties.keyUriWithVersion, '/'))
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
