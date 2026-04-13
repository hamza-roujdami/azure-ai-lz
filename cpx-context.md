# CPX AI Landing Zone — Full Project Context

> Last updated: April 10, 2026 — after AI Hub (ACR + CMK) deployment and policy audit.

## Customer Overview

- **Customer:** CPX (Enterprise, UAE)
- **Tenant:** Single Azure Entra ID tenant
- **Production region:** UAE North
- **Sandbox region:** Sweden Central (for testing in Microsoft subscriptions)
- **Existing Infrastructure:** Platform Landing Zone already deployed (Firewall, Bastion, DNS, ExpressRoute, Management subscription with Log Analytics, Defender, Azure Policy)

---

## Business Requirements

- CPX has **9 Business Units:** CSD, CRS, COM, MKT, CTE, CCS, PROC, FIN, CDO
- **~80+ AI use cases** across all BUs
- **3 external vendor teams** build the use cases:

| Vendor | Business Units | # BUs |
|--------|---------------|-------|
| Vendor A | CSD, CRS, COM, MKT | 4 |
| Vendor B | CTE, CCS, PROC, FIN | 4 |
| Vendor C | CDO | 1 |

- Each BU has exactly **1 vendor** (no overlap)
- Vendors are **external contractors** — may rotate every 1-2 years
- AI models are consumed from **Core42 Compass** (LLM + Embeddings) via Private Endpoint — **not deployed inside Azure AI Foundry**
- CPX requires full **private networking** — no public endpoints
- CPX wants to **standardize** the AI Landing Zone so every vendor uses the same technology stack

---

## Architecture Decisions Made

### Subscription Model: Per-BU Subscription
- **1 subscription per Business Unit per environment** (DEV / PROD)
- CPX Platform Team owns all subscriptions
- Vendors get RBAC on specific Resource Groups only
- **19 subscriptions total:** 1 AI Hub + 9 DEV + 9 PROD

### Alternatives Considered and Rejected

| Option | Description | Why Rejected |
|--------|------------|--------------|
| Subscription per Vendor | 1 sub per vendor, BUs as RGs inside | BU data scattered across vendor subs. Cost tracking per BU requires tagging. Vendor replacement = subscription migration (days). |
| Subscription per BU-Group | Groups of BUs in 1 sub | Grouping felt vendor-aligned. Ambiguous naming. Agent subnet constraint (multiple accounts per sub). |
| Single Subscription | All BUs in 1 sub | Insufficient isolation for production with 3 external vendors. |

### AI Hub: Centralized ACR + APIM (deferred)
- **cpx-ai-hub** subscription — separate from platform hub
- **Deployed today:** ACR Premium (CMK, zone-redundant, PE, AcrPull per BU UAMI) + Hub Key Vault (CMK key)
- **Deferred:** APIM AI Gateway (Premium, ~$2,800/mo — awaiting cost approval + Compass backend URL) + Core42 Compass PE (awaiting PLS ID from Core42)
- **Production design:** `main-aihub-cpx.bicep` — hub VNet with `snet-pe` (/25) + `snet-apim` (/24), NSGs (APIM mgmt rules), DNS zones, VNet peerings to all spokes
- **1 APIM workspace per BU** (ws-csd, ws-crs, ws-com, etc.) for per-BU rate limiting, API keys, usage tracking
- All LLM traffic: App → PE APIM (spoke) → Hub APIM (BU workspace) → PE Compass → Core42

### Resource Group Model: 3 RGs per BU + 1 Hub RG

**Naming convention:** `rg-{bu}-{function}-{env}-{region}-{instance}`

| RG | Example (CSD DEV) | Contains | Vendor Access | Protection |
|----|-------------------|---------|--------------|------------|
| **rg-{bu}-network-{env}-uaen-001** | rg-csd-network-dev-uaen-001 | VNet, 3 Subnets, 3 NSGs, 8 Private DNS zones, Log Analytics, App Insights | Reader | RG-level CanNotDelete lock |
| **rg-{bu}-aiservices-{env}-uaen-001** | rg-csd-aiservices-dev-uaen-001 | AI Foundry Account + Project + Agent Service + Capability Hosts, UAMI (CMK), Key Vault, Storage (CMK), Cosmos DB (CMK), AI Search (CMK enforcement) | Contributor | Resource-level locks on Account + data stores |
| **rg-{bu}-genaiapp-{env}-uaen-001** | rg-csd-genaiapp-dev-uaen-001 | UAMI (ACR pull), Container Apps Env, App Key Vault, App Storage (CMK) | Contributor | Resource-level locks on data stores |
| **rg-cpx-aihub-{env}-uaen-001** | rg-cpx-aihub-dev-uaen-001 | UAMI (CMK), Hub Key Vault, ACR Premium (CMK, PE), [APIM, Compass PE — deferred] | Platform only | N/A |

