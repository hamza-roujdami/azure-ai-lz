#!/usr/bin/env bash
set -uo pipefail

# ============================================================================
# AI Landing Zone — Infrastructure Validation
#
# Checks all deployed resources from CLI (no VNet access needed).
# Run after deploying Phases 1-4.
#
# Usage:
#   ./check-infra.sh <bu> <env> <region_abbr> <org> <hub_instance>
#   ./check-infra.sh csd dev swc cpx 002
# ============================================================================

BU="${1:?Usage: $0 <bu> <env> <region_abbr> <org> <hub_instance>}"
ENV="${2:?}"
REGION="${3:?}"
ORG="${4:?}"
HUB_INSTANCE="${5:-001}"

# Resource names
NETWORK_RG="rg-${BU}-network-${ENV}-${REGION}-001"
AISERVICES_RG="rg-${BU}-aiservices-${ENV}-${REGION}-001"
GENAIAPP_RG="rg-${BU}-genaiapp-${ENV}-${REGION}-001"
HUB_RG="rg-${ORG}-aihub-${ENV}-${REGION}-${HUB_INSTANCE}"

STORAGE="st${BU}fnd${ENV}${REGION}001"
COSMOS="cosmos-${BU}-fnd-${ENV}-${REGION}-001"
SEARCH="srch-${BU}-${ENV}-${REGION}-001"
AI_ACCOUNT="ais-${BU}-${ENV}-${REGION}-001"
PROJECT="${AI_ACCOUNT}/proj-${BU}-default-${ENV}-${REGION}-001"
FOUNDRY_KV="kv-${BU}-fnd-${ENV}-${REGION}-001"
APP_KV="kv-${BU}-app-${ENV}-${REGION}-001"
HUB_KV="kv-${ORG}-hub-${ENV}-${REGION}-${HUB_INSTANCE}"
ACR="acr${ORG}${ENV}${REGION}${HUB_INSTANCE}"
ACA_ENV="cae-${BU}-${ENV}-${REGION}-001"
ACA_UAMI="id-${BU}-aca-${ENV}-${REGION}-001"

PASS=0
FAIL=0
SKIP=0

check() {
  local name="$1"
  local result="$2"
  local expected="$3"

  if [[ -z "$result" ]]; then
    echo "  ⚠️  SKIP  $name (no result)"
    ((SKIP++))
  elif echo "$result" | grep -qi "$expected"; then
    echo "  ✅ PASS  $name → $result"
    ((PASS++))
  else
    echo "  ❌ FAIL  $name → $result (expected: $expected)"
    ((FAIL++))
  fi
}

echo "============================================"
echo "  AI Landing Zone — Infrastructure Check"
echo "  BU: ${BU} | Env: ${ENV} | Region: ${REGION}"
echo "  Hub: ${ORG} (instance ${HUB_INSTANCE})"
echo "============================================"
echo ""

# ── Resource Groups ──────────────────────────────────────────────────────
echo "── Resource Groups ──"
for rg in "$NETWORK_RG" "$AISERVICES_RG" "$GENAIAPP_RG" "$HUB_RG"; do
  state=$(az group show -n "$rg" --query properties.provisioningState -o tsv 2>/dev/null || echo "NOT_FOUND")
  check "$rg" "$state" "Succeeded"
done
echo ""

# ── CMK Encryption ───────────────────────────────────────────────────────
echo "── CMK Encryption ──"
check "Storage CMK" \
  "$(az storage account show -g $AISERVICES_RG -n $STORAGE --query encryption.keySource -o tsv 2>/dev/null)" \
  "Microsoft.Keyvault"

check "Cosmos CMK" \
  "$(az cosmosdb show -g $AISERVICES_RG -n $COSMOS --query keyVaultKeyUri -o tsv 2>/dev/null)" \
  "vault.azure.net"

check "AI Account CMK" \
  "$(az cognitiveservices account show -g $AISERVICES_RG -n $AI_ACCOUNT --query properties.encryption.keySource -o tsv 2>/dev/null)" \
  "Microsoft.KeyVault"

check "ACR CMK" \
  "$(az acr show -n $ACR --query encryption.status -o tsv 2>/dev/null)" \
  "enabled"
echo ""

# ── Public Network Access ────────────────────────────────────────────────
echo "── Public Network Access (all should be Disabled) ──"
check "Storage public access" \
  "$(az storage account show -g $AISERVICES_RG -n $STORAGE --query publicNetworkAccess -o tsv 2>/dev/null)" \
  "Disabled"

check "Cosmos public access" \
  "$(az cosmosdb show -g $AISERVICES_RG -n $COSMOS --query publicNetworkAccess -o tsv 2>/dev/null)" \
  "Disabled"

check "Search public access" \
  "$(az search service show -g $AISERVICES_RG -n $SEARCH --query publicNetworkAccess -o tsv 2>/dev/null)" \
  "Disabled"

check "ACR public access" \
  "$(az acr show -n $ACR --query publicNetworkAccess -o tsv 2>/dev/null)" \
  "Disabled"
echo ""

# ── Key Vault Security ───────────────────────────────────────────────────
echo "── Key Vault Security ──"
for kv in "$FOUNDRY_KV" "$APP_KV" "$HUB_KV"; do
  check "$kv purge protection" \
    "$(az keyvault show -n $kv --query properties.enablePurgeProtection -o tsv 2>/dev/null)" \
    "true"
