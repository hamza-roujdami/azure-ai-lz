// ============================================================================
// Core42 Compass Private Endpoint — Manual connection to Compass App Gateway
//
// This creates a PE using "Connect to Azure resource by resource ID" (manual).
// After deployment, Compass team must review and approve the connection.
// Until approved, PE status = 'Pending'.
//
// From Compass guide:
//   Resource ID: /subscriptions/194bbe9f-.../applicationGateways/SaaS-cmpss-prod-agw01-agw-uan
//   Sub-resource: fep1
// ============================================================================

@description('Private Endpoint name')
param name string

@description('Azure region')
param location string

@description('Tags')
param tags object

@description('Subnet resource ID where PE NIC will be provisioned')
param subnetResourceId string

@description('Core42 Compass App Gateway resource ID')
param compassResourceId string

@description('Core42 Compass sub-resource / group ID')
param compassGroupId string

resource compassPe 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    subnet: {
      id: subnetResourceId
    }
    manualPrivateLinkServiceConnections: [
      {
        name: '${name}-connection'
        properties: {
          privateLinkServiceId: compassResourceId
          groupIds: [
            compassGroupId
          ]
          requestMessage: 'AI Landing Zone - Private Endpoint request for Compass API access'
        }
      }
    ]
  }
}

@description('Private Endpoint name')
output peName string = compassPe.name

@description('Private Endpoint resource ID')
output peId string = compassPe.id

@description('Connection status (Pending until Compass team approves)')
output connectionStatus string = compassPe.properties.manualPrivateLinkServiceConnections[0].properties.privateLinkServiceConnectionState.status
