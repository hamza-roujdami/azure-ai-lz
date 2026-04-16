# AI Landing Zone — Health Check App

FastAPI app that validates infrastructure connectivity from inside the VNet. Runs on Container Apps using managed identity — zero secrets.

## Endpoints

| Endpoint | What it tests |
|----------|-------------|
| `GET /health` | App is running |
| `GET /health/keyvault` | Foundry KV + App KV accessible via MI |
| `GET /health/storage` | Blob write/read on Foundry Storage |
| `GET /health/cosmos` | Document CRUD on Foundry Cosmos DB |
| `GET /health/search` | Index create/list on AI Search |
| `GET /health/foundry` | AI Foundry project accessible via SDK |
| `GET /health/compass` | APIM model list + chat (skips if not configured) |
| `GET /health/all` | All checks in parallel, returns JSON summary |

## Deploy

### Prerequisites

- Infra deployed (Phases 1–4)
- AcrPull granted to BU ACA identity on Hub ACR
- Network path open: BU ACA subnet → Hub ACR PE (firewall or VNet peering)
- Hub ACR DNS zone linked to BU VNet

### Build and deploy

```bash
cd app/

# 1. Build image on Hub ACR (requires temporary public access)
az acr update -n <ACR_NAME> --public-network-enabled true --default-action Allow -o none
az acr build --registry <ACR_NAME> --image lz-healthcheck:v1 .
az acr update -n <ACR_NAME> --public-network-enabled false --default-action Deny -o none

# 2. Get BU ACA identity
UAMI_ID=$(az identity show -g rg-<bu>-genaiapp-<env>-<region>-001 -n id-<bu>-aca-<env>-<region>-001 --query id -o tsv)
UAMI_CLIENT_ID=$(az identity show -g rg-<bu>-genaiapp-<env>-<region>-001 -n id-<bu>-aca-<env>-<region>-001 --query clientId -o tsv)

# 3. Deploy to Container Apps
az containerapp create \
  --name lz-healthcheck \
  --resource-group rg-<bu>-genaiapp-<env>-<region>-001 \
  --environment cae-<bu>-<env>-<region>-001 \
  --image <ACR_NAME>.azurecr.io/lz-healthcheck:v1 \
  --registry-server <ACR_NAME>.azurecr.io \
  --registry-identity "$UAMI_ID" \
  --user-assigned "$UAMI_ID" \
  --target-port 8080 \
  --ingress internal \
  --min-replicas 1 --max-replicas 1 \
  --env-vars \
    AZURE_CLIENT_ID="$UAMI_CLIENT_ID" \
    FOUNDRY_ENDPOINT=https://ais-<bu>-<env>-<region>-001.services.ai.azure.com \
    PROJECT_NAME=proj-<bu>-default-<env>-<region>-001 \
    COSMOS_ENDPOINT=https://cosmos-<bu>-fnd-<env>-<region>-001.documents.azure.com:443/ \
    STORAGE_ACCOUNT=st<bu>fnd<env><region>001 \
    SEARCH_ENDPOINT=https://srch-<bu>-<env>-<region>-001.search.windows.net \
    FOUNDRY_KV_URL=https://kv-<bu>-fnd-<env>-<region>-001.vault.azure.net \
    APP_KV_URL=https://kv-<bu>-app-<env>-<region>-001.vault.azure.net
```

### Test (from inside the VNet)

The app is internal-only. Test via `az containerapp exec`:

```bash
az containerapp exec -g rg-<bu>-genaiapp-<env>-<region>-001 -n lz-healthcheck \
  --command "python3 -c \"import urllib.request; print(urllib.request.urlopen('http://localhost:8080/health/all').read().decode())\""
```

Or from a jump VM / Bastion:

```bash
curl https://lz-healthcheck.internal.<env-domain>/health/all
```

### Expected output

```json
{
  "summary": {"total": 8, "passed": 5, "failed": 0, "skipped": 3},
  "checks": [
    {"name": "foundry-kv",     "status": "pass", "latency_ms": 120},
    {"name": "app-kv",         "status": "pass", "latency_ms": 95},
    {"name": "storage",        "status": "pass", "latency_ms": 200},
    {"name": "cosmos",         "status": "pass", "latency_ms": 180},
    {"name": "search",         "status": "pass", "latency_ms": 150},
    {"name": "foundry",        "status": "pass", "latency_ms": 300},
    {"name": "compass-models", "status": "fail", "message": "APIM_COMPASS_URL not configured"},
    {"name": "compass-chat",   "status": "fail", "message": "APIM_COMPASS_URL not configured"}
  ]
}
```

Compass checks fail until APIM + Core42 Compass are configured. All other checks should pass.

## RBAC required

The ACA UAMI (`id-<bu>-aca`) needs roles on BU data stores to run all checks:

| Service | Role needed | Granted by |
|---------|------------|------------|
| Hub ACR | AcrPull | `main-aihub.bicep` (buAcrPullPrincipals) |
| Foundry KV | Key Vault Secrets User | Manual or add to Bicep |
| App KV | Key Vault Secrets User | Manual or add to Bicep |
| Storage | Storage Blob Data Contributor | Manual or add to Bicep |
| Cosmos DB | Cosmos DB Data Contributor | Manual or add to Bicep |
| AI Search | Search Index Data Reader | Manual or add to Bicep |