### Why 3 BU RGs (Not 2 or 4)
- **2 RGs** (shared + app) doesn't work because vendor needs Contributor on AI Foundry but shouldn't have Contributor on networking/data
- **4 RGs** (infra + ai + app + data) is over-engineered — separating data from ai/app creates friction for vendors debugging connectivity
- **3 RGs** gives clean separation: networking (Reader), AI development (Contributor), app deployment (Contributor)

---

## What's Deployed (Sandbox — Sweden Central)

### 4 Resource Groups — All Succeeded

| RG | Status | Template | Key Resources |
|----|--------|----------|---------------|
| `rg-csd-network-dev-swc-001` | Deployed | `main-network.bicep` | VNet (3 subnets, 3 NSGs), 8 DNS zones, LAW, AppInsights |
| `rg-csd-aiservices-dev-swc-001` | Deployed | `main-aiservices-custom.bicep` | AI Foundry (Account + Project + Agent Service), KV, Storage, Cosmos, Search — all CMK |
| `rg-csd-genaiapp-dev-swc-001` | Deployed | `main-genaiapp.bicep` | UAMI (`id-csd-aca`), Container Apps Env (internal, ZR), App KV, App Storage (CMK) |
| `rg-cpx-aihub-dev-swc-001` | Deployed | `main-aihub.bicep` | UAMI (`id-cpx-hub-cmk`), Hub KV, ACR Premium (CMK, PE, ZR) |

---

## Managed Identity Architecture

| Identity | Type | RG | Purpose | Roles |
|----------|------|-----|---------|-------|
| `id-csd-cmk-dev-swc-001` | User-Assigned | aiservices | CMK encryption key access | KV Crypto Service Encryption User on Foundry KV |
| `ais-csd-dev-swc-001` | System-Assigned | aiservices | AI Foundry Account operations | KV Crypto on Foundry KV (for Account CMK) |
| `proj-csd-default...` | System-Assigned | aiservices | AI Foundry Project data access | Blob Contributor on Storage, SQL role on Cosmos, Index Contributor on Search |
| `srch-csd-dev-swc-001` | System-Assigned | aiservices | AI Search CMK enforcement | KV Crypto on Foundry KV |
| `id-csd-aca-dev-swc-001` | User-Assigned | genaiapp | Container Apps ACR pull + app data | AcrPull on hub ACR (self-assigned via cross-RG module) |
| `id-cpx-hub-cmk-dev-swc-001` | User-Assigned | aihub | Hub ACR CMK encryption | KV Crypto Service Encryption User on Hub KV |

**Design decisions:**
- **CMK UAMI** separate from app identities — principle of least privilege, only has key unwrap access
- **ACA UAMI** is shared across all Container Apps in a BU — one identity for ACR pull + future app data access
- **AcrPull is self-contained**: each BU genaiapp template assigns its own AcrPull role on the hub ACR via `modules/acr-pull-role.bicep`. No hub redeploy needed when onboarding new BUs.

---

## Customer-Managed Keys (CMK) — Full Coverage

| RG | Service | CMK Enabled | Key Location | Identity |
|----|---------|------------|-------------|----------|
| aiservices | AI Foundry Account | Yes | `kv-csd-fnd` / `cmk-csd-dev` | Account System MI |
| aiservices | Storage (Foundry) | Yes | `kv-csd-fnd` / `cmk-csd-dev` | `id-csd-cmk` (UAMI) |
| aiservices | Cosmos DB | Yes | `kv-csd-fnd` / `cmk-csd-dev` | `id-csd-cmk` (UAMI) |
| aiservices | AI Search | Yes (enforcement) | Per-object at creation | Search System MI |
| genaiapp | App Storage | Yes | `kv-csd-fnd` / `cmk-csd-dev` | `id-csd-cmk` (UAMI, reuses BU key) |
| aihub | ACR | Yes | `kv-cpx-hub` / `cmk-hub-dev` | `id-cpx-hub-cmk` (UAMI, own hub key) |
| genaiapp | App Key Vault | N/A | Is the key store | N/A |
| aihub | Hub Key Vault | N/A | Is the key store | N/A |

