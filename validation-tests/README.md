# AI Landing Zone — Validation Tests

Four validation layers to verify the landing zone works end-to-end.

## Test layers

| # | Folder | What | Where to run | Prerequisites |
|---|--------|------|-------------|---------------|
| 1 | `1-infra-check/` | Resources, CMK, PEs, RBAC, public access, KV, Foundry | Laptop / Cloud Shell | Infra deployed |
| 2 | `2-network-check/` | VNet peering, DNS zone links, ACR pull chain | Laptop / Cloud Shell | Network configured |
| 3 | `3-dataplane-app/` | Service connectivity from inside VNet (KV, Storage, Cosmos, Search, Foundry) | Deploy to ACA | Network confirmed |
| 4 | `4-agent-test/` | Foundry Agent + Compass end-to-end | Inside VNet | Compass connected |

## Quick start

### 1. Infrastructure check (run first)

```bash
cd validation-tests/1-infra-check
./check-infra.sh csd dev swc cpx 002
```

Checks 30+ items: resource groups, CMK on all stores, PEs, public access disabled, KV purge protection, Foundry connections, capability hosts, RBAC.

### 2. Network check (after platform team configures network)

```bash
cd validation-tests/2-network-check
./check-network.sh csd dev swc cpx 002
```

Checks: VNet peering, DNS zone links, ACR DNS records, AcrPull role, image pull proof.

### 3. Data plane app (deploy to ACA for inside-VNet testing)

```bash
cd validation-tests/3-dataplane-app
./deploy.sh
```

See [3-dataplane-app/README.md](3-dataplane-app/README.md) for details. Tests KV, Storage, Cosmos, Search, Foundry, Compass connectivity from inside the VNet.

### 4. Agent test (after Compass)

Future — see [4-agent-test/README.md](4-agent-test/README.md).

## Parameters

Both scripts take the same 5 arguments:

| Param | Description | Example |
|-------|-------------|---------|
| `bu` | Business unit code | `csd` |
| `env` | Environment | `dev` |
| `region_abbr` | Region abbreviation | `swc` (swedencentral), `uaen` (uaenorth) |
| `org` | Organization prefix | `cpx` |
| `hub_instance` | Hub instance number | `002` |
