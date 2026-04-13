# CPX Agentic AI Landing Zone

A **production-grade Azure AI Landing Zone** for CPX — deploying Agentic AI workloads across 9 Business Units using **Microsoft Foundry**, **Centralized APIM AI Gateway**, and **Core42 Compass LLMs**.

One subscription per BU. Three resource groups per subscription. Fully private. Vendor-safe.

---

## Architecture Overview

Based on Microsoft's [Application landing zone for a generative AI workload](https://learn.microsoft.com/azure/architecture/ai-ml/architecture/ai-workload-landing-zone) pattern, adapted for CPX's multi-BU, multi-vendor structure.

**Example: CSD Business Unit (DEV)**

```
┌──────────────────────────────────────────────────────────────────────────────────┐
│  cpx-ai-hub (Centralized AI Hub)                                                 │
│                                                                                  │
│  APIM AI Gateway (Premium)     App Gateway + WAF    ACR (Premium)                │
│  ┌──────────────────────────┐  ┌────────────────┐  ┌──────────────┐              │
│  │ ws-csd │ ws-crs │ ws-com │  │ Multi-site     │  │ Shared       │              │
│  │ ws-mkt │ ws-cte │ ws-ccs │  │ routing per BU │  │ repo-scoped  │              │
│  │ ws-proc│ ws-fin │ ws-cdo │  │ csd.cpx.ai ... │  │ per BU/UC    │              │
│  └──────────────────────────┘  └────────────────┘  └──────────────┘              │
│                                                                                  │
│  PE to Core42 Compass                                                            │
│  ┌──────────────────┐                                                            │
│  │ PE Compass       │                                                            │
│  │ (Private Link)   │                                                            │
│  └──────────────────┘                                                            │
└──────────────────────────────────────────────────────────────────────────────────┘
         │ (VNet Peering)
         ▼
┌──────────────────────────────────────────────────────────────────────────────────┐
│  cpx-dev-csd (CSD BU Subscription)                                               │
│  Platform Team: Owner │ Vendor A: per-RG access                                  │
│                                                                                  │
│  ┌────────────────────────────────────────────────────────────────────────────┐   │
│  │  rg-csd-network-dev-uaen-001 │ Vendor: Reader │ Lock: CanNotDelete       │   │
│  │                                                                            │   │
│  │  VNet (spoke, DNS provided by Hub)                                         │   │
│  │  ┌──────────────────┬───────────────┬──────────────────────────────────────┐│   │
│  │  │ snet-pe          │ snet-         │ snet-foundry-agents                  ││   │
│  │  │                  │ container-apps│                                      ││   │
│  │  │ PE: APIM, ACR,  │ Container App │ AI Foundry Agent Runtime             ││   │
│  │  │ Foundry, Storage,│ Environment   │ (delegated Microsoft.App)            ││   │
│  │  │ KV, Cosmos,      │               │                                      ││   │
│  │  │ Search           │               │                                      ││   │
│  │  └──────────────────┴───────────────┴──────────────────────────────────────┘│   │
│  │                                                                            │   │
│  │  NSGs │ UDR → Platform Firewall │ Log Analytics │ App Insights             │   │
│  └────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│  ┌───────────────────────────────────────┐  ┌────────────────────────────────┐   │
│  │  rg-csd-aiservices-dev-uaen-001     │  │  rg-csd-genaiapp-dev-uaen-001│   │
│  │  Vendor: Contributor │ Locks on data  │  │  Vendor: Contributor │ Locks  │   │
│  │                                       │  │                                │   │
│  │  ┌── AI Foundry Agent Service ─────┐  │  │  ┌── Container Apps ────────┐  │   │
│  │  │  AI Foundry Account (CSD)       │  │  │  │  Container Apps Env      │  │   │
│  │  │  ├── proj-uc001                 │  │  │  │  ├── uc001-frontend      │  │   │
│  │  │  ├── proj-uc002                 │  │  │  │  ├── uc001-orchestrator  │  │   │
│  │  │  ├── proj-ucN                   │  │  │  │  ├── uc002-frontend      │  │   │
│  │  │  │   ├── Connections            │  │  │  │  ├── uc002-orchestrator  │  │   │
│  │  │  │   └── Foundry Agent Service  │  │  │  │  └── ucN apps            │  │   │
│  │  │  Managed IDs (per project)      │  │  │  │  Managed IDs (per app)   │  │   │
│  │  └─────────────────────────────────┘  │  │  └──────────────────────────┘  │   │
│  │                                       │  │                                │   │
│  │  ┌── Foundry Data (🔒 locked) ─────┐  │  │  ┌── App Data (🔒 locked) ──┐  │   │
│  │  │  Storage (ABAC per project)     │  │  │  │  App KV (per app policy) │  │   │
│  │  │  Cosmos DB (3 cont/project)     │  │  │  │  App Storage (ABAC/UC)   │  │   │
│  │  │  AI Search (indexes/project)    │  │  │  │  App Cosmos (db per UC)  │  │   │
│  │  │  Key Vault                      │  │  │  └──────────────────────────┘  │   │
│  │  └─────────────────────────────────┘  │  │                                │   │
│  └───────────────────────────────────────┘  └────────────────────────────────┘   │
│                                                                                  │
│  Role Assignments │ Policy Assignments │ Tags │ Defender for Cloud               │
└──────────────────────────────────────────────────────────────────────────────────┘

Existing Platform Landing Zone (not in scope):
Firewall │ Bastion │ DNS Zones │ ExpressRoute │ Central Log Analytics │ Defender
```