**Important:** ACR CMK must be set at creation time — cannot be added retroactively. If CPX has a deny policy for non-CMK ACR, the template handles this from day one.

---

## Policy Compliance Audit (Verified April 10, 2026)

| Policy | Requirement | Status |
|--------|------------|--------|
| Private Endpoints only | `publicNetworkAccess: Disabled` | **All services compliant** |
| CMK encryption | Customer-managed keys on all data stores | **6/6 data services** |
| No shared keys | `allowSharedKeyAccess: false` on Storage | **Both storages** |
| No admin user | ACR admin disabled | **ACR** |
| No anonymous pull | ACR anonymous pull disabled | **ACR** |
| TLS 1.2 minimum | On all supporting services | **Storage (both), Cosmos** |
| Zone redundancy | ZRS/zone-redundant where available | **Storage (ZRS), ACR, Cosmos, Container Apps Env** |
| Soft-delete + purge protection | Key Vaults | **All 3 KVs** |
| Infrastructure encryption | Double encryption on Storage | **Both storages** |
| RBAC authorization | KV uses RBAC (not access policies) | **All 3 KVs** |
| Diagnostic logging | All services → LAW | **All services** |
| No deployment scripts | No `Microsoft.Resources/deploymentScripts` | **Zero found** (custom modules used) |
| Managed Identity only | No local auth / shared keys | **All services** |

**Known exception:** AI Search `disableLocalAuthentication` is not set — left enabled because AI Foundry Agent Service currently requires API key auth on Search for runtime index creation. If CPX enforces this policy, it needs testing with Agent Service first.

---

## IaC Repository

**GitHub:** https://github.com/hamza-roujdami/cpx-ai-lz (7 commits)

### Templates

| Template | Phase | Scope | Description |
|----------|-------|-------|-------------|
| `main-network.bicep` | 1 | BU | VNet, 3 subnets, 3 NSGs, 8 DNS zones, LAW, AppInsights |
| `main-aiservices-custom.bicep` | 2 | BU | AI Foundry + data stores with CMK — **recommended** (no deployment scripts) |
| `main-aiservices.bicep` | 2 | BU | AI Foundry via AVM pattern — unrestricted environments only |
| `main-genaiapp.bicep` | 3 | BU | Container Apps Env, App KV, App Storage (CMK), UAMI, AcrPull |
| `main-aihub.bicep` | 4 | Hub (sandbox) | ACR Premium (CMK, PE), Hub KV, Compass PE toggle, APIM toggle |
| `main-aihub-cpx.bicep` | 4 | Hub (production) | Hub VNet + subnets + NSGs + DNS + peerings + ACR + APIM + Compass |

### Custom Modules

