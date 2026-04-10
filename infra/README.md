# CPX AI Landing Zone — Infrastructure

Bicep IaC for deploying an AI Foundry Landing Zone per Business Unit.

## Architecture

Each BU subscription gets **2 resource groups** deployed in sequence:

| Phase | Template | Resource Group | Resources |
|---|---|---|---|
| 1 | `main-network.bicep` | `rg-{bu}-network-{env}-{region}-{instance}` | VNet, 3 subnets, 3 NSGs, 7 Private DNS zones, Log Analytics, App Insights |
| 2 | `main-aiservices-custom.bicep` (recommended) | `rg-{bu}-aiservices-{env}-{region}-{instance}` | UAMI, Key Vault (CMK key), Storage (CMK, ZRS), Cosmos DB (CMK, serverless), AI Search (CMK enforcement), AI Foundry Account (CMK) + Project + Connections + RBAC + Capability Hosts |

## Phase 2 — Two Variants

| Template | Uses | Deployment Scripts | Policy-safe |
|---|---|---|---|
| `main-aiservices-custom.bicep` **(recommended)** | Custom modules (`modules/custom-ai-foundry/`) | None | Yes — works with zone-resilient, MCSB v2, deny-deployment-scripts policies |
| `main-aiservices.bicep` | AVM pattern (`avm/ptn/ai-ml/ai-foundry:0.6.0`) | Yes (3 internal scripts) | No — blocked by policies that deny `Microsoft.Resources/deploymentScripts` or non-zone-redundant ACI/Storage |

Use `main-aiservices-custom.bicep` for CPX and any environment with restrictive Azure Policies.

## File Structure

```
infra/
├── main-network.bicep                   # Phase 1 orchestrator
├── main-aiservices-custom.bicep         # Phase 2 orchestrator (RECOMMENDED — no deployment scripts)
├── main-aiservices.bicep                # Phase 2 orchestrator (AVM pattern — unrestricted environments only)
└── modules/
    ├── custom-ai-foundry/               # Policy-safe custom modules (no ACI, no scripts)
    │   ├── README.md                    # Integration guide
    │   ├── account.bicep                # AI Foundry Account + PE + DNS
    │   ├── project.bicep                # Project + 3 Connections (Cosmos, Storage, Search)
    │   ├── rbac-assignments.bicep       # 6 RBAC role assignments (Project MI → stores)
    │   └── capability-hosts.bicep       # Agent Service capability hosts
    ├── ai-foundry/
    │   ├── cmk-encryption.bicep         # CMK update on AI Foundry Account
    │   └── kv-role-assignment.bicep     # KV Crypto role for AI Account MI
    └── cosmos-db-account.bicep          # Cosmos DB with CMK (raw resource)
```

**AVM resource modules** (downloaded automatically from Bicep public registry):
- `avm/res/key-vault/vault:0.13.3`
- `avm/res/storage/storage-account:0.26.2`
- `avm/res/search/search-service:0.11.1`
- `avm/res/managed-identity/user-assigned-identity:0.4.0`
- `avm/res/network/virtual-network:0.7.0`
- `avm/res/network/network-security-group:0.5.0`
- `avm/res/network/private-dns-zone:0.7.0`
- `avm/res/operational-insights/workspace:0.12.0`
- `avm/res/insights/component:0.6.0`

## Prerequisites

1. **Azure CLI** with Bicep:
   ```bash
   az --version          # >= 2.60
   az bicep version      # >= 0.30
   ```
2. **Logged in** to the target subscription:
   ```bash
   az login
   az account set --subscription "<BU-subscription-id>"
   ```
3. **Permissions**: Owner or Contributor + User Access Administrator on the subscription
4. **Deployer principal ID**: your Entra Object ID (for Key Vault admin):
   ```bash
   az ad signed-in-user show --query id -o tsv
   ```

## Deployment

### Phase 1 — Network

```bash
cd infra/

az deployment sub create \
  --location uaenorth \
  --template-file main-network.bicep \
  --name "phase1-network-$(date +%Y%m%d%H%M)" \
  --parameters \
    location='uaenorth' \
    bu='csd' \
    regionAbbr='uaen' \
    env='dev'
```

### Phase 2 — AI Services

Get outputs from Phase 1, then deploy Phase 2:

```bash
# Get Phase 1 outputs
PHASE1_NAME="<phase1-deployment-name>"
PE_SUBNET=$(az deployment sub show --name $PHASE1_NAME --query "properties.outputs.peSubnetId.value" -o tsv)
LAW_ID=$(az deployment sub show --name $PHASE1_NAME --query "properties.outputs.lawId.value" -o tsv)
DEPLOYER_ID=$(az ad signed-in-user show --query id -o tsv)

# Get DNS zone IDs (from the network RG)
RG_NET="rg-csd-network-dev-uaen-001"
DNS_ZONES=$(az network private-dns zone list -g $RG_NET --query "[].id" -o json)

az deployment sub create \
  --location uaenorth \
  --template-file main-aiservices-custom.bicep \
  --name "phase2-aiservices-$(date +%Y%m%d%H%M)" \
  --parameters \
    location='uaenorth' \
    bu='csd' \
    regionAbbr='uaen' \
    env='dev' \
    deployerPrincipalId="$DEPLOYER_ID" \
    peSubnetId="$PE_SUBNET" \
    lawId="$LAW_ID" \
    dnsZoneIds="$DNS_ZONES"
```

## Parameters

### Required (both phases)

| Parameter | Description | Example |
|---|---|---|
| `location` | Azure region | `uaenorth` |
| `bu` | Business Unit code | `csd`, `cte`, `cdo` |
| `regionAbbr` | Short region code for naming | `uaen`, `swc` |

### Required (Phase 2 only)

| Parameter | Description |
|---|---|
| `deployerPrincipalId` | Entra Object ID of the deployer (for KV admin role) |
| `peSubnetId` | PE subnet resource ID (from Phase 1 output) |
| `lawId` | Log Analytics Workspace ID (from Phase 1 output) |
| `dnsZoneIds` | Array of 7 Private DNS Zone IDs (from Phase 1, order matters — see below) |

### Optional

| Parameter | Default | Description |
|---|---|---|
| `env` | `dev` | Environment: `dev`, `tst`, `prd` |
| `instance` | `001` | Instance number (for multiple deployments) |
| `vnetAddressPrefix` | `192.168.0.0/22` | VNet CIDR (Phase 1 only) |

### DNS Zone Ordering

The `dnsZoneIds` array **must** follow this order (matching `main-network.bicep`):

| Index | DNS Zone |
|---|---|
| 0 | `privatelink.cognitiveservices.azure.com` |
| 1 | `privatelink.openai.azure.com` |
| 2 | `privatelink.services.ai.azure.com` |
| 3 | `privatelink.search.windows.net` |
| 4 | `privatelink.documents.azure.com` |
| 5 | `privatelink.blob.core.windows.net` |
| 6 | `privatelink.vaultcore.azure.net` |

## Deploying for Another BU

Change the `bu` parameter — all resource names are derived from it:

```bash
# Deploy for CTE Business Unit
az deployment sub create \
  --location uaenorth \
  --template-file main-network.bicep \
  --parameters location='uaenorth' bu='cte' regionAbbr='uaen'
```

This creates `rg-cte-network-dev-uaen-001`, `vnet-cte-dev-uaen-001`, etc.

## Policy Compliance

All resources are deployed with:

- **CMK**: Key Vault key on Storage, Cosmos DB, AI Foundry Account; `cmkEnforcement: Enabled` on Search
- **Private Endpoints only**: `publicNetworkAccess: 'Disabled'` on all services
- **No local auth**: Entra ID / Managed Identity everywhere
- **ZRS**: `Standard_ZRS` on Storage Account
- **Zone redundancy**: Cosmos DB (region-dependent)
- **Infrastructure encryption**: Double encryption on Storage
- **TLS 1.2**: Minimum on Storage and Cosmos
- **Soft-delete + purge protection**: Key Vault
- **Diagnostic logging**: All services → Log Analytics Workspace

## Known Limitations

- **AVM AI Foundry pattern blocked by policies**: The AVM `avm/ptn/ai-ml/ai-foundry` module uses `Microsoft.Resources/deploymentScripts` internally, which creates temporary ACI + Storage. These are blocked by zone-resilient, MCSB v2, and shared-key policies. Use `main-aiservices-custom.bicep` instead — it uses raw Bicep resources with no deployment scripts. See [Deployment Scripts docs](https://learn.microsoft.com/en-us/azure/azure-resource-manager/templates/deployment-script-template) for details.
- **Cosmos DB CMK**: Uses a raw Bicep resource (not AVM) because the published AVM Cosmos module (v0.18.0) does not support `customerManagedKey` yet
- **UAE North Cosmos zone redundancy**: May not have AZ capacity — set `isZoneRedundant: false` in `modules/cosmos-db-account.bicep` if needed
- **AI Account CMK**: The CMK update module (`cmk-encryption.bicep`) may hit transient Azure internal errors — safe to retry the deployment