---

## Subscription Model

**19 subscriptions total:** 1 AI Hub + 9 DEV + 9 PROD

| Subscription | Purpose | Owner |
|---|---|---|
| **cpx-ai-hub** | Centralized APIM AI Gateway + PE to Core42 Compass | Platform Team |
| **cpx-dev-csd** | CSD BU DEV (Vendor A) | CPX Platform Team |
| **cpx-dev-crs** | CRS BU DEV (Vendor A) | CPX Platform Team |
| **cpx-dev-com** | COM BU DEV (Vendor A) | CPX Platform Team |
| **cpx-dev-mkt** | MKT BU DEV (Vendor A) | CPX Platform Team |
| **cpx-dev-cte** | CTE BU DEV (Vendor B) | CPX Platform Team |
| **cpx-dev-ccs** | CCS BU DEV (Vendor B) | CPX Platform Team |
| **cpx-dev-proc** | PROC BU DEV (Vendor B) | CPX Platform Team |
| **cpx-dev-fin** | FIN BU DEV (Vendor B) | CPX Platform Team |
| **cpx-dev-cdo** | CDO BU DEV (Vendor C) | CPX Platform Team |
| *+ 9 PROD* | Same pattern, stricter policies | CPX Platform Team |

### Vendor-to-BU Mapping

| Vendor | Business Units |
|---|---|
| Vendor A | CSD, CRS, COM, MKT |
| Vendor B | CTE, CCS, PROC, FIN |
| Vendor C | CDO |

Each BU has exactly 1 vendor. No overlap. Vendors are external contractors with RBAC access — they don't own subscriptions.

---

## 3 Resource Groups per BU Subscription

**Naming convention:** `rg-{bu}-{function}-{env}-{region}-{instance}`

| Resource Group | Contains | Vendor Access | Protection |
|---|---|---|---|
| **rg-{bu}-network-{env}-uaen-001** | VNet, Subnets, NSGs, UDR, PEs, ACR, Log Analytics, App Insights, App Gateway | **Reader** | RG-level CanNotDelete |
| **rg-{bu}-aiservices-{env}-uaen-001** | AI Foundry Account + N Projects + Agent Service + Capability Hosts + Managed IDs + Foundry KV, Storage, Cosmos DB, AI Search | **Contributor** | Resource-level locks on Account + data stores |
| **rg-{bu}-genaiapp-{env}-uaen-001** | Container Apps Env + N Apps + Managed IDs + App KV, App Storage, App Cosmos DB | **Contributor** | Resource-level locks on data stores |

> **Why 3 RGs?**
> - **2 RGs** doesn't work — vendor needs Contributor on AI Foundry but shouldn't have Contributor on networking
> - **4 RGs** (separate data RG) is over-engineered — creates friction for vendors debugging connectivity
> - **3 RGs** = clean separation: networking (Reader), AI development (Contributor), app deployment (Contributor)

