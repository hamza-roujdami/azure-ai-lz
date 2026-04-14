# Azure AI Landing Zone

A **production-grade Infrastructure-as-Code** solution to build a secure Agentic AI platform on Azure. 

Built for organizations with multiple business units, multiple AI developer teams, and strict security requirements (CMK encryption, private networking, managed identities only).

## Architecture

Based on Microsoft's 

- [Baseline Microsoft Foundry Landing Zone](https://learn.microsoft.com/en-us/azure/architecture/ai-ml/architecture/baseline-microsoft-foundry-landing-zone) pattern, with design principles. 
- [Azure/AI-Landing-Zones](https://github.com/Azure/AI-Landing-Zones) — Microsoft's official AI Landing Zone reference
- [Azure/bicep-ptn-aiml-landing-zone](https://github.com/Azure/bicep-ptn-aiml-landing-zone) — Bicep AI/ML landing zone pattern
- [Azure-Samples/ai-hub-gateway-solution-accelerator](https://github.com/Azure-Samples/ai-hub-gateway-solution-accelerator) — APIM AI Gateway (Citadel)
- [microsoft-foundry/foundry-samples](https://github.com/microsoft-foundry/foundry-samples) — Foundry agent infrastructure & SDK samples

Each business unit gets its own subscription with **4 resource groups**, deployed in 4 phases:

> **Note:** The AI Hub RG can alternatively be deployed as a **separate shared subscription** at the org level — centralizing ACR, APIM, and external LLM connectivity across all BUs.

| Phase | Resource Group | What Gets Deployed |
|-------|----------------|---------------------|
| 1 — Network | `rg-{bu}-network` | VNet (4 subnets), NSGs, 8 Private DNS zones, Log Analytics, App Insights |
| 2 — AI Services | `rg-{bu}-aiservices` | AI Foundry Account + Project, Key Vault, Storage, Cosmos DB, AI Search — all with CMK + Private Endpoints |
| 3 — GenAI App | `rg-{bu}-genaiapp` | Container Apps Environment, App Key Vault, App Storage, Managed Identity |
| 4 — AI Hub | `rg-{org}-aihub` | ACR + AcrPull roles for BUs, APIM AI Gateway (toggleable), External LLM PE (toggleable) |

```
┌─────────────────────────────────────────────────────────────┐
│  BU Subscription                                            │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ Network RG                                          │    │
│  │ VNet │ snet-pe │ snet-aca │ snet-agents │ snet-apim │    │
│  │ NSGs │ Private DNS zones │ Log Analytics             │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
│  ┌──────────────────────┐  ┌────────────────────────────┐   │
│  │ AI Services RG       │  │ GenAI App RG               │   │
│  │ AI Foundry Account   │  │ Container Apps Env         │   │
│  │  └─ Project(s)       │  │  └─ Frontend / Orchestrator│   │
│  │  └─ Agent Service    │  │ App Key Vault              │   │
│  │ Key Vault (CMK)      │  │ App Storage                │   │
│  │ Storage (CMK, ZRS)   │  │ Managed Identity           │   │
│  │ Cosmos DB (CMK)      │  └────────────────────────────┘   │
│  │ AI Search (CMK)      │                                   │
│  └──────────────────────┘                                   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ AI Hub RG                                           │    │
│  │ ACR │ APIM AI Gateway │ External LLM PE             │    │
│  │ Hub Key Vault │ Hub Managed Identity                 │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

## Security Posture

- **CMK encryption** on all 4 data stores (Storage, Cosmos DB, AI Foundry Account, AI Search)
- **Private Endpoints only** — zero public network access on every resource
- **Managed identities only** — no local auth, no shared keys, no connection strings
- **Zone-redundant storage** (ZRS) with infrastructure encryption
- **Infrastructure encryption** (double encryption) on Storage accounts
- **TLS 1.2+** enforced everywhere
- **No public IPs** — deny direct internet exposure
- **Soft-delete + purge protection** on all Key Vaults
- **Diagnostic logging** to Log Analytics on all resources
- **RBAC on Key Vaults** (no access policies)
- **Zero deployment scripts** — policy-safe (no ACI/deploymentScripts dependencies)

## Quick Start

### Prerequisites

- Azure CLI ≥ 2.60 with Bicep ≥ 0.30
- **Two subscriptions:** one for BU workloads, one for AI Hub (ACR, APIM, Compass)
- Owner or Contributor + User Access Administrator on both subscriptions

### Deploy

```bash
cd infra/bicep
export DEPLOYER_PRINCIPAL_ID=$(az ad signed-in-user show --query id -o tsv)

# ── Hub Subscription ──────────────────────────────────────────────────────
az account set -s <HUB_SUBSCRIPTION_ID>

# Phase 4 — AI Hub (deploy first — creates ACR, Hub VNet, DNS zones)
az deployment sub create -l uaenorth -p params/aihub.bicepparam

# ── BU Subscription ───────────────────────────────────────────────────────
az account set -s <BU_SUBSCRIPTION_ID>

# Phase 1 — Network (BU spoke VNet, no ACR DNS zone — Hub owns it)
az deployment sub create -l uaenorth -p params/csd-network.bicepparam

# Phase 2 — AI Services (update resource IDs in param file with Phase 1 outputs)
az deployment sub create -l uaenorth -p params/csd-aiservices.bicepparam

# Phase 3 — GenAI App (update acrId with Hub ACR resource ID)
az deployment sub create -l uaenorth -p params/csd-genaiapp.bicepparam

# ── Back to Hub Subscription ──────────────────────────────────────────────
az account set -s <HUB_SUBSCRIPTION_ID>

# Grant AcrPull to BU identity (get principalId from Phase 3 output)
az deployment sub create -l uaenorth -p params/aihub.bicepparam \
  -p buAcrPullPrincipals='[{"name":"csd","principalId":"<PHASE3_OUTPUT>"}]'
```

Each phase takes 3-8 minutes. Deploy in order — Phase 2+ references outputs from Phase 1.

## File Structure

```
infra/
├── bicep/
│   ├── main-network.bicep              # Phase 1: VNet, subnets, NSGs, DNS zones, monitoring
│   ├── main-aiservices.bicep           # Phase 2: AI Foundry + data stores (CMK, PE-only)
│   ├── main-genaiapp.bicep             # Phase 3: Container Apps, app data stores
│   ├── main-aihub.bicep                # Phase 4: ACR, APIM AI Gateway, external LLM PE
│   ├── bicepconfig.json                # Linter rules (29 rules, strict)
│   ├── modules/
│   │   ├── aiservices/                 # Custom AI Foundry + Cosmos modules (policy-safe)
│   │   │   ├── ai-foundry-account.bicep
│   │   │   ├── ai-foundry-project.bicep
│   │   │   ├── ai-foundry-rbac.bicep
│   │   │   ├── ai-foundry-capability-hosts.bicep
│   │   │   ├── cosmos-db-account.bicep # Raw Bicep (AVM lacks CMK support)
│   │   │   ├── cmk-encryption.bicep
│   │   │   ├── kv-role-assignment.bicep
│   │   │   └── foundry-apim-connection.bicep  # Foundry → APIM external LLM connection
│   │   ├── aihub/
│   │   │   ├── apim-premiumv2.bicep    # APIM AI Gateway (toggleable)
│   │   │   ├── apim-compass-api.bicep  # Compass API + operations + policies on APIM
│   │   │   ├── apim-kv-role.bicep      # APIM MI → KV Secrets User (for Named Values)
│   │   │   ├── compass-pe.bicep        # External LLM Private Endpoint (toggleable)
│   │   │   └── acr-pull-role.bicep     # AcrPull role assignment (BU identity → Hub ACR)
│   │   └── aiservices/                 # Custom AI Foundry + Cosmos modules (policy-safe)
│   └── params/
│       ├── aihub.bicepparam            # AI Hub (Hub subscription)
│       ├── csd-network.bicepparam      # CSD BU network (BU subscription)
│       ├── csd-aiservices.bicepparam   # CSD BU AI services (BU subscription)
│       └── csd-genaiapp.bicepparam     # CSD BU GenAI app (BU subscription)
└── tf/                                 # Terraform equivalent (planned)
```

## Customization

Edit the parameter files in `infra/bicep/params/` to configure for your environment:

| Parameter | Where | What to change |
|-----------|-------|----------------|
| `businessUnit` | All params | Your BU code (e.g., `fin`, `hr`, `eng`) |
| `environment` | All params | `dev`, `staging`, `prod` |
| `location` | All params | Azure region (`swedencentral`, `uaenorth`, etc.) |
| `deployApim` | aihub params | `true` to deploy APIM AI Gateway |
| `deployExternalLlmPe` | aihub params | `true` to deploy external LLM Private Endpoint |
| `deployCompassApi` | aihub params | `true` to configure Compass API on APIM (requires `deployApim`) |
| `deployApimConnection` | aiservices params | `true` to create Foundry → APIM connection for external LLM |
| `buAcrPullPrincipals` | aihub params | Array of BU identities needing AcrPull: `[{name:"csd", principalId:"xxx"}]` |
| `deployerPrincipalId` | aiservices params | Your Entra Object ID for Key Vault admin |

## Hub-Spoke Network (Cross-Subscription ACR Access)

When the AI Hub is in a **separate subscription**, BU Container Apps and Foundry agents reach the hub ACR through the **platform firewall** (no VNet peering between spokes).

### Firewall rules required

| Rule | Source (BU spoke) | Destination (AI Hub) | Port | Protocol |
|------|-------------------|---------------------|------|----------|
| ACA → ACR | `snet-aca` | ACR PE private IP | 443 | TCP |
| Agents → ACR | `snet-foundry-agents` | ACR PE private IP | 443 | TCP |
| ACA → APIM | `snet-aca` | APIM private IP | 443 | TCP |
| Agents → APIM | `snet-foundry-agents` | APIM private IP | 443 | TCP |
| APIM → Compass | `snet-apim` | Compass PE private IP | 443 | TCP |

### DNS resolution

BU spoke VNets must resolve `privatelink.azurecr.io` and `privatelink.azure-api.net` to the hub PE private IPs. This requires the platform's existing DNS forwarding infrastructure (Azure DNS Private Resolver or conditional forwarders).

### RBAC (AcrPull)

Pass BU identity principal IDs to `main-aihub.bicep` via the `buAcrPullPrincipals` param. As BUs onboard, add their UAMI and redeploy:

```bash
az account set -s <HUB_SUBSCRIPTION_ID>
az deployment sub create -l uaenorth -p params/aihub.bicepparam \
  -p buAcrPullPrincipals='[{"name":"csd","principalId":"<id>"},{"name":"fin","principalId":"<id>"}]'
```

Docs: [ACR Private Link](https://learn.microsoft.com/azure/container-registry/container-registry-private-link) · [ACR Firewall Rules](https://learn.microsoft.com/azure/container-registry/container-registry-firewall-access-rules) · [Container Apps Networking](https://learn.microsoft.com/azure/container-apps/networking)

## Why Custom Modules Instead of AVM Patterns?

The [AVM AI Foundry pattern](https://github.com/Azure/bicep-registry-modules/tree/main/avm/ptn/ai-ml/ai-foundry) uses `deploymentScripts` (which requires ACI). Enterprise policies like **Zone Resilient** and **MCSB v2** block ACI creation. This landing zone uses raw Bicep modules for AI Foundry, achieving the same result without deployment scripts.

Similarly, the **AVM Cosmos DB module** (v0.18.0) doesn't yet support `customerManagedKey`, so a custom Cosmos module is used.

## External LLM Provider — Core42 Compass

This landing zone uses [Core42 Compass](https://www.core42.ai/compass/documentation/compass-api-faqs) as the external LLM provider, accessed entirely over **Azure Private Link** — no public internet.

> **Compass is optional.** All Compass modules are **toggled off by default**. Deploy Phases 1–4 without any Core42 details — the full AI platform (networking, Foundry, data stores, Container Apps, ACR) works independently. Enable Compass later when ready.

### What you need from Core42

| Item | Where to use | How to get it |
|------|-------------|---------------|
| **Resource ID** (App Gateway) | `compassResourceId` param in Phase 4 | Request from Compass team |
| **Sub-resource ID** | `compassGroupId` param (default: `fep1`) | Request from Compass team |
| **API Key** | Store as secret in Hub Key Vault | Compass team provides after PE approval |
| **Model names** (e.g., `jais-70b`) | `compassModels` param in Phase 4 | Compass documentation / team |

### Deployment guide

**Stage 1 — Deploy without Compass** (no Core42 dependency):

```bash
# Hub subscription — deploy AI Hub first
az account set -s <HUB_SUBSCRIPTION_ID>
az deployment sub create -l uaenorth -p params/aihub.bicepparam

# BU subscription — deploy BU phases
az account set -s <BU_SUBSCRIPTION_ID>
az deployment sub create -l uaenorth -p params/csd-network.bicepparam
az deployment sub create -l uaenorth -p params/csd-aiservices.bicepparam
az deployment sub create -l uaenorth -p params/csd-genaiapp.bicepparam
```

**Stage 2 — Enable Compass** (once you have Core42 details):

```bash
# 2a. Redeploy AI Hub with Compass PE + APIM enabled (Hub subscription)
az account set -s <HUB_SUBSCRIPTION_ID>
az deployment sub create -l uaenorth -p params/aihub.bicepparam \
  -p deployApim=true \
  -p deployCompassPe=true \
  -p compassResourceId='<Resource ID from Core42>' \
  -p deployCompassApi=true \
  -p compassModels='["jais-70b","falcon-180b"]'

# 2b. Wait for Core42 to approve the PE (typically within 24h)

# 2c. Store Compass API key in Hub Key Vault
az keyvault secret set --vault-name kv-<org>-hub-<env>-<region>-001 \
  --name compass-api-key --value '<API key from Core42>'

# 2d. Redeploy Phase 2 with Foundry → APIM connection (BU subscription)
az account set -s <BU_SUBSCRIPTION_ID>
az deployment sub create -l uaenorth -p params/csd-aiservices.bicepparam \
  -p deployApimConnection=true \
  -p apimCompassEndpointUrl='https://<apim-name>.azure-api.net/compass' \
  -p apimSubscriptionKey='<APIM subscription key>'
```

Agents can now reference models as `compass-connection/jais-70b`.

### How it works

```
Foundry Agent ─→ ApiManagement Connection ─→ APIM AI Gateway ─→ PE ─→ Core42 Compass
                 (compass-connection)         (compass-api)             (manual approval)
```

The integration spans two deployment phases:

**Phase 4 — AI Hub** (infrastructure):
1. `apim-premiumv2.bicep` — deploys the APIM instance
2. `compass-pe.bicep` — creates a manual PE to Compass App Gateway (sub-resource `fep1`). The Compass team must review and approve (typically within 24h)
3. `apim-kv-role.bicep` — grants APIM system MI access to Hub Key Vault secrets
4. `apim-compass-api.bicep` — configures an OpenAI-compatible API on APIM with 3 operations:
   - **ListDeployments** — returns available models (static JSON, parameterizable)
   - **GetDeployment** — returns model details (dynamic from URL path)
   - **ChatCompletions** — forwards to Compass, injects API key from Key Vault via Named Value

**Phase 2 — AI Services** (Foundry connection):
5. `foundry-apim-connection.bicep` — creates an `ApiManagement` category connection on the Foundry project, pointing to the APIM Compass endpoint. Agents reference models as `compass-connection/jais-70b`

> **Note:** The Compass PE module uses `manualPrivateLinkServiceConnections` (not auto-approve) because Core42 manages the target resource. This is the standard pattern for connecting to third-party SaaS providers via Private Link.
>
> APIM API key handling uses Key Vault Named Values (not hardcoded in policies). Based on the [sample-foundry-apim](https://github.com/nstijepovic/sample-foundry-apim) integration pattern.

## Cost Estimate (DEV, per month)

| Scope | Estimate |
|-------|----------|
| 1 BU subscription (foundation, no APIM) | ~$410 |
| 1 BU subscription (with APIM + ACR) | ~$3,700 |

Top per-BU costs: APIM Premium v2 ($2,800 if enabled), AI Search S1 ($274), Cosmos serverless (~$50), Private Endpoints (~$56).