done
echo ""

# ── Private Endpoints ────────────────────────────────────────────────────
echo "── Private Endpoints (AI Services) ──"
PE_COUNT=$(az network private-endpoint list -g $AISERVICES_RG --query "length(@)" -o tsv 2>/dev/null)
check "PE count (expected 5)" "$PE_COUNT" "5"
echo ""

# ── ACR Hub ──────────────────────────────────────────────────────────────
echo "── ACR Hub ──"
check "ACR trusted services" \
  "$(az acr show -n $ACR --query networkRuleBypassOptions -o tsv 2>/dev/null)" \
  "AzureServices"

check "AcrPull role exists" \
  "$(az role assignment list --scope $(az acr show -n $ACR --query id -o tsv 2>/dev/null) --query "[?roleDefinitionName=='AcrPull'] | length(@)" -o tsv 2>/dev/null)" \
  "[1-9]"
echo ""

# ── AI Foundry ───────────────────────────────────────────────────────────
echo "── AI Foundry ──"
check "AI Account state" \
  "$(az cognitiveservices account show -g $AISERVICES_RG -n $AI_ACCOUNT --query properties.provisioningState -o tsv 2>/dev/null)" \
  "Succeeded"

check "Project state" \
  "$(az resource show --ids /subscriptions/$(az account show --query id -o tsv)/resourceGroups/$AISERVICES_RG/providers/Microsoft.CognitiveServices/accounts/$PROJECT --api-version 2025-04-01-preview --query properties.provisioningState -o tsv 2>/dev/null)" \
  "Succeeded"

CONN_COUNT=$(az rest --method GET --uri "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$AISERVICES_RG/providers/Microsoft.CognitiveServices/accounts/$PROJECT/connections?api-version=2025-04-01-preview" --query "value | length(@)" -o tsv 2>/dev/null)
check "Project connections (expected 3)" "$CONN_COUNT" "3"

CAP_ACCOUNT=$(az rest --method GET --uri "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$AISERVICES_RG/providers/Microsoft.CognitiveServices/accounts/$AI_ACCOUNT/capabilityHosts?api-version=2025-04-01-preview" --query "value[0].properties.provisioningState" -o tsv 2>/dev/null)
check "Capability Host (Account)" "$CAP_ACCOUNT" "Succeeded"

CAP_PROJECT=$(az rest --method GET --uri "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$AISERVICES_RG/providers/Microsoft.CognitiveServices/accounts/$PROJECT/capabilityHosts?api-version=2025-04-01-preview" --query "value[0].properties.provisioningState" -o tsv 2>/dev/null)
check "Capability Host (Project)" "$CAP_PROJECT" "Succeeded"
echo ""

# ── GenAI App ────────────────────────────────────────────────────────────
echo "── GenAI App ──"
check "ACA Environment" \
  "$(az containerapp env show -g $GENAIAPP_RG -n $ACA_ENV --query properties.provisioningState -o tsv 2>/dev/null)" \
  "Succeeded"

check "ACA internal mode" \
  "$(az containerapp env show -g $GENAIAPP_RG -n $ACA_ENV --query 'properties.vnetConfiguration.internal' -o tsv 2>/dev/null)" \
  "true"
echo ""

# ── RBAC (Project MI → Backing Stores) ───────────────────────────────────
echo "── RBAC (Project MI → Backing Stores) ──"
PROJECT_MI=$(az resource show --ids /subscriptions/$(az account show --query id -o tsv)/resourceGroups/$AISERVICES_RG/providers/Microsoft.CognitiveServices/accounts/$PROJECT --api-version 2025-04-01-preview --query identity.principalId -o tsv 2>/dev/null)

if [[ -n "$PROJECT_MI" ]]; then
  STORAGE_ROLES=$(az role assignment list --assignee $PROJECT_MI --scope $(az storage account show -g $AISERVICES_RG -n $STORAGE --query id -o tsv 2>/dev/null) --query "[].roleDefinitionName" -o tsv 2>/dev/null | tr '\n' ', ')
  check "Project MI → Storage" "$STORAGE_ROLES" "Blob Data Contributor"

  COSMOS_ROLES=$(az role assignment list --assignee $PROJECT_MI --scope $(az cosmosdb show -g $AISERVICES_RG -n $COSMOS --query id -o tsv 2>/dev/null) --query "[].roleDefinitionName" -o tsv 2>/dev/null | tr '\n' ', ')
  check "Project MI → Cosmos" "$COSMOS_ROLES" "Operator"

  SEARCH_ROLES=$(az role assignment list --assignee $PROJECT_MI --scope $(az search service show -g $AISERVICES_RG -n $SEARCH --query id -o tsv 2>/dev/null) --query "[].roleDefinitionName" -o tsv 2>/dev/null | tr '\n' ', ')
  check "Project MI → Search" "$SEARCH_ROLES" "Index Data Contributor"
else
  echo "  ⚠️  SKIP  Project MI not found"
  ((SKIP+=3))
fi
echo ""

# ── Summary ──────────────────────────────────────────────────────────────
echo "============================================"
echo "  RESULTS: ✅ $PASS passed | ❌ $FAIL failed | ⚠️ $SKIP skipped"
echo "============================================"

[[ $FAIL -eq 0 ]] && exit 0 || exit 1