> **Foundry Private Endpoints:** AI Foundry auto-creates PEs in rg-{bu}-aiservices that attach to snet-pe in rg-{bu}-network. This cross-RG PE-to-subnet pattern is supported — requires `subnets/join/action` permission on the target subnet.

---

## What Gets Deployed

### rg-{bu}-network-{env}-uaen-001 — Networking + Monitoring

| Resource | Purpose |
|---|---|
| **Virtual Network** | Spoke VNet with 3 subnets (PE, Agent /24, ACA) |
| **NSGs** | Per-subnet, deny-all-inbound default |
| **Route Table (UDR)** | Forced tunneling → Platform Firewall |
| **Private Endpoints** | PEs for: Hub APIM, Hub ACR, Foundry services, App data services |
| **Log Analytics** | Centralized logging, forwarded to platform Central LAW |
| **Application Insights** | APM for Container Apps |

> **Note:** App Gateway + WAF and ACR are now in cpx-ai-hub (shared). No appgw subnet needed in spoke.

### rg-{bu}-aiservices-{env}-uaen-001 — AI Foundry + Foundry Data

| Resource | Purpose |
|---|---|
| **AI Foundry Account** | 1 per BU — central AI platform |
| **AI Foundry Projects** | 1 per use case — own managed identity, connections, capability host |
| **Agent Service** | Agentic AI runtime per project |
| **Foundry Key Vault** 🔒 | Foundry secrets (including Compass API keys) |
| **Foundry Storage** 🔒 | Foundry data, ABAC-isolated per project (workspaceId prefix) |
| **Foundry Cosmos DB** 🔒 | Agent state, threads — 3 containers auto-created per project |
| **Foundry AI Search** 🔒 | Vector store, indexes per project at runtime |
| **Managed Identities** | SystemAssigned per project |

### rg-{bu}-genaiapp-{env}-uaen-001 — Container Apps + App Data

| Resource | Purpose |
|---|---|
| **Container Apps Env** | 1 per BU — shared compute pool |
| **Container Apps** | 2 per use case: Frontend + Orchestrator (+ MCP, Ingestion optional) |
| **App Key Vault** 🔒 | App secrets, access policies per app identity |
| **App Storage** 🔒 | App data, ABAC per use case prefix |
| **App Cosmos DB** 🔒 | App data, per-use-case database (db-uc001, db-uc002) |
| **Managed Identities** | Per-app identity for data access |

> 🔒 = Resource-level CanNotDelete lock. Vendor has Contributor on the RG but cannot delete these resources.

---

## Centralized APIM AI Hub (cpx-ai-hub)

