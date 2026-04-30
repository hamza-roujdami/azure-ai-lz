# AI Hub — Compass API Setup on Existing APIM

Configures an **existing** APIM instance as an OpenAI-compatible proxy to Core42 Compass, then connects it to AI Foundry for agent use.

## Prerequisites (already done)

- [x] APIM provisioned (portal) with **system-assigned managed identity enabled**
- [x] Compass PE approved
- [x] Hub Key Vault with Compass API key secret stored
- [x] APIM DNS zone (`azure-api.net`) with A record → APIM private IP
- [x] Compass model names confirmed

## What's in this folder

```
aihub-compass-setup/
├── 01-apim-setup/
│   ├── main.bicep              # Compass API on APIM (RBAC, Named Value, API, operations, policies, Product)
│   └── policies/
│       ├── forward-with-key.xml    # Injects Compass API key, forwards to backend (Chat, Embeddings, Score)
│       └── get-deployment.xml      # Returns model detail dynamically (C# expression)
├── 02-foundry-connection/
│   └── foundry-connection.bicep    # Foundry → APIM connection (deploy per BU project)
├── 03-agent-test/
│   ├── .env.example            # Environment config (copy to .env)
│   ├── test_connection.py      # Verify APIM connection in Foundry
│   ├── create_agent.py         # Create agent using Compass model
│   ├── chat_with_agent.py      # Interactive chat with agent
│   └── pyproject.toml          # Python dependencies
└── README.md                   # This file
```

## Step 1 — Configure Compass API on APIM

Deploys on your existing APIM: RBAC, Named Value (KV reference), API + 5 operations + 5 policies, Product + Subscription.

```bash
# Get APIM system MI principal ID first
APIM_MI=$(az apim show -n <APIM_NAME> -g <HUB_RG> \
  --query identity.principalId -o tsv)

az deployment group create \
  -g <HUB_RG> \
  -f 01-apim-setup/main.bicep \
  -p apimName='<APIM_NAME>' \
  -p keyVaultName='<HUB_KV_NAME>' \
  -p apimPrincipalId="$APIM_MI"
```

> Models default to the 6 Core42 Compass models (gpt-5.1, gpt-4.1-mini, o4-mini, text-embedding-3-large, qwen3-reranker, k2-think-core42). Override with `-p compassModels='["model1","model2"]'` if needed.

### Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `apimName` | Yes | — | Existing APIM resource name |
| `keyVaultName` | Yes | — | Existing Hub KV name (must have Compass API key secret) |
| `apimPrincipalId` | Yes | — | APIM system MI principal ID (`az apim show ... --query identity.principalId`) |
| `backendUrl` | No | `https://api.core42.ai/openai` | Compass backend URL |
| `compassApiKeySecretName` | No | `compass-api-key` | Secret name in Key Vault |
| `apiName` | No | `compass-api` | API identifier in APIM (unique per API) |
| `apiPath` | No | `compass` | API URL path prefix |
| `apiDisplayName` | No | `Compass API` | API display name |
| `compassModels` | No | 6 Core42 models | Model deployment names |
| `productName` | No | `cpx-compass` | APIM Product name |
| `productDisplayName` | No | `CPX Compass` | Product display name |

### What it creates

| Resource | Purpose |
|----------|---------|
| RBAC: APIM MI → KV Secrets User | APIM reads API key from Key Vault |
| Named Value: `compass-api-key` | Key Vault reference (not hardcoded) |
| API: `compass-api` (path `/compass`) | OpenAI-compatible proxy |
| Op: `GET /deployments` | Returns static model list (for Foundry discovery) |
| Op: `GET /deployments/{name}` | Returns model detail (dynamic) |
| Op: `POST /deployments/{id}/chat/completions` | Forwards chat requests to Compass (gpt-5.1, gpt-4.1-mini, o4-mini, k2-think-core42) |
| Op: `POST /deployments/{id}/embeddings` | Forwards embedding requests to Compass (text-embedding-3-large) |
| Op: `POST /deployments/{id}/score` | Forwards reranker requests to Compass (qwen3-reranker) |
| Product + Subscription | Generates APIM subscription key for consumers |

### Get the APIM subscription key

