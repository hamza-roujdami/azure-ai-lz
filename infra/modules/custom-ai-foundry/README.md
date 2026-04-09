# CPX Custom Foundry Modules — Policy-Safe (No Deployment Scripts)

These modules replace the `avm/ptn/ai-ml/ai-foundry` pattern module for environments
where Azure Policy blocks deployment scripts (zone-resilient, MCSB v2).

## Why?

The AVM AI Foundry pattern module (`avm/ptn/ai-ml/ai-foundry:0.4.0` and `0.6.0`)
internally uses `Microsoft.Resources/deploymentScripts` which spin up temporary
Azure Container Instances (ACI) + Storage Accounts. CPX policies block these because:

- ACI is not zone-redundant
- Temporary storage doesn't meet MCSB v2 controls

These custom modules use **raw Bicep resources only** — zero deployment scripts,
zero ACI, zero temporary storage.

## Files

```
modules/ai-foundry/
├── account.bicep          # AI Foundry Account + PE + DNS
├── project.bicep          # Project + 3 Connections (Cosmos, Storage, Search)
├── rbac-assignments.bicep # 6 role assignments (Project MI → backing stores)
└── capability-hosts.bicep # Account + Project capability hosts (Agent Service)
```

## How to integrate with CPX's existing code

In their `main.bicep`, replace the AVM AI Foundry pattern call:

```bicep
// REMOVE THIS:
// module aiFoundry 'br/public:avm/ptn/ai-ml/ai-foundry:0.4.0' = { ... }

// REPLACE WITH:
module aiAccount 'modules/ai-foundry/account.bicep' = {
  scope: foundryRg
  name: 'deploy-ai-account'
  params: {
    name: aiAccountName
    location: location
    tags: tags
    peSubnetId: peSubnetId
    dnsZoneIds: [cognitiveServicesDnsZoneId, openAiDnsZoneId, aiServicesDnsZoneId]
  }
}

module aiProject 'modules/ai-foundry/project.bicep' = {
  scope: foundryRg
  name: 'deploy-ai-project'
  params: {
    projectName: projectName
    accountName: aiAccount.outputs.name
    cosmosName: cosmosAccountName
    storageName: storageAccountName
    searchName: searchServiceName
    location: location
    tags: tags
  }
}

module rbac 'modules/ai-foundry/rbac-assignments.bicep' = {
  scope: foundryRg
  name: 'deploy-rbac'
  params: {
    projectPrincipalId: aiProject.outputs.projectPrincipalId
    storageAccountName: storageAccountName
    cosmosAccountName: cosmosAccountName
    searchServiceName: searchServiceName
  }
}

module capHosts 'modules/ai-foundry/capability-hosts.bicep' = {
  scope: foundryRg
  name: 'deploy-capability-hosts'
  params: {
    accountName: aiAccount.outputs.name
    projectName: projectName
    cosmosConnectionName: aiProject.outputs.cosmosConnectionName
    storageConnectionName: aiProject.outputs.storageConnectionName
    searchConnectionName: aiProject.outputs.searchConnectionName
  }
  dependsOn: [rbac]
}
```

## What these modules create (same as AVM pattern, without the scripts)

- AI Foundry Account (AIServices, S0, SystemAssigned MI, PE, disableLocalAuth)
- AI Foundry Project (SystemAssigned MI)
- 3 AAD Connections (Cosmos, Storage, Search)
- 6 RBAC role assignments (Project MI → backing stores)
- 2 Capability Hosts (Account + Project level for Agent Service)

## CMK

CMK for the AI Account is handled separately via `foundry-cmk` component
(already in the CPX repo at `components/foundry-cmk/main.bicep`).
Call it after the account is created.
