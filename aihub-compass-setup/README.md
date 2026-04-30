# AI Hub — External LLM Gateway Setup on Existing APIM

## Overview

This setup connects **Microsoft Foundry agents** to **external OpenAI-compatible LLMs** (e.g., Core42 Compass) through **Azure API Management (APIM)** — enabling enterprise AI workloads to use external language models securely, without exposing API keys or opening public endpoints.

### The Problem

External LLM providers (e.g., Core42 Compass) expose models via private endpoints. But Foundry agents can't call them directly — they need an OpenAI-compatible gateway that handles authentication, model discovery, and request routing.

### The Solution

APIM acts as a **secure proxy** between Foundry and the external LLM provider:

```
Foundry Agent (BU spoke)
  → APIM connection (category: ApiManagement)
    → APIM Gateway (hub, internal VNet)
      → Policy injects LLM API key from Key Vault
        → LLM Private Endpoint
          → External LLM (e.g., Core42 Compass)
```

**What this gives you:**
- **Zero secrets in code** — LLM API key stored in Key Vault, injected at runtime via APIM Named Value
- **Fully private** — APIM in Internal VNet mode, LLM via Private Endpoint, no public access
- **Foundry-compatible** — APIM exposes OpenAI-compatible endpoints (`/deployments`, `/chat/completions`, `/embeddings`, `/score`) so Foundry can discover and use models natively
- **Reusable** — deploy multiple APIs with different keys, models, or paths by changing parameters
- **Per-BU isolation** — each Business Unit gets its own Foundry connection and APIM subscription key

### 3 Steps

| Step | What | Folder |
|------|------|--------|
| **1** | Configure LLM API on existing APIM (RBAC, Named Value, API, 5 operations, policies, Product) | `01-apim-setup/` |
| **2** | Create Foundry → APIM connection (per BU project) | `02-foundry-connection/` |
| **3** | Test with a Foundry agent (Python SDK) | `03-agent-test/` |

## Prerequisites

- [x] APIM provisioned (portal) with **system-assigned managed identity enabled**
- [x] LLM Private Endpoint approved (e.g., Core42 Compass PE)
- [x] Hub Key Vault with LLM API key secret stored
- [x] APIM DNS zone (`azure-api.net`) with A record → APIM private IP
- [x] Model deployment names confirmed

## What's in this folder

```
aihub-compass-setup/
├── 01-apim-setup/
│   ├── main.bicep              # LLM API on APIM (RBAC, Named Value, API, operations, policies, Product)
│   └── policies/
│       ├── forward-with-key.xml    # Injects LLM API key, forwards to backend (Chat, Embeddings, Score)
│       └── get-deployment.xml      # Returns model detail dynamically (C# expression)
├── 02-foundry-connection/
│   └── foundry-connection.bicep    # Foundry → APIM connection (deploy per BU project)
├── 03-agent-test/
│   ├── .env.example            # Environment config (copy to .env)
│   ├── test_connection.py      # Verify APIM connection in Foundry
│   ├── create_agent.py         # Create agent using external LLM model
│   ├── chat_with_agent.py      # Interactive chat with agent
│   └── pyproject.toml          # Python dependencies
└── README.md                   # This file
```

## Step 1 — Configure LLM API on APIM

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

> Models default to 6 Core42 Compass models. Override with `-p compassModels='["model1","model2"]'` if using a different provider.

### Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `apimName` | Yes | — | Existing APIM resource name |
| `keyVaultName` | Yes | — | Existing Hub KV name (must have LLM API key secret) |
| `apimPrincipalId` | Yes | — | APIM system MI principal ID (`az apim show ... --query identity.principalId`) |
| `backendUrl` | No | `https://api.core42.ai/openai` | LLM backend URL (PE IP or FQDN) |
| `compassApiKeySecretName` | No | `compass-api-key` | Secret name in Key Vault |
| `apiName` | No | `compass-api` | API identifier in APIM (unique per API) |
| `apiPath` | No | `compass` | API URL path prefix |
| `apiDisplayName` | No | `Compass API` | API display name |
| `compassModels` | No | 6 Core42 models | Model deployment names |
| `productName` | No | `compass` | APIM Product name |
| `productDisplayName` | No | `Compass` | Product display name |

### What it creates

| Resource | Purpose |
|----------|---------|
| RBAC: APIM MI → KV Secrets User | APIM reads API key from Key Vault |
| Named Value: `compass-api-key` | Key Vault reference (not hardcoded) |
| API: `compass-api` (path `/compass`) | OpenAI-compatible proxy |
| Op: `GET /deployments` | Returns static model list (for Foundry discovery) |
| Op: `GET /deployments/{name}` | Returns model detail (dynamic) |
| Op: `POST /deployments/{id}/chat/completions` | Forwards chat requests to LLM backend |
| Op: `POST /deployments/{id}/embeddings` | Forwards embedding requests to LLM backend |
| Op: `POST /deployments/{id}/score` | Forwards reranker/scoring requests to LLM backend |
| Product + Subscription | Generates APIM subscription key for consumers |

### Get the APIM subscription key

```bash
# Via REST API
az rest --method POST \
  --url "/subscriptions/<SUB_ID>/resourceGroups/<HUB_RG>/providers/Microsoft.ApiManagement/service/<APIM_NAME>/subscriptions/<PRODUCT_NAME>-sub/listSecrets?api-version=2022-08-01" \
  --query primaryKey -o tsv
```

Or from portal: **APIM → Subscriptions → Show primary key**.

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
