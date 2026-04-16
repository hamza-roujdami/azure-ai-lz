#!/usr/bin/env bash
set -uo pipefail

# ============================================================================
# AI Landing Zone — Network Validation
#
# Checks VNet peering, DNS zone links, ACR connectivity chain.
# Run after platform team configures network.
#
# Usage:
#   ./check-network.sh <bu> <env> <region_abbr> <org> <hub_instance>
#   ./check-network.sh csd dev swc cpx 002
# ============================================================================

BU="${1:?Usage: $0 <bu> <env> <region_abbr> <org> <hub_instance>}"
ENV="${2:?}"
REGION="${3:?}"
ORG="${4:?}"
HUB_INSTANCE="${5:-001}"

NETWORK_RG="rg-${BU}-network-${ENV}-${REGION}-001"
HUB_RG="rg-${ORG}-aihub-${ENV}-${REGION}-${HUB_INSTANCE}"
BU_VNET="vnet-${BU}-${ENV}-${REGION}-001"
HUB_VNET="vnet-${ORG}-hub-${ENV}-${REGION}-${HUB_INSTANCE}"
ACR="acr${ORG}${ENV}${REGION}${HUB_INSTANCE}"
ACA_UAMI="id-${BU}-aca-${ENV}-${REGION}-001"
GENAIAPP_RG="rg-${BU}-genaiapp-${ENV}-${REGION}-001"

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
echo "  AI Landing Zone — Network Check"
echo "  BU: ${BU} | Hub: ${ORG}"
echo "============================================"
echo ""

# ── VNet Peering ─────────────────────────────────────────────────────────
echo "── VNet Peering ──"
BU_TO_HUB=$(az network vnet peering list -g $NETWORK_RG --vnet-name $BU_VNET --query "[?contains(remoteVirtualNetwork.id,'$HUB_VNET')].peeringState" -o tsv 2>/dev/null)
check "BU → Hub peering" "${BU_TO_HUB:-NOT_FOUND}" "Connected"

HUB_TO_BU=$(az network vnet peering list -g $HUB_RG --vnet-name $HUB_VNET --query "[?contains(remoteVirtualNetwork.id,'$BU_VNET')].peeringState" -o tsv 2>/dev/null)
check "Hub → BU peering" "${HUB_TO_BU:-NOT_FOUND}" "Connected"
echo ""

# ── DNS Zone Links ───────────────────────────────────────────────────────
echo "── DNS Zone Links (Hub → BU VNet) ──"
ACR_DNS_LINK=$(az network private-dns link vnet list -g $HUB_RG -z privatelink.azurecr.io --query "[?contains(virtualNetwork.id,'$BU_VNET')].virtualNetworkLinkState" -o tsv 2>/dev/null)
check "ACR DNS zone → BU VNet" "${ACR_DNS_LINK:-NOT_FOUND}" "Completed"

echo ""
echo "── DNS Zone Links (BU — local services) ──"
for zone in privatelink.cognitiveservices.azure.com privatelink.openai.azure.com privatelink.services.ai.azure.com privatelink.search.windows.net privatelink.documents.azure.com privatelink.blob.core.windows.net privatelink.vaultcore.azure.net; do
  LINK=$(az network private-dns link vnet list -g $NETWORK_RG -z $zone --query "[0].virtualNetworkLinkState" -o tsv 2>/dev/null)
  check "$zone" "${LINK:-NOT_FOUND}" "Completed"
done
echo ""

# ── ACR PE DNS Records ───────────────────────────────────────────────────
echo "── ACR PE DNS Records ──"
REGISTRY_IP=$(az network private-dns record-set a show -g $HUB_RG -z privatelink.azurecr.io -n $ACR --query "aRecords[0].ipv4Address" -o tsv 2>/dev/null)
check "ACR registry A record" "${REGISTRY_IP:-NOT_FOUND}" "10\."

DATA_IP=$(az network private-dns record-set a show -g $HUB_RG -z privatelink.azurecr.io -n "${ACR}.${REGION/swc/swedencentral}.data" --query "aRecords[0].ipv4Address" -o tsv 2>/dev/null || \
          az network private-dns record-set a show -g $HUB_RG -z privatelink.azurecr.io -n "${ACR}.uaenorth.data" --query "aRecords[0].ipv4Address" -o tsv 2>/dev/null)
check "ACR data endpoint A record" "${DATA_IP:-NOT_FOUND}" "10\."
echo ""

# ── ACR Pull Chain ───────────────────────────────────────────────────────
echo "── ACR Pull Chain ──"
check "ACR trusted services" \
  "$(az acr show -n $ACR --query networkRuleBypassOptions -o tsv 2>/dev/null)" \
  "AzureServices"

ACR_ID=$(az acr show -n $ACR --query id -o tsv 2>/dev/null)
UAMI_PRINCIPAL=$(az identity show -g $GENAIAPP_RG -n $ACA_UAMI --query principalId -o tsv 2>/dev/null)
if [[ -n "$UAMI_PRINCIPAL" && -n "$ACR_ID" ]]; then
  ACRPULL=$(az role assignment list --scope $ACR_ID --assignee $UAMI_PRINCIPAL --query "[?roleDefinitionName=='AcrPull'] | length(@)" -o tsv 2>/dev/null)
  check "AcrPull role ($ACA_UAMI → ACR)" "${ACRPULL:-0}" "[1-9]"
else
  echo "  ⚠️  SKIP  AcrPull check (UAMI or ACR not found)"
  ((SKIP++))
fi

# Check if health check app pulled successfully from ACR
APP_IMAGE=$(az containerapp show -g $GENAIAPP_RG -n lz-healthcheck --query "properties.template.containers[0].image" -o tsv 2>/dev/null)
if [[ -n "$APP_IMAGE" && "$APP_IMAGE" == *"$ACR"* ]]; then
  check "ACA image pulled from Hub ACR" "$APP_IMAGE" "$ACR"
else
  echo "  ⚠️  SKIP  No health check app deployed yet"
  ((SKIP++))
fi
echo ""

# ── Summary ──────────────────────────────────────────────────────────────
echo "============================================"
echo "  RESULTS: ✅ $PASS passed | ❌ $FAIL failed | ⚠️ $SKIP skipped"
echo "============================================"

[[ $FAIL -eq 0 ]] && exit 0 || exit 1
