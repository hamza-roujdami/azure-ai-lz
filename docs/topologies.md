# Topologies

One deployment targets one subscription and one environment. Run it again with a different
`environmentName`, against a different subscription, for each environment you need.

## Resource groups

Four groups when everything is deployed.

| Resource group | Contents | Created when |
| --- | --- | --- |
| `rg-ai-platform-<env>-network` | VNet, subnets, NSG, private DNS zones | always |
| `rg-ai-spoke-<env>-ai` | Foundry account and project, Cosmos DB, AI Search, Storage, Key Vault | `deploySpoke` |
| `rg-ai-spoke-<env>-app` | Container Apps, registry, App Configuration, identity, observability | `deploySpoke` and `deployAppLayer` |
| `rg-ai-hub-<env>` | API Management, hub Foundry with the model deployments, observability | `deployHub` |

The split between `-ai` and `-app` is deliberate. Data services are stateful and long-lived;
application compute is redeployed constantly. Keeping them apart means an application rollout cannot
affect the data plane, and the two can carry different RBAC and delete locks.

The hub keeps API Management and the model Foundry together. Both are platform-owned, deployed at the
same time, and change on a similar cadence, so a split would add bookkeeping without reducing risk.

## Subscription mapping

The simplest arrangement is one subscription per environment holding both pillars:

```
platform-dev   →  rg-ai-platform-dev-network,  rg-ai-spoke-dev-ai,  rg-ai-spoke-dev-app,  rg-ai-hub-dev
platform-uat   →  rg-ai-platform-uat-network,  rg-ai-spoke-uat-ai,  rg-ai-spoke-uat-app,  rg-ai-hub-uat
platform-prod  →  rg-ai-platform-prod-network, rg-ai-spoke-prod-ai, rg-ai-spoke-prod-app, rg-ai-hub-prod
```

Production stays isolated from non-production at the subscription boundary, which is usually the
easiest boundary to defend in a review.

## Separating the hub from the spokes

If a platform team owns the gateway and models while product teams own their own workloads, split the
deployment:

- In the platform subscription, deploy with `deploySpoke = false`. You get the network and the hub.
- In each workload subscription, deploy with `deployHub = false`. You get the network and a spoke.
- Peer the workload networks to the platform network and point the spokes at the shared gateway.

Note that each deployment creates its own virtual network. If you want spokes to reuse a central
network instead of creating their own, that requires changes to `main.bicep` to accept existing
subnet and DNS zone resource IDs.