| Module | Purpose |
|--------|---------|
| `modules/custom-ai-foundry/account.bicep` | AI Foundry Account (raw Bicep, no deployment scripts) |
| `modules/custom-ai-foundry/project.bicep` | Project + 3 Connections (Cosmos, Storage, Search) |
| `modules/custom-ai-foundry/rbac-assignments.bicep` | 6 RBAC roles (Project MI → data stores) |
| `modules/custom-ai-foundry/capability-hosts.bicep` | Agent Service capability hosts |
| `modules/ai-foundry/cmk-encryption.bicep` | CMK update on AI Foundry Account |
| `modules/ai-foundry/kv-role-assignment.bicep` | KV Crypto role for AI Account MI |
| `modules/cosmos-db-account.bicep` | Cosmos DB with CMK (raw Bicep — AVM doesn't support CMK yet) |
| `modules/acr-pull-role.bicep` | AcrPull role assignment (cross-RG, self-contained per BU) |

### AVM Modules Used

- `avm/res/key-vault/vault:0.13.3`
- `avm/res/storage/storage-account:0.26.2`
- `avm/res/search/search-service:0.11.1`
- `avm/res/managed-identity/user-assigned-identity:0.4.0`
- `avm/res/network/virtual-network:0.7.0`
- `avm/res/network/network-security-group:0.5.0`
- `avm/res/network/private-dns-zone:0.7.0`
- `avm/res/network/private-endpoint:0.12.0`
- `avm/res/operational-insights/workspace:0.12.0`
- `avm/res/insights/component:0.6.0`
- `avm/res/app/managed-environment:0.8.0`
- `avm/res/container-registry/registry:0.12.0`
- `avm/res/api-management/service:0.12.0`

---

## Deployment Order (for a new BU)

```
Phase 4: Hub  → main-aihub.bicep (deploy once, shared)
Phase 1: BU   → main-network.bicep
Phase 2: BU   → main-aiservices-custom.bicep (needs Phase 1 outputs)
Phase 3: BU   → main-genaiapp.bicep (needs Phase 1 + Phase 4 outputs)
```

Phase 3 auto-assigns AcrPull on the hub ACR — no hub redeploy needed.

---

## AI Foundry Configuration

- **Setup Mode:** Standard Setup with BYO Virtual Network
- **1 AI Foundry Account per BU** — dedicated backing services per BU
- **1 AI Foundry Project per use case** — own managed identity, connections, capability host
- **No model deployments inside Foundry** — models from Core42 Compass via APIM
- **Foundry backing services (per BU):** Key Vault, Storage (ABAC per project), Cosmos DB (3 containers per project), AI Search (indexes per project)

### Agent Subnet
- Delegated to Microsoft.App/environments
- /24 recommended by Microsoft (256 IPs)
- Cannot be shared between Foundry resources

---

## Multi-Use-Case Split Within a BU

| Resource | Shared or Per UC | How Split |
|----------|-----------------|-----------|
| VNet, Subnets, PEs | Shared per BU | All UCs share |
| ACR | Shared (1 for all BUs) | Repo-scoped per BU/UC (csd/uc001/*) |
| AI Foundry Account | Shared per BU | 1 account, N projects |
| AI Foundry Project | Per use case | Own identity, connections, capability host |
| Container Apps Env | Shared per BU | 1 env, N apps |
| Container App | Per use case | Own identity, ingress, scaling |
| Foundry Storage | Shared (1 per BU) | ABAC per project (workspaceId prefix) |
| Foundry Cosmos DB | Shared (1 per BU) | 3 containers auto-created per project |
| Foundry AI Search | Shared (1 per BU) | Indexes per project at runtime |
| App Storage | Shared (1 per BU) | ABAC per UC prefix |
| App Key Vault | Shared (1 per BU) | RBAC per app identity |

---

## Networking

- **Per-BU VNet** (`192.168.0.0/22`) with 3 subnets: `snet-pe` (/25), `snet-foundry-agents` (/24), `snet-container-apps` (/24)
- **Hub VNet** (`10.0.0.0/22`, production only): `snet-pe` (/25), `snet-apim` (/24)
- **8 Private DNS zones:** cognitiveservices, openai, services.ai, search, documents, blob, vaultcore, azurecr.io
- **NSGs:** deny-all-inbound default per subnet; APIM subnet has mgmt port 3443, LB 6390, VNet 443
- **Forced tunneling:** UDR → platform Firewall (not deployed in IaC — managed by platform team)
- **No public endpoints** on any resource (Azure Policy enforced)
- **VNet peering** (production): hub ↔ each BU spoke, DNS zones linked to all spoke VNets

---

## RBAC Model

| Actor | Scope | Role |
|-------|-------|------|
| Platform Team | Each BU subscription | Owner |
| Vendor A | rg-aiservices + rg-genaiapp in CSD/CRS/COM/MKT | Contributor |
| Vendor A | rg-network in CSD/CRS/COM/MKT | Reader |
| Vendor B | rg-aiservices + rg-genaiapp in CTE/CCS/PROC/FIN | Contributor |
| Vendor C | rg-aiservices + rg-genaiapp in CDO | Contributor |
| BU Lead | Their BU subscription | Reader |
| Other vendors | Other BU subs | No access (subscription boundary) |
| Security/GRC | Management Group | Policy Admin |

---

## Problems Solved During Implementation

| Problem | Cause | Solution |
|---------|-------|---------|
| AVM AI Foundry pattern blocked by CPX policies | `deploymentScripts` creates temp ACI + Storage — blocked by zone-resilient/MCSB v2 | Created 4 custom modules in `modules/custom-ai-foundry/` — raw Bicep, no scripts |
| Cosmos DB CMK not supported by AVM | AVM Cosmos v0.18.0 doesn't support `customerManagedKey` | Created raw Bicep resource in `modules/cosmos-db-account.bicep` |
| CMK cross-tenant error on AI Account | Cosmos app registration tried to access KV | Switched KV to RBAC mode, removed access policies |
| Storage CMK auth failure | KV was using access policies, not RBAC | Set `enableRbacAuthorization: true` on all KVs |
| AI Account CMK race condition | KV role not propagated before CMK update | Separated KV role assignment into own module with `dependsOn` |
| ACR CMK can't be added retroactively | Azure limitation | Must be set at creation time — deleted and recreated ACR with CMK |
| ACR soft delete incompatible with zone redundancy | Azure limitation | Disabled soft delete on ACR, kept zone redundancy (better tradeoff) |
| Hub redeploy needed per BU for AcrPull | Role assignments on hub template grew with each BU | Moved AcrPull to BU template via `modules/acr-pull-role.bicep` (cross-RG) |
| UAE North Cosmos zone redundancy | May not have AZ capacity | Parameterized — set `isZoneRedundant: false` if needed |

---

## What's Deferred / Blocked

| Item | Blocker | Template Ready |
|------|---------|---------------|
| APIM AI Gateway (Premium) | Cost approval (~$2,800/mo) + Compass backend URL | Yes — `deployApim = true` toggle in both hub templates |
| Core42 Compass PE | Core42 must provide Private Link Service resource ID | Yes — `deployCompassPe = true` + `compassPlsId` param |
| App Gateway + WAF | Design not finalized (multi-site routing per BU) | Not started |
| CI/CD pipeline | Waiting for CPX to confirm pipeline tooling (ADO / GitHub Actions) | Not started |
| PROD subscriptions | Depends on Phase 1-3 validation in DEV | Not started |
| AI Search local auth disable | Agent Service may require API key auth — needs testing | Parameterizable |

---

## Cost Estimate (UAE North, DEV Foundation)

| Scope | Monthly |
|-------|---------|
| AI Hub (ACR Premium + Hub KV + [APIM when enabled]) | ~$3,327 (ACR only: ~$55) |
| 1 BU Subscription (foundation, no traffic) | ~$410 |
| 9 BU Subscriptions | ~$3,690 |
| **DEV Total** | **~$7,017** |
| **DEV + PROD Total** | **~$15,000** |

Top per-BU costs: AI Search S1 ($274), Cosmos Serverless (~$50), PEs (~$56)

> Savings vs per-BU ACR: **~$440/mo** (1 shared ACR vs 9 individual)

---

## LLM Data Flow

```
User → App Gateway (cpx-ai-hub, multi-site: csd.cpx.ai)
  → PE to BU spoke → Frontend (rg-{bu}-genaiapp)
    → Orchestrator (rg-{bu}-genaiapp)
      → reads App KV/Storage via Managed ID (rg-{bu}-genaiapp)
      → calls AI Foundry Agent (rg-{bu}-aiservices)
        → Agent reads Foundry Cosmos/Storage/Search via Project MI (rg-{bu}-aiservices)
      → sends LLM request to PE APIM (rg-{bu}-network)
        → VNet Peering → Hub APIM ws-csd (cpx-ai-hub)
          → PE Compass → Core42 Compass APIs (Private Link)
            → Response returns same path
```

All traffic stays private. No public internet.

---

## Rollout Plan

| Phase | Scope | Status |
|-------|-------|--------|
| Phase 0 | cpx-ai-hub: ACR deployed, APIM + Compass deferred | **Partial** |
| Phase 1 | cpx-dev-csd: 4 RGs deployed in sandbox (swedencentral) | **Complete** |
| Phase 2 | Remaining Vendor A BU subs (CRS, COM, MKT) | Not started |
| Phase 3 | Vendor B + C BU subs (CTE, CCS, PROC, FIN, CDO) | Not started |
| Phase 4 | PROD subs + stricter policies + CI/CD | Not started |

**CPX tenant:** Custom modules shared with CPX infra team. Awaiting feedback on deployment in UAE North with their policies.

---

## References

- [Foundry Agent Environment Setup](https://learn.microsoft.com/azure/foundry/agents/environment-setup)
- [Standard Agent Setup](https://learn.microsoft.com/azure/foundry/agents/concepts/standard-agent-setup)
- [Virtual Networks for Foundry](https://learn.microsoft.com/azure/foundry/agents/how-to/virtual-networks)
- [AI Gateway Integration](https://learn.microsoft.com/azure/foundry/agents/how-to/ai-gateway)
- [AI Workload Landing Zone](https://learn.microsoft.com/azure/architecture/ai-ml/architecture/ai-workload-landing-zone)
- [GitHub Repo](https://github.com/hamza-roujdami/cpx-ai-lz)
