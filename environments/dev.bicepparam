using '../infra/main.bicep'

param environmentName = 'dev'
param location = 'swedencentral'

// Deploy everything by default. Set either of these to false to deploy one pillar on its own.
param deploySpoke = true
param deployHub = true

// Container Apps runtime for self-hosted agents. Set false for Foundry hosted agents only.
param deployAppLayer = true

param apimPublisherEmail = 'admin@example.com'
param apimPublisherName = 'AI Platform'

// Claude uses the Anthropic Messages schema and is not available in every region.
param deployAnthropicApi = true

// Durable usage ledger behind the gateway: Event Hub plus a Cosmos DB container.
param deployUsageLedger = true

// Bastion and a jumpbox, the only way into a landing zone with no public endpoints.
// Bastion needs a public IP, so this stays off in subscriptions that block them.
// To enable, supply the password on the command line, never in this file:
//   az deployment sub create ... --parameters jumpboxAdminPassword=<value>
param deployJumpbox = false

// Caller identity enforcement. Turn on once you have an Entra app registration to validate against.
param enableJwtValidation = false

// Models the gateway fronts. Check quota in your region before adding more.
// Claude models are format 'Anthropic' and currently only offer the GlobalStandard SKU.
param modelDeployments = [
  {
    name: 'gpt-4o'
    model: {
      format: 'OpenAI'
      name: 'gpt-4o'
      version: '2024-11-20'
    }
    sku: {
      name: 'Standard'
      capacity: 1
    }
  }
  {
    name: 'text-embedding-3-large'
    model: {
      format: 'OpenAI'
      name: 'text-embedding-3-large'
      version: '1'
    }
    sku: {
      name: 'Standard'
      capacity: 1
    }
  }
  {
    name: 'claude-sonnet-4-5'
    model: {
      format: 'Anthropic'
      name: 'claude-sonnet-4-5'
      version: '20250929'
    }
    sku: {
      name: 'GlobalStandard'
      capacity: 1
    }
  }
]