```bash
# Via REST API
az rest --method POST \
  --url "/subscriptions/<SUB_ID>/resourceGroups/<HUB_RG>/providers/Microsoft.ApiManagement/service/<APIM_NAME>/subscriptions/<PRODUCT_NAME>-sub/listSecrets?api-version=2022-08-01" \
  --query primaryKey -o tsv
```

Or from portal: **APIM → Subscriptions → Compass Subscription → Show primary key**.

### Test (from jumpbox)

```bash
APIM_URL="https://<APIM_NAME>.azure-api.net"
APIM_KEY="<subscription-key-from-above>"

# List models
curl -s -H "api-key: $APIM_KEY" "$APIM_URL/compass/deployments" | jq .

# Chat completion
curl -s -X POST \
  -H "api-key: $APIM_KEY" \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Hello"}],"max_tokens":10}' \
  "$APIM_URL/compass/deployments/gpt-5.1/chat/completions" | jq .

# Embeddings
curl -s -X POST \
  -H "api-key: $APIM_KEY" \
  -H "Content-Type: application/json" \
  -d '{"input":"Hello world","model":"text-embedding-3-large"}' \
  "$APIM_URL/compass/deployments/text-embedding-3-large/embeddings" | jq .

# Reranker
curl -s -X POST \
  -H "api-key: $APIM_KEY" \
  -H "Content-Type: application/json" \
  -d '{"query":"What is AI?","documents":["AI is artificial intelligence","The sky is blue"]}' \
  "$APIM_URL/compass/deployments/qwen3-reranker/score" | jq .
```

## Step 2 — Connect Foundry to APIM

Creates an `ApiManagement` connection in a Foundry project so agents can call Compass through APIM.

```bash
az deployment group create \
  -g <BU_AISERVICES_RG> \
  -f 02-foundry-connection/foundry-connection.bicep \
  -p accountName='<FOUNDRY_ACCOUNT>' \
  -p projectName='<FOUNDRY_PROJECT>' \
  -p targetUrl='https://<APIM_NAME>.azure-api.net/compass' \
  -p apiKey='<APIM_SUBSCRIPTION_KEY>'
```

### Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `accountName` | Yes | — | Existing Foundry account name |
| `projectName` | Yes | — | Existing Foundry project name |
| `targetUrl` | Yes | — | APIM Compass endpoint URL |
| `apiKey` | Yes | — | APIM subscription key (from Step 1) |
| `connectionName` | No | `compass-apim` | Connection name in Foundry |
| `staticModels` | No | `[]` | Static model list (empty = dynamic discovery via ListDeployments) |

## Step 3 — Test with an Agent

```bash
cd 03-agent-test

# Install dependencies
pip install uv
uv sync

# Copy and edit .env
cp .env.example .env
# Update AZURE_AI_PROJECT_ENDPOINT with your Foundry project endpoint

# 1. Verify connection exists
uv run test_connection.py

# 2. Create agent
uv run create_agent.py

# 3. Chat with agent
uv run chat_with_agent.py
```

## Architecture

```
Foundry Agent (BU spoke)
  → APIM connection (category: ApiManagement)
    → APIM Gateway (hub, internal VNet)
      → ChatCompletions policy injects {{compass-api-key}} from KV
        → Compass PE (10.0.20.7:443)
          → Core42 Compass LLM
```

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `404 Resource not found` on APIM | API/operations not created | Run Step 1 deployment |
| `401 Unauthorized` | Wrong APIM subscription key | Check Product subscription key |
| `500` with Named Value error | APIM can't read KV secret | Verify APIM MI has KV Secrets User role |
| `500` with backend error | APIM can't reach Compass PE | Check NSG on snet-apim allows outbound to snet-pe:443 |
| `404` from Compass backend | Wrong model name | Confirm deployment names with Core42 |
| DNS resolution fails | Missing `azure-api.net` private DNS zone | Create zone + A record + VNet links |
| Foundry can't discover models | ListDeployments returns wrong format | Check policy returns `{"value":[...]}` with model objects |

## References

- [Sample: Foundry + APIM Integration](../references/sample-foundry-apim/)
- [Foundry AI Gateway Docs](https://learn.microsoft.com/en-us/azure/ai-foundry/agents/how-to/ai-gateway)
- [Bring your own AI Gateway](https://learn.microsoft.com/en-us/azure/ai-foundry/agents/how-to/tools/bring-your-own-ai-gateway)
