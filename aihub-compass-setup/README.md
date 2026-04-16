# AI Hub + Core42 Compass Setup Guide

Self-contained Bicep deployment for the AI Hub subscription — APIM AI Gateway and Core42 Compass integration.

## What's in this folder

```
aihub-compass-setup/
├── main-aihub.bicep            # Main orchestrator (deploy this)
├── bicepconfig.json            # Linter rules
└── modules/
    ├── compass-pe.bicep        # Core42 Compass Private Endpoint (manual approval)
    ├── apim-premiumv2.bicep    # APIM Premium v2 (AI Gateway)
    ├── apim-compass-api.bicep  # Compass API on APIM (3 OpenAI-compatible operations)
    └── apim-kv-role.bicep      # APIM → KV Secrets User (for API key)
```

## What it deploys

| Resource | Purpose |
|----------|---------|
| Hub VNet (snet-pe + snet-apim) | Hub networking |
| Hub LAW | Diagnostics |
| Hub UAMI + Key Vault | CMK encryption for ACR |
| ACR Premium (CMK, PE, zone-redundant) | Shared container registry |       
| DNS zones (azurecr.io, vaultcore.azure.net) | Private DNS for PEs |
| [Toggle] APIM Premium v2 | AI Gateway for Compass |
| [Toggle] Compass PE | Private Endpoint to Core42 App Gateway |
| [Toggle] Compass API on APIM | OpenAI-compatible proxy (ListDeployments, GetDeployment, ChatCompletions) |

## Prerequisites

- Azure CLI ≥ 2.60 with Bicep ≥ 0.30
- Owner or Contributor + User Access Administrator on the Hub subscription
- From Core42 (for Compass):
  - Compass App Gateway Resource ID
  - Sub-resource ID (typically `fep1`)
  - API Key (after PE approval)
  - Available model names

## Step-by-step deployment

### Step 1 — Deploy AI Hub (without Compass)

```bash
az account set -s <HUB_SUBSCRIPTION_ID>

az deployment sub create -l uaenorth \
  -f main-aihub.bicep \
  -p org=cpx \
  -p location=uaenorth \
  -p regionAbbr=uaen \
  -p env=dev
```

This creates: Hub VNet, ACR, KV, LAW, DNS zones. No Compass yet.

### Step 2 — Platform team: network + DNS for Compass

| Task | Details |
|------|---------|
| Firewall rules | BU `snet-aca` + `snet-foundry-agents` → Hub APIM IP, TCP 443 |
| DNS zone link | Link Hub `privatelink.azure-api.net` zone to BU spoke VNets (for APIM resolution) |

### Step 3 — Deploy Compass PE (when Core42 ready)

```bash
az account set -s <HUB_SUBSCRIPTION_ID>

az deployment sub create -l uaenorth \
  -f main-aihub.bicep \
  -p org=cpx location=uaenorth regionAbbr=uaen env=dev \
  -p deployCompassPe=true \
  -p compassResourceId='<Resource ID from Core42>' \
  -p compassGroupId='fep1'
```

PE will be in **Pending** state. Tell Core42 to approve it.

### Step 4 — Deploy APIM + Compass API (after PE approved)

```bash
# Store Compass API key in Hub KV
az keyvault secret set \
  --vault-name kv-cpx-hub-dev-uaen-001 \
  --name compass-api-key \
  --value '<API key from Core42>'

# Deploy APIM + Compass API
az deployment sub create -l uaenorth \
  -f main-aihub.bicep \
  -p org=cpx location=uaenorth regionAbbr=uaen env=dev \
  -p deployCompassPe=true \
  -p compassResourceId='<Resource ID from Core42>' \
  -p deployApim=true \
  -p deployCompassApi=true \
  -p compassModels='["jais-70b","falcon-180b"]' \
  -p apimPublisherEmail='platform@cpx.ae' \
  -p apimPublisherName='CPX Platform Team'
```

### Step 5 — Verify Compass works

```bash
# Get APIM subscription key (from Azure Portal → APIM → Subscriptions)
APIM_KEY="<subscription-key>"
APIM_URL="https://apim-cpx-dev-uaen-001.azure-api.net/compass"

# Test model discovery
curl -H "api-key: $APIM_KEY" "$APIM_URL/deployments"

# Test chat completion
curl -X POST -H "api-key: $APIM_KEY" -H "Content-Type: application/json" \
  "$APIM_URL/deployments/jais-70b/chat/completions" \
  -d '{"messages":[{"role":"user","content":"Hello"}],"max_tokens":10}'
```

## References

- [Core42 Compass API FAQs](https://www.core42.ai/compass/documentation/compass-api-faqs)
- [Core42 Compass PE Guide](https://www.core42.ai/compass/documentation)
- [Foundry APIM Gateway Integration](https://learn.microsoft.com/en-us/azure/ai-foundry/agents/how-to/ai-gateway)
