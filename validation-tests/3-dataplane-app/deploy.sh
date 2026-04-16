#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Deploy LZ Health Check app to Azure Container Apps
#
# Usage:
#   cd app/
#   ./deploy.sh
#
# Prerequisites:
#   - az CLI logged in to BU subscription
#   - ACR accessible (AcrPush role on Hub ACR)
#   - ACA environment deployed (Phase 3)
# ============================================================================

# --- Configuration (update for your environment) ---
ACR_NAME="acrcpxdevswc002"
ACR_LOGIN_SERVER="${ACR_NAME}.azurecr.io"
IMAGE_NAME="lz-healthcheck"
IMAGE_TAG="v1"

RG="rg-csd-genaiapp-dev-swc-001"
ACA_ENV="cae-csd-dev-swc-001"
ACA_APP_NAME="lz-healthcheck"
UAMI_NAME="id-csd-aca-dev-swc-001"
UAMI_RG="rg-csd-genaiapp-dev-swc-001"

# Service endpoints (from deployed infra)
FOUNDRY_ENDPOINT="https://ais-csd-dev-swc-001.services.ai.azure.com"
PROJECT_NAME="proj-csd-default-dev-swc-001"
COSMOS_ENDPOINT="https://cosmos-csd-fnd-dev-swc-001.documents.azure.com:443/"
STORAGE_ACCOUNT="stcsdfnddevswc001"
SEARCH_ENDPOINT="https://srch-csd-dev-swc-001.search.windows.net"
FOUNDRY_KV_URL="https://kv-csd-fnd-dev-swc-001.vault.azure.net"
APP_KV_URL="https://kv-csd-app-dev-swc-001.vault.azure.net"

# --- Get UAMI resource ID and client ID ---
echo "Getting UAMI details..."
UAMI_ID=$(az identity show -g "$UAMI_RG" -n "$UAMI_NAME" --query id -o tsv)
UAMI_CLIENT_ID=$(az identity show -g "$UAMI_RG" -n "$UAMI_NAME" --query clientId -o tsv)

# --- Build and push image ---
echo "Building and pushing image to ${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG}..."
az acr build --registry "$ACR_NAME" --image "${IMAGE_NAME}:${IMAGE_TAG}" .

# --- Deploy to Container Apps ---
echo "Deploying to Container Apps..."
az containerapp create \
  --name "$ACA_APP_NAME" \
  --resource-group "$RG" \
  --environment "$ACA_ENV" \
  --image "${ACR_LOGIN_SERVER}/${IMAGE_NAME}:${IMAGE_TAG}" \
  --registry-server "$ACR_LOGIN_SERVER" \
  --registry-identity "$UAMI_ID" \
  --user-assigned "$UAMI_ID" \
  --target-port 8080 \
  --ingress internal \
  --min-replicas 1 \
  --max-replicas 1 \
  --env-vars \
    AZURE_CLIENT_ID="$UAMI_CLIENT_ID" \
    FOUNDRY_ENDPOINT="$FOUNDRY_ENDPOINT" \
    PROJECT_NAME="$PROJECT_NAME" \
    COSMOS_ENDPOINT="$COSMOS_ENDPOINT" \
    STORAGE_ACCOUNT="$STORAGE_ACCOUNT" \
    SEARCH_ENDPOINT="$SEARCH_ENDPOINT" \
    FOUNDRY_KV_URL="$FOUNDRY_KV_URL" \
    APP_KV_URL="$APP_KV_URL"

echo ""
echo "✅ Deployed! App is internal-only (no public access)."
echo ""
echo "To test from inside the VNet:"
echo "  curl https://${ACA_APP_NAME}.internal.<env-domain>/health/all"
echo ""
echo "To get the FQDN:"
echo "  az containerapp show -g $RG -n $ACA_APP_NAME --query properties.configuration.ingress.fqdn -o tsv"
