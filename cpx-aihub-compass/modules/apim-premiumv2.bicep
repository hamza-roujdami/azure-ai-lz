// ============================================================================
// APIM Premium v2 — raw Bicep resource
// Deployed at resource group scope.
// ============================================================================

@description('APIM resource name')
param name string

@description('Azure region')
param location string

@description('Tags')
param tags object

@description('Publisher email')
param publisherEmail string

@description('Publisher name')
param publisherName string

@description('Log Analytics Workspace resource ID for diagnostics')
param lawId string

@description('Subnet resource ID for VNet injection (optional — if empty, no VNet injection)')
param subnetResourceId string = ''

resource apim 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: 'Premiumv2'
    capacity: 1
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    virtualNetworkType: !empty(subnetResourceId) ? 'Internal' : 'None'
    virtualNetworkConfiguration: !empty(subnetResourceId) ? {
      subnetResourceId: subnetResourceId
    } : null
  }
}

resource apimDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: '${name}-diagnostics'
  scope: apim
  properties: {
    workspaceId: lawId
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

@description('APIM resource name')
output apimName string = apim.name

@description('APIM gateway URL')
output gatewayUrl string = apim.properties.gatewayUrl

@description('APIM system-assigned MI principal ID')
output principalId string = apim.identity.principalId