| Component | Details |
|---|---|
| **APIM AI Gateway** | Premium SKU. 9 workspaces — 1 per BU. Rate limits, JWT validation, token counting. |
| **APIM Workspaces** | ws-csd, ws-crs, ws-com, ws-mkt, ws-cte, ws-ccs, ws-proc, ws-fin, ws-cdo |
| **App Gateway + WAF** | Shared, multi-site routing per BU (csd.cpx.ai, crs.cpx.ai, etc.). OWASP 3.2. |
| **ACR (Premium)** | Shared container registry. Repo-scoped tokens per BU/UC (csd/uc001/*, crs/uc002/*). |
| **PE to Core42 Compass** | Private Endpoint connecting APIM to Core42 Compass APIs via Private Link |

### LLM Data Flow

```
User → App Gateway (cpx-ai-hub, multi-site: csd.cpx.ai)
  → PE to BU spoke → Frontend (rg-{bu}-genaiapp)
    → Orchestrator (rg-{bu}-genaiapp)
      → reads App KV/Cosmos via Managed ID (rg-{bu}-genaiapp)
      → calls AI Foundry Agent (rg-{bu}-aiservices)
        → Agent reads Foundry Cosmos/Storage/Search via Managed ID (rg-{bu}-aiservices)
      → sends LLM request to PE APIM (rg-{bu}-network)
        → VNet Peering → Hub APIM ws-csd (cpx-ai-hub)
          → PE Compass → Core42 Compass APIs (Private Link)
            → Response returns same path
```

All traffic stays private. No public internet.

---

## RBAC Model

| Actor | Scope | Role |
|---|---|---|
| Platform Team | Each BU subscription | Owner |
| Vendor A | rg-{bu}-aiservices + rg-{bu}-genaiapp in CSD/CRS/COM/MKT | Contributor |
| Vendor A | rg-{bu}-network in CSD/CRS/COM/MKT | Reader |
| Vendor B | rg-{bu}-aiservices + rg-{bu}-genaiapp in CTE/CCS/PROC/FIN | Contributor |
| Vendor C | rg-{bu}-aiservices + rg-{bu}-genaiapp in CDO | Contributor |
| BU Lead (CSD) | cpx-dev-csd subscription | Reader |
| Other vendors | Other BU subs | No access (subscription boundary) |
| Security/GRC | Management Group | Policy Admin |
| App Managed IDs | Data resources in rg-{bu}-aiservices + rg-{bu}-genaiapp | Scoped roles (Cosmos SQL, Storage ABAC, KV policy) |

---

## Security Controls

| Category | Controls |
|---|---|
| **Network** | Private Endpoints, no public access, NSGs, forced tunneling (UDR → Firewall), WAF, no spoke-to-spoke, 7 Private DNS zones |
| **Identity** | Managed Identities (per project + per app), zero shared keys, PIM, Conditional Access, deny broad RBAC via Policy |
| **Data** | Encryption at rest (AES-256, CMK option), TLS 1.2+ in transit, Storage ABAC, Cosmos SQL roles, KV access policies, no data exfiltration |
| **Secrets** | Key Vault (soft delete + purge protection), no hardcoded creds (Policy enforced), key rotation |
| **Threats** | Defender for AI, Storage, Key Vault, Cosmos DB, Resource Manager |
| **Logging** | Activity Log, diagnostic settings (Policy: deploy-if-not-exists), central LAW forwarding, APIM logging, 30d DEV / 90-365d PROD |
| **Compliance** | Azure Policy (deny/deploy/audit), resource locks, tagging enforcement, deny assignments, Defender compliance dashboard |

---

## Cost Estimate (UAE North, DEV Foundation)

| Scope | Monthly |
|---|---|
| AI Hub (APIM Premium + App Gateway + ACR + PE Compass) | ~$3,327 |
| 1 BU Subscription (foundation, no traffic) | ~$410 |
| 9 BU Subscriptions | ~$3,690 |
| **DEV Total** | **~$7,017** |
| **DEV + PROD Total** | **~$15,000** |

Top per-BU costs: AI Search S1 ($274), Cosmos Serverless (~$50), PEs (~$56)

> Savings vs per-BU App Gateway + ACR: **~$2,016/mo**

---

## Rollout Plan

| Phase | Scope | Timeline |
|---|---|---|
| Phase 0 | cpx-ai-hub: APIM + PE Compass + Core42 coordination | Week 1-2 |
| Phase 1 | cpx-dev-csd: 3 RGs + 1 use case, validate end-to-end | Week 3-4 |
| Phase 2 | Remaining Vendor A BU subs (CRS, COM, MKT) | Week 5-6 |
| Phase 3 | Vendor B + C BU subs (CTE, CCS, PROC, FIN, CDO) | Week 7-10 |
| Phase 4 | PROD subs + stricter policies + CI/CD | Week 11-14 |

---

## Microsoft Foundry Alignment

| Pattern | Reference |
|---|---|
| Environment setup | [Foundry Agent Environment Setup](https://learn.microsoft.com/azure/foundry/agents/environment-setup) |
| Standard agent setup | [Standard Agent Setup](https://learn.microsoft.com/azure/foundry/agents/concepts/standard-agent-setup) |
| Private networking | [Virtual Networks for Foundry](https://learn.microsoft.com/azure/foundry/agents/how-to/virtual-networks) |
| AI Gateway (APIM) | [AI Gateway Integration](https://learn.microsoft.com/azure/foundry/agents/how-to/ai-gateway) |
| Reference architecture | [AI Workload Landing Zone](https://learn.microsoft.com/azure/architecture/ai-ml/architecture/ai-workload-landing-zone) |

---

## Customer-Managed Keys (CMK) — Encryption at Rest

This landing zone supports **Customer-Managed Keys (CMK)** to give CPX full control over encryption keys used to protect data at rest. Instead of relying on Microsoft-managed (platform) keys, CPX stores and manages RSA keys in their own Azure Key Vault (with soft-delete and purge protection enabled). This enables crypto-shred capability (revoke the key to make all data permanently inaccessible), full audit trail via Key Vault diagnostic logs, compliance with UAE data sovereignty and NESA requirements, and CPX-controlled key rotation schedules.

### CMK Coverage per Service

| Service | What CMK Encrypts | Tier Requirement | Notes |
|---|---|---|---|
| **AI Foundry Account** | AI platform internal data — cached model artifacts, prompt/completion logs, fine-tuning job data, Agent Service internal state | Any (S0) | Configured via `encryption.keySource: Microsoft.KeyVault` on the Cognitive Services account. The AI Foundry Account's system-assigned managed identity requires `wrapKey` and `unwrapKey` permissions on the Key Vault key. |
| **Azure Cosmos DB** | All data stored in the account — documents, indexes, backups, attachments. Only metadata (account/database/container names, stored procedure names, indexing policy paths, partition key values) remains unencrypted. | Any | CMK adds a **second layer** of encryption on top of PMK (double encryption). Increases RU consumption: +5% reads, +6% writes, +15% queries. CMK can be configured on both new and existing accounts. Cosmos DB's first-party identity (`a232010e-820c-4083-83bb-3ace5fc29d0b`) requires `Get`, `wrapKey`, `unwrapKey` permissions on the Key Vault. |
| **Azure AI Search** | Individual objects — indexes, synonym lists, indexers, data sources, skillsets, and vectorizers (connection strings, keys, user inputs, references to external resources). | **Basic or higher** (any billable tier) | CMK is applied **per object** at creation time (cannot retroactively encrypt existing objects). Service-wide enforcement is available via `encryptionWithCmk.enforcement: Enabled` on the Search service resource. Search service's system-assigned managed identity requires the `Key Vault Crypto Service Encryption User` role on the Key Vault. |
| **Storage Account** | All blob, file, table, and queue data, plus Azure Data Lake Storage. | Any (including Standard) | Configured via `encryption.keySource: Microsoft.Keyvault` with `keyVaultProperties` on the storage account. Storage uses the account's system-assigned managed identity to access the key. Supports both Key Vault and Managed HSM. |
| **Key Vault** | N/A — Key Vault itself is the key store | N/A | Key Vault data is encrypted at rest using HSM-backed keys managed by Microsoft. CMK does not apply to Key Vault itself. |

### Current Implementation

In this landing zone, CMK is currently configured on the **AI Foundry Account** only (via the `cmk-encryption.bicep` module). The module creates an RSA-2048 key in the Foundry Key Vault, grants access policies to the AI Foundry managed identity and the Cosmos DB first-party application, and updates the AI Foundry Account with `keySource: Microsoft.KeyVault`. Storage, Cosmos DB, and AI Search use platform-managed keys (PMK) by default. For production deployments where CPX policy requires CMK on all data stores, CMK should be enabled on each resource individually. Note that Cosmos DB CMK can now be added to existing accounts, and AI Search CMK must be configured per object at creation time.

### References

- [AI Search — Configure CMK](https://learn.microsoft.com/azure/search/search-security-manage-encryption-keys)
- [Cosmos DB — Configure CMK](https://learn.microsoft.com/azure/cosmos-db/how-to-setup-customer-managed-keys)
- [Storage Account — CMK with Key Vault](https://learn.microsoft.com/azure/storage/common/customer-managed-keys-configure-key-vault)
- [AI Services — CMK](https://learn.microsoft.com/azure/ai-services/openai/encrypt-data-at-rest)

---

## Related Documents

| Document | Description |
|---|---|
| [cpx-context.md](cpx-context.md) | Full project context — decisions, alternatives, open items |
| [architecture-diagrams/cpx-architecture.png](architecture-diagrams/cpx-architecture.png) | Architecture diagram with Azure icons |
| [architecture-diagrams/CPX-AI-Landing-Zone-Design.docx](architecture-diagrams/CPX-AI-Landing-Zone-Design.docx) | Design document (Part 1: Foundry Foundation + Part 2: CPX Architecture) |
| [architecture-diagrams/CPX-Security-Controls-and-BOM.docx](architecture-diagrams/CPX-Security-Controls-and-BOM.docx) | Security controls + Resource BOM + Cost estimate |
