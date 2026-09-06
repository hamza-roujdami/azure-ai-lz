metadata description = 'Durable token usage ledger: API Management streams usage events to Event Hub, and a Cosmos DB container stores them for chargeback.'

@description('Base name used to derive resource names.')
@minLength(3)
@maxLength(20)
param baseName string

@description('Location for the ledger resources.')
param location string

@description('Tags applied to all resources.')
param tags object = {}

@description('Resource ID of the subnet for private endpoints.')
param privateEndpointSubnetResourceId string

@description('Private DNS zone resource ID for Event Hub.')
param eventHubPrivateDnsZoneResourceId string

@description('Private DNS zone resource ID for Cosmos DB.')
param cosmosPrivateDnsZoneResourceId string

@description('Name of the Event Hub namespace. Passed in so the gateway can be configured without waiting on this module.')
param eventHubNamespaceName string

@description('Name of the event hub that receives usage events from the gateway.')
param eventHubName string = 'ai-usage'

@description('Days to retain raw usage events in the event hub.')
param eventHubRetentionDays int = 7

@description('Principal ID of the identity the gateway uses to publish usage events.')
param gatewayPrincipalId string

var abbrs = loadJsonContent('../abbreviations.json')

var cosmosDatabaseName = 'ai-usage'
var cosmosContainerName = 'token-events'

module eventHubNamespace 'br/public:avm/res/event-hub/namespace:0.15.0' = {
  name: 'evhns-${baseName}'
  params: {
    name: eventHubNamespaceName
    location: location
    tags: tags
    skuName: 'Standard'
    publicNetworkAccess: 'Disabled'
    disableLocalAuth: true
    eventhubs: [
      {
        name: eventHubName
        partitionCount: 2
        messageRetentionInDays: eventHubRetentionDays
      }
    ]
    privateEndpoints: [
      {
        subnetResourceId: privateEndpointSubnetResourceId
        service: 'namespace'
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: eventHubPrivateDnsZoneResourceId
            }
          ]
        }
      }
    ]
    roleAssignments: [
      {
        principalId: gatewayPrincipalId
        principalType: 'ServicePrincipal'
        roleDefinitionIdOrName: 'Azure Event Hubs Data Sender'
      }
    ]
  }
}

module ledgerCosmos 'br/public:avm/res/document-db/database-account:0.21.1' = {
  name: 'cosmos-${baseName}'
  params: {
    name: '${abbrs.cosmosDb}${baseName}'
    location: location
    tags: tags
    disableLocalAuthentication: true
    networkRestrictions: {
      publicNetworkAccess: 'Disabled'
// Private endpoints are the only access path, so no IP or VNet rules are needed.
      ipRules: []
      virtualNetworkRules: []
    }
    sqlDatabases: [
      {
        name: cosmosDatabaseName
        containers: [
          {
            name: cosmosContainerName
            paths: [
              '/subscriptionId'
            ]
            // Usage rows age out on their own; the ledger is not meant to grow forever.
            defaultTtl: 7776000
          }
        ]
      }
    ]
    privateEndpoints: [
      {
        subnetResourceId: privateEndpointSubnetResourceId
        service: 'Sql'
        privateDnsZoneGroup: {
          privateDnsZoneGroupConfigs: [
            {
              privateDnsZoneResourceId: cosmosPrivateDnsZoneResourceId
            }
          ]
        }
      }
    ]
  }
}

@description('Fully qualified namespace of the event hub that receives usage events.')
output eventHubNamespaceName string = eventHubNamespace.outputs.name

@description('Name of the event hub that receives usage events.')
output eventHubName string = eventHubName

@description('Name of the Cosmos DB account holding the usage ledger.')
output ledgerAccountName string = ledgerCosmos.outputs.name

@description('Database holding the usage ledger.')
output ledgerDatabaseName string = cosmosDatabaseName

@description('Container holding token usage events.')
output ledgerContainerName string = cosmosContainerName
