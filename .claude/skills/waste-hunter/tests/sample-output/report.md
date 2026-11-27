# Azure waste report

## Estimated monthly savings: **38,364.62 CAD + 11,925.15 USD**

High confidence: **32,105.42 CAD + 2,662.65 USD**. The rest needs a check before acting (see each finding's confidence and reason).

65 finding(s) across 39 waste type(s). 3 resource(s) excluded (3 by the `waste-hunter:ignore=true` tag, 0 by an exclusions file (none used); listed in `excluded.csv`).

Generated 2026-11-27 05:45 UTC. Scope: tenant(s) 00000000-0000-0000-0000-00000000demo. **Read-only scan: nothing in Azure was changed.**

> **SYNTHETIC DEMO DATA** loaded from `fixtures`. No Azure calls were made and these resources are not real.

| Waste type | Findings | Est. monthly | High | Medium | Low | Excluded |
|---|---:|---:|---:|---:|---:|---:|
| Unattached managed disks | 3 | 135.18 USD + 72.17 CAD | 1 | 0 | 2 | 1 |
| Orphaned NICs (no VM attached) | 2 | 0.00 CAD | 1 | 1 | 0 | 0 |
| Unassociated public IPs | 3 | 10.22 CAD | 2 | 0 | 1 | 0 |
| Empty App Service plans | 3 | 248.20 USD + 102.49 CAD | 2 | 0 | 1 | 0 |
| VMs stopped but not deallocated | 2 | 276.48 USD + 103.51 CAD | 2 | 0 | 0 | 0 |
| Disk snapshots older than 90 days | 2 | 88.57 CAD | 1 | 0 | 1 | 0 |
| Idle Container Apps with always-on replicas | 2 | 76.41 CAD | 1 | 1 | 0 | 0 |
| Log Analytics: paid retention or unqueried data | 1 | cost unknown | 0 | 1 | 0 | 0 |
| Idle storage accounts | 2 | 16.63 CAD | 1 | 0 | 1 | 1 |
| Hot-tier blob data nobody reads | 1 | 27.65 CAD | 0 | 1 | 0 | 0 |
| Idle container registries | 2 | 147.39 CAD | 1 | 0 | 1 | 0 |
| Premium container registries not using Premium | 1 | 42.11 CAD | 0 | 1 | 0 | 0 |
| Idle Azure OpenAI deployments that bill hourly | 2 | 15,370.51 CAD + 1,241.00 USD | 2 | 0 | 0 | 0 |
| Load balancers with no backends | 2 | 25.62 CAD | 1 | 0 | 1 | 0 |
| Application Gateways with no backends | 1 | 509.10 CAD | 1 | 0 | 0 | 0 |
| Idle NAT, VPN and ExpressRoute gateways and circuits | 3 | 548.23 CAD + 1 unknown | 2 | 1 | 0 | 0 |
| Idle Bastion hosts | 1 | 297.18 CAD | 1 | 0 | 0 | 0 |
| Idle SQL databases | 1 | 147.17 USD | 1 | 0 | 0 | 0 |
| Premium disks on long-deallocated VMs | 1 | 81.94 CAD | 1 | 0 | 0 | 0 |
| Empty resource groups | 1 | 0.00 CAD | 0 | 1 | 0 | 0 |
| DDoS protection plans protecting nothing | 1 | 4,132.02 CAD | 1 | 0 | 0 | 0 |
| App Service plans whose apps are all stopped | 2 | 322.81 CAD | 1 | 0 | 1 | 0 |
| Backups of deleted VMs | 1 | cost unknown | 0 | 0 | 1 | 0 |
| Idle Azure Firewalls | 2 | 3,074.25 CAD | 1 | 1 | 0 | 0 |
| Over-provisioned Cosmos DB throughput | 2 | 359.74 CAD | 1 | 1 | 0 | 0 |
| Idle Fabric, Synapse and Data Explorer compute | 3 | 11,368.22 CAD + 8,409.60 USD | 1 | 1 | 1 | 0 |
| Idle Redis caches | 1 | 141.40 CAD | 1 | 0 | 0 | 0 |
| Idle Service Bus and Event Hubs namespaces | 2 | 965.86 CAD | 2 | 0 | 0 | 0 |
| Idle API Management instances | 1 | 67.45 CAD | 1 | 0 | 0 | 0 |
| ML compute clusters that never scale to zero | 2 | 438.00 USD | 1 | 1 | 0 | 0 |
| Private endpoints with no working connection | 2 | 14.60 USD | 1 | 1 | 0 | 0 |
| Unused public IP prefixes | 1 | 98.11 CAD | 0 | 1 | 0 | 0 |
| Front Door and Traffic Manager profiles with no endpoints | 2 | 35.00 USD | 1 | 0 | 1 | 0 |
| Non-production VMs with no shutdown schedule | 1 | 126.47 CAD | 0 | 1 | 0 | 0 |
| Underused reservations | 1 | cost unknown | 1 | 0 | 0 | 0 |
| Azure Hybrid Benefit not applied (if you own licences) | 2 | 587.50 USD + 188.56 CAD | 0 | 0 | 2 | 0 |
| Geo-redundant storage in non-production | 1 | 15.60 USD | 0 | 1 | 0 | 0 |
| Oversized VMs (CPU nearly idle) | 1 | 280.32 USD | 1 | 0 | 0 | 0 |
| Other Azure Advisor cost recommendations | 1 | 96.50 USD | 0 | 1 | 0 | 1 |

**Cost sources:** *billed* is the actual 30-day cost from the Consumption API, scaled to 30 days. *advisor* is Azure Advisor's monthly savings estimate. *estimated* is pay-as-you-go list prices for each resource's own region, in CAD, from the Azure Retail Prices API, with `scripts/pricing.json` (US East, USD) as the fallback. Snapshot estimates are upper bounds. Advisor recommendations that match a finding above are merged into it and not counted twice.

**† Reservations and savings plans:** 16 estimated cost(s) are for resources a reservation or savings plan can cover. If one covers them, the commitment is already paid, so the bill drops by less than shown (the unused commitment shifts elsewhere or is wasted). Check Reservations in the portal before counting these savings. Billed costs already reflect commitments.

**Ranking across currencies:** amounts are shown in their original currency, but findings are ranked after converting them to CAD at the rate implied by Microsoft's price list (1 USD = 1.4037 CAD).

## Quick wins: 13,439.23 CAD + 851.68 USD/month

High-confidence findings whose fix is reversible (deallocate, scale to zero, add a schedule) or removes something nothing depends on. Start here. Data stores, backups and anything that may be a dependency are never on this list.

| Resource | Waste type | Est. monthly | Suggested action (not executed) |
|---|---|---:|---|
| [syn-ws/dw-legacy](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-data/providers/Microsoft.Synapse/workspaces/syn-ws/sqlPools/dw-legacy) | Idle Fabric, Synapse and Data Explorer compute | 7,736.76 CAD | Pause the pool: storage keeps billing, compute stops, and it resumes in minutes. Delete it if nothing needs the data. |
| [ddos-legacy-plan](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-net/providers/Microsoft.Network/ddosProtectionPlans/ddos-legacy-plan) | DDoS protection plans protecting nothing | 4,132.02 CAD | Confirm with the owner (netops@example.com) that no virtual network is about to be linked, then delete the plan. Free DDoS infrastructure protection stays on. If only a few public IPs need DDoS protection, IP Protection per IP is usually cheaper. |
| [agw-legacy-portal](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-web/providers/Microsoft.Network/applicationGateways/agw-legacy-portal) | Application Gateways with no backends | 509.10 CAD | Stop it to end the hourly charge while keeping its configuration (start it again when backends return), or delete it if it has been retired. |
| [mlw-research/cpu-cluster](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-ml/providers/Microsoft.MachineLearningServices/workspaces/mlw-research/computes/cpu-cluster) | ML compute clusters that never scale to zero | 292.00 USD | Set the cluster's minimum node count to 0 and a short idle time before scale-down (for example 120 seconds), so nodes are released between jobs. The first job after idle then waits a few minutes for a node. |
| [vm-build-agent-02](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-build/providers/Microsoft.Compute/virtualMachines/vm-build-agent-02) | VMs stopped but not deallocated | 276.48 USD | Deallocate it to stop compute billing (its disks keep billing), or delete it if it's no longer needed. Deallocating releases dynamic public IPs. |
| [asp-legacy-api](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-api/providers/Microsoft.Web/serverFarms/asp-legacy-api) | Empty App Service plans | 248.20 USD | Delete the plan if no deployment is planned. If it's being kept for upcoming work, scale it down to Free or B1 until needed. |
| [asp-intranet-old](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-intranet/providers/Microsoft.Web/serverFarms/asp-intranet-old) | App Service plans whose apps are all stopped | 322.81 CAD | Confirm with the owner (web@example.com) whether the stopped apps will run again. If they're retired, delete them and then the plan. If they're parked, scale the plan down to B1 or Free while they're stopped (stopping an app doesn't reduce the bill). |
| [bas-dev](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-net-dev/providers/Microsoft.Network/bastionHosts/bas-dev) | Idle Bastion hosts | 297.18 CAD | Delete it and re-create it when needed (it takes about 10 minutes), or move dev/test use to the free Developer SKU. |
| [vm-win-jumpbox](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-ops/providers/Microsoft.Compute/virtualMachines/vm-win-jumpbox) | VMs stopped but not deallocated | 103.51 CAD | Deallocate it to stop compute billing (its disks keep billing), or delete it if it's no longer needed. Deallocating releases dynamic public IPs. |
| [asp-reports-weu](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-reports/providers/Microsoft.Web/serverFarms/asp-reports-weu) | Empty App Service plans | 102.49 CAD | Delete the plan if no deployment is planned. If it's being kept for upcoming work, scale it down to Free or B1 until needed. |
| [cosmos-dev-idle](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-api/providers/Microsoft.DocumentDB/databaseAccounts/cosmos-dev-idle) | Over-provisioned Cosmos DB throughput | 98.11 CAD | Lower the provisioned throughput (or the autoscale maximum) to about 400 RU/s in total, then watch for throttled (429) requests. If traffic stays this low, serverless may cost less still. |
| [ca-orders-legacy](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-orders/providers/Microsoft.App/containerApps/ca-orders-legacy) | Idle Container Apps with always-on replicas | 65.49 CAD | Set minReplicas to 0 so it scales to zero when idle (the first request after idle then has a cold start), or delete the app if it's no longer needed. |
| [afd-old-site](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-web/providers/Microsoft.Cdn/profiles/afd-old-site) | Front Door and Traffic Manager profiles with no endpoints | 35.00 USD | Confirm with the owner (web@example.com) that no endpoint is about to be added, then delete the profile. Custom domains and WAF policies attached to it go with it. |
| [nat-dev-unused](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-net-dev/providers/Microsoft.Network/natGateways/nat-dev-unused) | Idle NAT, VPN and ExpressRoute gateways and circuits | 46.14 CAD | Delete it, or attach it to the subnets that need outbound access. Release its public IPs if they aren't needed. |
| [lb-old-web](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-web/providers/Microsoft.Network/loadBalancers/lb-old-web) | Load balancers with no backends | 25.62 CAD | Confirm with the owner (web@example.com) that no deployment is about to add backends, then delete it and release its frontend public IPs if they aren't needed. |

## Changes since the last scan

No earlier scan of this scope to compare with, so this report is the baseline. The next scan will show what is new, still open and resolved.

## By owner

From the `owner` tag (or `createdBy`) on the resource, falling back to its resource group's tag. Each owner has a CSV and a short summary (`.md`, ready to paste into an email or chat) in `by-owner/`.

| Owner | Findings | High confidence | Est. monthly | List |
|---|---:|---:|---:|---|
| ml@example.com | 4 | 3 | 15,370.51 CAD + 1,679.00 USD | `by-owner/ml@example.com.csv` |
| bi-team@example.com | 2 | 1 | 8,409.60 USD + 102.49 CAD | `by-owner/bi-team@example.com.csv` |
| data-team@example.com | 4 | 4 | 7,815.81 CAD + 282.35 USD | `by-owner/data-team@example.com.csv` |
| netops@example.com | 5 | 3 | 6,525.54 CAD + 1 unknown | `by-owner/netops@example.com.csv` |
| orders@example.com | 3 | 2 | 1,277.58 CAD | `by-owner/orders@example.com.csv` |
| erp@example.com | 2 | 0 | 587.50 USD + 188.56 CAD | `by-owner/erp@example.com.csv` |
| api-team@example.com | 4 | 3 | 528.52 USD + 193.92 CAD | `by-owner/api-team@example.com.csv` |
| web@example.com <sub>(1 via resource group tag)</sub> | 5 | 5 | 862.64 CAD + 35.00 USD | `by-owner/web@example.com.csv` |
| ci@example.com | 3 | 2 | 276.48 USD + 153.85 CAD | `by-owner/ci@example.com.csv` |
| ops@example.com | 1 | 1 | 103.51 CAD | `by-owner/ops@example.com.csv` |
| legacy-team@example.com <sub>(3 via resource group tag)</sub> | 3 | 2 | 91.46 CAD + 7.30 USD | `by-owner/legacy-team@example.com.csv` |
| platform@example.com | 5 | 3 | 63.29 CAD + 1 unknown | `by-owner/platform@example.com.csv` |
| sandbox@example.com <sub>(6 via resource group tag)</sub> | 6 | 1 | 15.40 CAD | `by-owner/sandbox@example.com.csv` |
| secops@example.com | 1 | 0 | cost unknown | `by-owner/secops@example.com.csv` |
| **no owner tag** | 17 | 5 | 5,600.06 CAD + 119.40 USD + 1 unknown | `by-owner/_no-owner.csv` |

**Costly findings with no owner** (tag these to route them): adx-telemetry (3,631.46 CAD); fw-dev-dnat (1,280.93 CAD); bas-dev (297.18 CAD); redis-session-old (141.40 CAD); demo-prod (96.50 USD); cosmos-dev-idle (98.11 CAD); asrseeddisk-web01-a1b2c3 (58.69 CAD); nat-dev-unused (46.14 CAD); stmediaarchive (27.65 CAD); stdevlogs (15.60 USD).

## Idle Fabric, Synapse and Data Explorer compute: 3 finding(s), 11,368.22 CAD + 8,409.60 USD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [fab-analytics](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-bi/providers/Microsoft.Fabric/capacities/fab-analytics)<br><sub>microsoft.fabric/capacities</sub> | demo-prod<br><sub>rg-bi</sub> | eastus | bi-team@example.com / - / prod | unknown | 8,409.60 USD<br><sub>estimated†</sub> | **low** | Fabric capacity F64 is Active and bills every hour whether or not workloads run. Azure Monitor has no usage metric for Fabric, so usage isn't verified here: check the Fabric Capacity Metrics app | Check the Fabric Capacity Metrics app with the owner (bi-team@example.com). If the capacity is idle outside working hours, pause it then (a schedule or a pipeline can do it); if it's unused, delete it. |
| 2 | [syn-ws/dw-legacy](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-data/providers/Microsoft.Synapse/workspaces/syn-ws/sqlPools/dw-legacy)<br><sub>microsoft.synapse/workspaces/sqlpools</sub> | demo-prod<br><sub>rg-data</sub> | eastus | data-team@example.com / - / prod | age 300d, idle 30d | 7,736.76 CAD<br><sub>estimated†</sub> | **high** | Dedicated SQL pool DW500c is Online with 0 connections and 0 queries in 30 days, but compute bills every hour until it's paused | Pause the pool: storage keeps billing, compute stops, and it resumes in minutes. Delete it if nothing needs the data. |
| 3 | [adx-telemetry](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-telemetry/providers/Microsoft.Kusto/clusters/adx-telemetry)<br><sub>microsoft.kusto/clusters</sub> | demo-dev<br><sub>rg-telemetry</sub> | eastus | - / - / dev | idle 30d | 3,631.46 CAD<br><sub>estimated†</sub> | **medium** | Data Explorer cluster (2 x Standard_E8ads_v5) ingested 5,000 MB but answered 0 queries in 30 days: data goes in and nobody reads it | Stop the cluster (data is kept and it can be started again), or confirm with the resource group owner that nothing reads it and delete it. |

## Idle Azure OpenAI deployments that bill hourly: 2 finding(s), 15,370.51 CAD + 1,241.00 USD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [oai-research/gpt-ptu-eval](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-ml/providers/Microsoft.CognitiveServices/accounts/oai-research/deployments/gpt-ptu-eval)<br><sub>microsoft.cognitiveservices/accounts/deployments</sub> | demo-dev<br><sub>rg-ml</sub> | eastus | ml@example.com / research / dev | age 120d, idle 30d | 15,370.51 CAD<br><sub>estimated†</sub> | **high** | Deployment 'gpt-ptu-eval' (model gpt-4o) bills hourly for 15 PTU of GlobalProvisionedManaged but had 0 requests in 30 days. If a PTU reservation covers it, the commitment is already paid, but the capacity is still unused | Delete the deployment (re-create it when needed). For PTU, also check whether a reservation covers it before you rely on the saving. |
| 2 | [oai-research/gpt-4o-mini-support-ft](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-ml/providers/Microsoft.CognitiveServices/accounts/oai-research/deployments/gpt-4o-mini-support-ft)<br><sub>microsoft.cognitiveservices/accounts/deployments</sub> | demo-dev<br><sub>rg-ml</sub> | eastus | ml@example.com / research / dev | age 90d, idle 30d | 1,241.00 USD<br><sub>estimated†</sub> | **high** | Deployment 'gpt-4o-mini-support-ft' (model gpt-4o-mini-2024-07-18.ft-3f9a2c) bills hourly for fine-tuned model hosting but had 0 requests in 30 days | Delete the deployment (re-create it when needed). For PTU, also check whether a reservation covers it before you rely on the saving. |

## DDoS protection plans protecting nothing: 1 finding(s), 4,132.02 CAD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [ddos-legacy-plan](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-net/providers/Microsoft.Network/ddosProtectionPlans/ddos-legacy-plan)<br><sub>microsoft.network/ddosprotectionplans</sub> | demo-prod<br><sub>rg-net</sub> | eastus | netops@example.com / - / prod | unknown | 4,132.02 CAD<br><sub>estimated</sub> | **high** | DDoS Network Protection plan protects no virtual networks or public IPs, but bills its fixed monthly fee | Confirm with the owner (netops@example.com) that no virtual network is about to be linked, then delete the plan. Free DDoS infrastructure protection stays on. If only a few public IPs need DDoS protection, IP Protection per IP is usually cheaper. |

## Idle Azure Firewalls: 2 finding(s), 3,074.25 CAD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [fw-hub-legacy](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-net/providers/Microsoft.Network/azureFirewalls/fw-hub-legacy)<br><sub>microsoft.network/azurefirewalls</sub> | demo-prod<br><sub>rg-net</sub> | eastus | netops@example.com / - / prod | idle 30d | 1,793.32 CAD<br><sub>estimated</sub> | **high** | 0 application or network rule hits and 0 B processed in 30 days (Premium), but the deployment fee bills every hour | Check route tables (forced tunneling, hub routing) and any planned spokes that send traffic through it. If it is not needed, delete it, or deallocate it to keep its configuration without the hourly fee (Azure PowerShell: $fw.Deallocate(); Set-AzFirewall $fw). |
| 2 | [fw-dev-dnat](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-net-dev/providers/Microsoft.Network/azureFirewalls/fw-dev-dnat)<br><sub>microsoft.network/azurefirewalls</sub> | demo-dev<br><sub>rg-net-dev</sub> | eastus | - / - / dev | idle 30d | 1,280.93 CAD<br><sub>estimated</sub> | **medium** | 0 application or network rule hits and 300.0 MiB processed in 30 days (Standard), but the deployment fee bills every hour. Some traffic still flows (DNAT rules have no hit metric), so check what routes through it first | Check route tables (forced tunneling, hub routing) and any planned spokes that send traffic through it. If it is not needed, delete it, or deallocate it to keep its configuration without the hourly fee (Azure PowerShell: $fw.Deallocate(); Set-AzFirewall $fw). |

## Azure Hybrid Benefit not applied (if you own licences): 2 finding(s), 587.50 USD + 188.56 CAD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [sqlsrv-erp/erp](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-erp/providers/Microsoft.Sql/servers/sqlsrv-erp/databases/erp)<br><sub>microsoft.sql/servers/databases</sub> | demo-prod<br><sub>rg-erp</sub> | eastus | erp@example.com / - / prod | unknown | 587.50 USD<br><sub>estimated</sub> | **low** | SQL GeneralPurpose pays for the SQL Server licence by the hour (LicenseIncluded). This is a saving only if you own eligible licences with Software Assurance or subscriptions | Check with your licensing team whether you own eligible SQL Server licences with Software Assurance that aren't already assigned. If you do, turn on Azure Hybrid Benefit; if you don't, there's nothing to save, so exclude this finding. |
| 2 | [vm-win-app01](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-erp/providers/Microsoft.Compute/virtualMachines/vm-win-app01)<br><sub>microsoft.compute/virtualmachines</sub> | demo-prod<br><sub>rg-erp</sub> | eastus | erp@example.com / - / prod | unknown | 188.56 CAD<br><sub>estimated</sub> | **low** | Windows VM pays for the Windows Server licence by the hour (Azure Hybrid Benefit is off). This is a saving only if you own eligible licences with Software Assurance or subscriptions | Check with your licensing team whether you own eligible Windows Server licences with Software Assurance that aren't already assigned. If you do, turn on Azure Hybrid Benefit; if you don't, there's nothing to save, so exclude this finding. |

## Idle Service Bus and Event Hubs namespaces: 2 finding(s), 965.86 CAD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [sb-legacy-orders](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-orders/providers/Microsoft.ServiceBus/namespaces/sb-legacy-orders)<br><sub>microsoft.servicebus/namespaces</sub> | demo-prod<br><sub>rg-orders</sub> | eastus | orders@example.com / - / prod | age 700d, idle 30d | 950.46 CAD<br><sub>estimated</sub> | **high** | 0 incoming and 0 outgoing messages in 30 days (Service Bus Premium, 1 messaging unit(s)), but each unit bills every hour | Confirm with the owner (orders@example.com) that no producer or consumer still points at it (a disabled app or a DR pairing), then delete it. If it must stay, scale it down to the fewest units. |
| 2 | [evh-dev-unused](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-sandbox/providers/Microsoft.EventHub/namespaces/evh-dev-unused)<br><sub>microsoft.eventhub/namespaces</sub> | demo-dev<br><sub>rg-sandbox</sub> | eastus | sandbox@example.com / - / dev | age 200d, idle 30d | 15.40 CAD<br><sub>estimated</sub> | **high** | 0 incoming and 0 outgoing messages in 30 days (Event Hubs Basic, 1 throughput unit(s)), but each unit bills every hour | Confirm with the owner (sandbox@example.com) that no producer or consumer still points at it (a disabled app or a DR pairing), then delete it. If it must stay, scale it down to the fewest units. |

## ML compute clusters that never scale to zero: 2 finding(s), 438.00 USD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [mlw-research/cpu-cluster](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-ml/providers/Microsoft.MachineLearningServices/workspaces/mlw-research/computes/cpu-cluster)<br><sub>microsoft.machinelearningservices/workspaces/computes</sub> | demo-dev<br><sub>rg-ml</sub> | eastus | ml@example.com / - / dev | idle 30d | 292.00 USD<br><sub>estimated</sub> | **high** | Cluster kept at least 2 idle node(s) (8 cores) in every hour for 30 days, so its minimum node count is above 0 and those nodes bill like VMs. No jobs ran on it in 30 days | Set the cluster's minimum node count to 0 and a short idle time before scale-down (for example 120 seconds), so nodes are released between jobs. The first job after idle then waits a few minutes for a node. |
| 2 | [mlw-research/batch-cluster](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-ml/providers/Microsoft.MachineLearningServices/workspaces/mlw-research/computes/batch-cluster)<br><sub>microsoft.machinelearningservices/workspaces/computes</sub> | demo-dev<br><sub>rg-ml</sub> | eastus | ml@example.com / - / dev | idle 30d | 146.00 USD<br><sub>estimated</sub> | **medium** | Cluster kept at least 1 idle node(s) (4 cores) in every hour for 30 days, so its minimum node count is above 0 and those nodes bill like VMs. It does run jobs (up to 6 active nodes), so only the always-idle part is the saving | Set the cluster's minimum node count to 0 and a short idle time before scale-down (for example 120 seconds), so nodes are released between jobs. The first job after idle then waits a few minutes for a node. |

## Idle NAT, VPN and ExpressRoute gateways and circuits: 3 finding(s), 548.23 CAD + 1 unknown/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [vpngw-old-branch](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworkGateways/vpngw-old-branch)<br><sub>microsoft.network/virtualnetworkgateways</sub> | demo-prod<br><sub>rg-net</sub> | eastus | netops@example.com / - / prod | unknown | 502.09 CAD<br><sub>estimated</sub> | **medium** | VPN gateway (VpnGw2) has no site-to-site or VNet-to-VNet connections and no point-to-site configuration | Confirm with the owner (netops@example.com) that it isn't a DR standby or waiting for a connection (re-creating a gateway takes 30-45 minutes), then delete it. |
| 2 | [nat-dev-unused](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-net-dev/providers/Microsoft.Network/natGateways/nat-dev-unused)<br><sub>microsoft.network/natgateways</sub> | demo-dev<br><sub>rg-net-dev</sub> | eastus | - / - / dev | unknown | 46.14 CAD<br><sub>estimated</sub> | **high** | NAT gateway is attached to no subnet; its public IPs keep billing too | Delete it, or attach it to the subnets that need outbound access. Release its public IPs if they aren't needed. |
| 3 | [erc-pending-dc2](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-net/providers/Microsoft.Network/expressRouteCircuits/erc-pending-dc2)<br><sub>microsoft.network/expressroutecircuits</sub> | demo-prod<br><sub>rg-net</sub> | eastus | netops@example.com / - / - | unknown | unknown | **high** | ExpressRoute circuit (Standard_MeteredData) is billed but the provider state is NotProvisioned | If the circuit will never be provisioned, ask the provider to deprovision it and then delete it. Billing runs from creation, not from provisioning. |

## Application Gateways with no backends: 1 finding(s), 509.10 CAD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [agw-legacy-portal](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-web/providers/Microsoft.Network/applicationGateways/agw-legacy-portal)<br><sub>microsoft.network/applicationgateways</sub> | demo-prod<br><sub>rg-web</sub> | westeurope | web@example.com / - / prod | unknown | 509.10 CAD<br><sub>estimated</sub> | **high** | Every backend pool is empty (WAF_v2, min capacity 2) | Stop it to end the hourly charge while keeping its configuration (start it again when backends return), or delete it if it has been retired. |

## VMs stopped but not deallocated: 2 finding(s), 276.48 USD + 103.51 CAD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [vm-build-agent-02](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-build/providers/Microsoft.Compute/virtualMachines/vm-build-agent-02)<br><sub>microsoft.compute/virtualmachines</sub> | demo-dev<br><sub>rg-build</sub> | eastus | ci@example.com / build / dev | age 420d, idle 47d | 276.48 USD<br><sub>billed</sub> | **high** | Power state is Stopped (not deallocated), so compute is still billed | Deallocate it to stop compute billing (its disks keep billing), or delete it if it's no longer needed. Deallocating releases dynamic public IPs. |
| 2 | [vm-win-jumpbox](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-ops/providers/Microsoft.Compute/virtualMachines/vm-win-jumpbox)<br><sub>microsoft.compute/virtualmachines</sub> | demo-prod<br><sub>rg-ops</sub> | canadacentral | ops@example.com / - / prod | age 800d, idle 90d+ | 103.51 CAD<br><sub>estimated†</sub> | **high** | Power state is Stopped (not deallocated), so compute is still billed | Deallocate it to stop compute billing (its disks keep billing), or delete it if it's no longer needed. Deallocating releases dynamic public IPs. |

## Empty App Service plans: 3 finding(s), 248.20 USD + 102.49 CAD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [asp-legacy-api](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-api/providers/Microsoft.Web/serverFarms/asp-legacy-api)<br><sub>microsoft.web/serverfarms</sub> | demo-prod<br><sub>rg-api</sub> | eastus | api-team@example.com / orders-api / prod | unknown | 248.20 USD<br><sub>advisor</sub> | **high** | Plan hosts 0 apps (PremiumV3 P1v3 x2 instance(s)); corroborated by Advisor: Unused or empty App Service plan | Delete the plan if no deployment is planned. If it's being kept for upcoming work, scale it down to Free or B1 until needed. |
| 2 | [asp-reports-weu](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-reports/providers/Microsoft.Web/serverFarms/asp-reports-weu)<br><sub>microsoft.web/serverfarms</sub> | demo-prod<br><sub>rg-reports</sub> | westeurope | bi-team@example.com / reports / prod | unknown | 102.49 CAD<br><sub>estimated†</sub> | **high** | Plan hosts 0 apps (Standard S1 x1 instance(s)) | Delete the plan if no deployment is planned. If it's being kept for upcoming work, scale it down to Free or B1 until needed. |
| 3 | [asp-playground](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-sandbox/providers/Microsoft.Web/serverFarms/asp-playground)<br><sub>microsoft.web/serverfarms</sub> | demo-dev<br><sub>rg-sandbox</sub> | centralus | sandbox@example.com / - / - | unknown | 0.00 CAD<br><sub>free</sub> | **low** | Plan hosts 0 apps (Free F1 x1 instance(s)); free/consumption tier, no charge while empty | No charge while empty. Delete to reduce clutter. |

## Oversized VMs (CPU nearly idle): 1 finding(s), 280.32 USD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [vm-api-01](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-api/providers/Microsoft.Compute/virtualMachines/vm-api-01)<br><sub>microsoft.compute/virtualmachines</sub> | demo-prod<br><sub>rg-api</sub> | eastus | api-team@example.com / orders-api / prod | age 600d | 280.32 USD<br><sub>advisor</sub> | **high** | CPU averaged under 3.3% in 95% of hours over 30 days (busiest hour 3.5%) on 16 vCPUs (Standard_D16s_v5). Half the vCPUs would likely do; check memory use first, which is not measured here; corroborated by Advisor: Right-size or shutdown underutilized virtual machines | Check memory and disk throughput with the owner (api-team@example.com) (the smaller size halves those too), then resize to the next size down in the same family. Resizing restarts the VM. |

## Over-provisioned Cosmos DB throughput: 2 finding(s), 359.74 CAD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [cosmos-orders-legacy](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-orders/providers/Microsoft.DocumentDB/databaseAccounts/cosmos-orders-legacy)<br><sub>microsoft.documentdb/databaseaccounts</sub> | demo-prod<br><sub>rg-orders</sub> | eastus | orders@example.com / orders / prod | unknown | 261.63 CAD<br><sub>estimated†</sub> | **medium** | 4,000 RU/s provisioned across 2 database/container scope(s), but the busiest partition peaked at 3.0% of it in 30 days (hourly maximum). About 800 RU/s would still leave twice the peak. With autoscale, lower the autoscale maximum instead | Lower the provisioned throughput (or the autoscale maximum) to about 800 RU/s in total, then watch for throttled (429) requests. If traffic stays this low, serverless may cost less still. |
| 2 | [cosmos-dev-idle](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-api/providers/Microsoft.DocumentDB/databaseAccounts/cosmos-dev-idle)<br><sub>microsoft.documentdb/databaseaccounts</sub> | demo-dev<br><sub>rg-api</sub> | eastus | - / - / dev | idle 30d | 98.11 CAD<br><sub>estimated†</sub> | **high** | 1,000 RU/s provisioned across 1 database/container scope(s), and no request units were consumed in 30 days. With autoscale, lower the autoscale maximum instead | Lower the provisioned throughput (or the autoscale maximum) to about 400 RU/s in total, then watch for throttled (429) requests. If traffic stays this low, serverless may cost less still. |

## App Service plans whose apps are all stopped: 2 finding(s), 322.81 CAD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [asp-intranet-old](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-intranet/providers/Microsoft.Web/serverFarms/asp-intranet-old)<br><sub>microsoft.web/serverfarms</sub> | demo-prod<br><sub>rg-intranet</sub> | eastus | web@example.com / intranet / prod | unknown | 322.81 CAD<br><sub>estimated†</sub> | **high** | All 2 app(s) on this plan are stopped (app-intranet, app-intranet-api), but the plan bills per instance (PremiumV3 P1v3 x1) | Confirm with the owner (web@example.com) whether the stopped apps will run again. If they're retired, delete them and then the plan. If they're parked, scale the plan down to B1 or Free while they're stopped (stopping an app doesn't reduce the bill). |
| 2 | [asp-free-stopped](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-sandbox/providers/Microsoft.Web/serverFarms/asp-free-stopped)<br><sub>microsoft.web/serverfarms</sub> | demo-dev<br><sub>rg-sandbox</sub> | eastus | sandbox@example.com / - / - | unknown | 0.00 CAD<br><sub>free</sub> | **low** | All 1 app(s) on this plan are stopped (app-demo), but the plan bills per instance (Free F1 x1); free/consumption tier, no charge | No charge on this tier. Delete the stopped apps and the plan to reduce clutter. |

## Idle Bastion hosts: 1 finding(s), 297.18 CAD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [bas-dev](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-net-dev/providers/Microsoft.Network/bastionHosts/bas-dev)<br><sub>microsoft.network/bastionhosts</sub> | demo-dev<br><sub>rg-net-dev</sub> | eastus | - / - / dev | idle 30d | 297.18 CAD<br><sub>estimated</sub> | **high** | 0 Bastion sessions in 30 days (Standard, 2 scale unit(s)), billed hourly regardless | Delete it and re-create it when needed (it takes about 10 minutes), or move dev/test use to the free Developer SKU. |

## Unattached managed disks: 3 finding(s), 135.18 USD + 72.17 CAD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [disk-sql-data-old](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-sql-prod/providers/Microsoft.Compute/disks/disk-sql-data-old)<br><sub>microsoft.compute/disks</sub> | demo-prod<br><sub>rg-sql-prod</sub> | eastus | data-team@example.com / billing-db / prod | age 610d, idle 140d | 135.18 USD<br><sub>billed</sub> | **high** | Unattached for 140 days (LastOwnershipUpdateTime) | Confirm with the owner (data-team@example.com) that the data isn't needed. If unsure, take an incremental snapshot (cheaper per GiB), then delete the disk. |
| 2 | [asrseeddisk-web01-a1b2c3](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-dr/providers/Microsoft.Compute/disks/asrseeddisk-web01-a1b2c3)<br><sub>microsoft.compute/disks</sub> | demo-prod<br><sub>rg-dr</sub> | westeurope | - / web / prod | age 200d, idle 45d | 58.69 CAD<br><sub>estimated†</sub> | **low** | Unattached for 45 days (LastOwnershipUpdateTime); looks like an Azure Site Recovery replica/seed disk | Confirm with the resource group owner that the data isn't needed. If unsure, take an incremental snapshot (cheaper per GiB), then delete the disk. |
| 3 | [disk-temp-build](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-build/providers/Microsoft.Compute/disks/disk-temp-build)<br><sub>microsoft.compute/disks</sub> | demo-dev<br><sub>rg-build</sub> | japaneast | ci@example.com / - / dev | age 9d, idle 3d | 13.48 CAD<br><sub>estimated†</sub> | **low** | Unattached for 3 days (LastOwnershipUpdateTime); recently detached, may be mid-redeploy | Confirm with the owner (ci@example.com) that the data isn't needed. If unsure, take an incremental snapshot (cheaper per GiB), then delete the disk. |

## Idle SQL databases: 1 finding(s), 147.17 USD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [sql-legacy/reporting-old](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-data/providers/Microsoft.Sql/servers/sql-legacy/databases/reporting-old)<br><sub>microsoft.sql/servers/databases</sub> | demo-prod<br><sub>rg-data</sub> | eastus | data-team@example.com / reporting / prod | age 400d, idle 30d | 147.17 USD<br><sub>estimated†</sub> | **high** | 0 successful connections in 30 days (S3, 100 vCore(s)), but compute bills every hour | Confirm with the owner (data-team@example.com) that nothing connects to it on a schedule longer than 30 days, then export a .bacpac or check backup retention and delete it. If it must stay online, move it to serverless with auto-pause. |

## Idle container registries: 2 finding(s), 147.39 CAD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [crlegacybuild](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-build/providers/Microsoft.ContainerRegistry/registries/crlegacybuild)<br><sub>microsoft.containerregistry/registries</sub> | demo-dev<br><sub>rg-build</sub> | eastus | ci@example.com / - / dev | age 300d, idle 30d | 140.37 CAD<br><sub>estimated</sub> | **high** | 0 image pulls by any client in 30 days; 300.0 GiB stored; 1 geo-replication(s), each billed | Confirm with the owner (ci@example.com) that no pipeline or cluster pulls from it, export any images you need, then delete it. |
| 2 | [crgraphapps](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-graph/providers/Microsoft.ContainerRegistry/registries/crgraphapps)<br><sub>microsoft.containerregistry/registries</sub> | demo-prod<br><sub>rg-graph</sub> | canadacentral | - / - / - | age 300d, idle 30d | 7.02 CAD<br><sub>estimated</sub> | **low** | 0 image pulls by any client in 30 days; 3.0 GiB stored; still referenced by Container App(s) ca-graphdb. Scale-to-zero apps only pull when a replica starts, so deleting it would break the next scale-up. | Keep it while the referencing Container App(s) exist. They pull from it when a replica starts. If those apps are retired, delete the registry along with them. |

## Idle Redis caches: 1 finding(s), 141.40 CAD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [redis-session-old](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-web-dev/providers/Microsoft.Cache/Redis/redis-session-old)<br><sub>microsoft.cache/redis</sub> | demo-dev<br><sub>rg-web-dev</sub> | eastus | - / - / dev | idle 30d | 141.40 CAD<br><sub>estimated†</sub> | **high** | No client connected at any point in 30 days (Standard C1), but the cache bills every hour | Confirm with the resource group owner that no app uses it (a connection string may sit in an app that's switched off), export the data if it matters (Premium can export to storage), then delete it. |

## Other Azure Advisor cost recommendations: 1 finding(s), 96.50 USD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [demo-prod](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111)<br><sub>subscriptions</sub> | demo-prod<br><sub></sub> | eastus | - / - / - | unknown | 96.50 USD<br><sub>advisor</sub> | **medium** | Advisor (Medium impact): Consider virtual machine reserved instance to save over your on-demand costs | Advisor suggests: Buy a 1-year Dsv5 reservation (East US). Review it on the Advisor Cost tab. |

## Non-production VMs with no shutdown schedule: 1 finding(s), 126.47 CAD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [vm-dev-api](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-api/providers/Microsoft.Compute/virtualMachines/vm-dev-api)<br><sub>microsoft.compute/virtualmachines</sub> | demo-dev<br><sub>rg-api</sub> | eastus | api-team@example.com / - / dev | age 250d | 126.47 CAD<br><sub>estimated†</sub> | **medium** | Tagged env=dev and running with no auto-shutdown schedule, so it bills around the clock. Schedulers other than auto-shutdown (Automation, Start/Stop VMs v2, pipelines) are not visible here | Agree working hours with the owner (api-team@example.com) and add an auto-shutdown schedule (or Start/Stop VMs v2 for start and stop). Shutdown deallocates, so compute stops billing; disks keep billing. |

## Unused public IP prefixes: 1 finding(s), 98.11 CAD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [ippre-legacy](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-net/providers/Microsoft.Network/publicIPPrefixes/ippre-legacy)<br><sub>microsoft.network/publicipprefixes</sub> | demo-prod<br><sub>rg-net</sub> | eastus | netops@example.com / - / prod | unknown | 98.11 CAD<br><sub>estimated</sub> | **medium** | Prefix 20.10.30.0/28 (16 addresses) has no public IP, NAT gateway or load balancer using it, but every address bills hourly | Ask the owner (netops@example.com) whether these addresses are on a partner or firewall allowlist. Deleting the prefix releases them for good and you won't get the same range back. If nobody needs them, delete it. |

## Disk snapshots older than 90 days: 2 finding(s), 88.57 CAD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [snap-sql-pre-upgrade-2025](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-sql-prod/providers/Microsoft.Compute/snapshots/snap-sql-pre-upgrade-2025)<br><sub>microsoft.compute/snapshots</sub> | demo-prod<br><sub>rg-sql-prod</sub> | australiaeast | data-team@example.com / billing-db / prod | age 412d, idle 412d | 79.05 CAD<br><sub>estimated</sub> | **high** | Snapshot is 412 days old (full); source disk still exists | Check whether a retention policy requires it. If not, delete it. If it must be kept, make sure it's incremental on Standard storage. |
| 2 | [snap-vm-old01-osdisk](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-legacy/providers/Microsoft.Compute/snapshots/snap-vm-old01-osdisk)<br><sub>microsoft.compute/snapshots</sub> | demo-dev<br><sub>rg-legacy</sub> | uksouth | legacy-team@example.com / - / dev | age 150d, idle 150d | 9.52 CAD<br><sub>estimated</sub> | **low** | Snapshot is 150 days old (incremental); source disk was deleted, may be the only copy | The source disk is gone or this is Azure Backup data. Confirm the data is not needed. Check whether a retention policy requires it. If not, delete it. If it must be kept, make sure it's incremental on Standard storage. |

## Premium disks on long-deallocated VMs: 1 finding(s), 81.94 CAD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [vm-retired-app_OsDisk](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-legacy/providers/Microsoft.Compute/disks/vm-retired-app_OsDisk)<br><sub>microsoft.compute/disks</sub> | demo-dev<br><sub>rg-legacy</sub> | eastus | legacy-team@example.com / - / dev | age 500d, idle 90d+ | 81.94 CAD<br><sub>estimated†</sub> | **high** | Premium SSD attached to VM vm-retired-app, which has been deallocated for 90+ days (no CPU data). The disk still bills at its full Premium tier | While the VM stays deallocated, switch the disk to Standard SSD and switch it back before starting the VM. If the VM is retired, snapshot what you need and delete the VM and its disks. |

## Idle Container Apps with always-on replicas: 2 finding(s), 76.41 CAD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [ca-orders-legacy](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-orders/providers/Microsoft.App/containerApps/ca-orders-legacy)<br><sub>microsoft.app/containerapps</sub> | demo-prod<br><sub>rg-orders</sub> | northeurope | orders@example.com / orders / prod | idle 30d | 65.49 CAD<br><sub>estimated</sub> | **high** | minReplicas 2 keeps replicas running, but there were 0 requests and 5.0 MiB of network traffic in 30 days | Set minReplicas to 0 so it scales to zero when idle (the first request after idle then has a cold start), or delete the app if it's no longer needed. |
| 2 | [ca-queue-worker](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-jobs/providers/Microsoft.App/containerApps/ca-queue-worker)<br><sub>microsoft.app/containerapps</sub> | demo-dev<br><sub>rg-jobs</sub> | westeurope | - / - / dev | idle 30d | 10.92 CAD<br><sub>estimated</sub> | **medium** | minReplicas 1 keeps replicas running, but there were 0 requests and 2.0 MiB of network traffic in 30 days; no HTTP ingress, so this is judged by network traffic only (a quiet background worker looks the same) | Set minReplicas to 0 so it scales to zero when idle (the first request after idle then has a cold start), or delete the app if it's no longer needed. |

## Idle API Management instances: 1 finding(s), 67.45 CAD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [apim-legacy](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-api/providers/Microsoft.ApiManagement/service/apim-legacy)<br><sub>microsoft.apimanagement/service</sub> | demo-prod<br><sub>rg-api</sub> | eastus | api-team@example.com / - / prod | age 500d, idle 30d | 67.45 CAD<br><sub>estimated</sub> | **high** | 0 gateway requests in 30 days (Developer, 1 unit(s)), but every unit bills hourly | Confirm with the owner (api-team@example.com) that nothing calls it (and that the APIs aren't only defined here), back up the configuration if needed, then delete it. A dev/test copy can move to the Consumption tier, which bills per call. |

## Front Door and Traffic Manager profiles with no endpoints: 2 finding(s), 35.00 USD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [afd-old-site](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-web/providers/Microsoft.Cdn/profiles/afd-old-site)<br><sub>microsoft.cdn/profiles</sub> | demo-prod<br><sub>rg-web</sub> | global | web@example.com / - / prod | unknown | 35.00 USD<br><sub>estimated</sub> | **high** | Standard_AzureFrontDoor profile has no endpoints, but bills its monthly base fee | Confirm with the owner (web@example.com) that no endpoint is about to be added, then delete the profile. Custom domains and WAF policies attached to it go with it. |
| 2 | [tm-unused](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-sandbox/providers/Microsoft.Network/trafficManagerProfiles/tm-unused)<br><sub>microsoft.network/trafficmanagerprofiles</sub> | demo-dev<br><sub>rg-sandbox</sub> | global | sandbox@example.com / - / - | unknown | 0.00 CAD<br><sub>free</sub> | **low** | Traffic Manager profile has no endpoints. It bills only DNS queries, so it is nearly free (clutter only) | Delete it if no DNS name points at it (check CNAME records first). |

## Premium container registries not using Premium: 1 finding(s), 42.11 CAD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [crplatform](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-platform/providers/Microsoft.ContainerRegistry/registries/crplatform)<br><sub>microsoft.containerregistry/registries</sub> | demo-prod<br><sub>rg-platform</sub> | eastus | platform@example.com / - / prod | age 300d | 42.11 CAD<br><sub>estimated</sub> | **medium** | Premium registry with no geo-replications, no private endpoints and 40.0 GiB stored, which fits Standard's 100 GiB included storage. Check for other Premium-only features (content trust, dedicated data endpoints, connected registries) first | Downgrade to Standard if you rely on none of geo-replication, private endpoints, content trust, dedicated data endpoints or connected registries. |

## Hot-tier blob data nobody reads: 1 finding(s), 27.65 CAD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [stmediaarchive](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-media/providers/Microsoft.Storage/storageAccounts/stmediaarchive)<br><sub>microsoft.storage/storageaccounts</sub> | demo-prod<br><sub>rg-media</sub> | westeurope | - / media / prod | age 500d, idle 30d | 27.65 CAD<br><sub>estimated</sub> | **medium** | 2,048 GiB of blob data on the Hot tier with 0 GetBlob reads in 30 days. Cool stores it for less (reads cost more, and there's a 30-day minimum) | Move it to the Cool tier: change the account's default tier, or add a lifecycle rule that tiers blobs not accessed for 30 days. Cool has a 30-day minimum and higher read cost, so skip this if reads are about to start. |

## Load balancers with no backends: 2 finding(s), 25.62 CAD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [lb-old-web](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-web/providers/Microsoft.Network/loadBalancers/lb-old-web)<br><sub>microsoft.network/loadbalancers</sub> | demo-prod<br><sub>rg-web</sub> | eastus | web@example.com / - / prod | unknown | 25.62 CAD<br><sub>estimated</sub> | **high** | No backend pool members and no inbound NAT rule targets (Standard, 3 rule(s), 1 frontend(s)); its frontend public IPs also keep billing | Confirm with the owner (web@example.com) that no deployment is about to add backends, then delete it and release its frontend public IPs if they aren't needed. |
| 2 | [lb-empty-scratch](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-sandbox/providers/Microsoft.Network/loadBalancers/lb-empty-scratch)<br><sub>microsoft.network/loadbalancers</sub> | demo-dev<br><sub>rg-sandbox</sub> | eastus | sandbox@example.com / - / - | unknown | 0.00 CAD<br><sub>free</sub> | **low** | No backend pool members and no inbound NAT rule targets (Standard, 0 rule(s), 0 frontend(s)); no rules, so the load balancer itself is free (clutter only) | No rules, so no charge. Delete it to reduce clutter. |

## Geo-redundant storage in non-production: 1 finding(s), 15.60 USD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [stdevlogs](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-build/providers/Microsoft.Storage/storageAccounts/stdevlogs)<br><sub>microsoft.storage/storageaccounts</sub> | demo-dev<br><sub>rg-build</sub> | eastus | - / - / dev | age 400d | 15.60 USD<br><sub>estimated</sub> | **medium** | Tagged env=dev but stores 500 GiB as RA-GRS, which keeps a second copy in another region. LRS keeps the data in one region (three copies) at a lower price per GB | Confirm with the resource group owner that this data doesn't need a copy in a second region (a dev or test copy rarely does), then change the redundancy. GRS to LRS and GZRS to ZRS take effect at once; the secondary copy is removed. |

## Private endpoints with no working connection: 2 finding(s), 14.60 USD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [pe-st-deleted](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-legacy/providers/Microsoft.Network/privateEndpoints/pe-st-deleted)<br><sub>microsoft.network/privateendpoints</sub> | demo-dev<br><sub>rg-legacy</sub> | eastus | legacy-team@example.com / - / dev | unknown | 7.30 USD<br><sub>estimated</sub> | **high** | Connection to stdeleted01 is Disconnected (the target was deleted or dropped the connection), so no traffic flows, but the endpoint bills hourly | Delete the endpoint (its network interface goes with it), and the private DNS record for it if nothing else uses that. |
| 2 | [pe-sql-rejected](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-data/providers/Microsoft.Network/privateEndpoints/pe-sql-rejected)<br><sub>microsoft.network/privateendpoints</sub> | demo-prod<br><sub>rg-data</sub> | eastus | - / - / prod | unknown | 7.30 USD<br><sub>estimated</sub> | **medium** | Connection to sql-partner was Rejected by the owner of the target, so no traffic flows, but the endpoint bills hourly | Ask the resource group owner whether the connection should be requested again; if not, delete the endpoint. |

## Idle storage accounts: 2 finding(s), 16.63 CAD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [stlegacyexports](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-legacy/providers/Microsoft.Storage/storageAccounts/stlegacyexports)<br><sub>microsoft.storage/storageaccounts</sub> | demo-dev<br><sub>rg-legacy</sub> | eastus | platform@example.com / - / dev | age 500d, idle 30d | 16.07 CAD<br><sub>estimated</sub> | **high** | 0 transactions on any service (blob, file, queue, table) in 30 days; 250.0 GiB stored | Confirm with the owner (platform@example.com) that nothing reads or writes it (apps, Functions, backups, scripts) and that its data isn't needed. Then delete it, or move the data to Cool or Archive if it must be kept. |
| 2 | [stgraphdata](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-graph/providers/Microsoft.Storage/storageAccounts/stgraphdata)<br><sub>microsoft.storage/storageaccounts</sub> | demo-prod<br><sub>rg-graph</sub> | canadacentral | - / graph / prod | age 500d, idle 30d | 0.56 CAD<br><sub>estimated</sub> | **low** | 0 transactions on any service (blob, file, queue, table) in 30 days; 20.0 GiB stored; Container App(s) in the same resource group mount an Azure Files volume (ca-graphdb). This account may be their data store, idle only because the app is scaled to zero. | Do NOT delete before confirming what uses it. A Container App in the same resource group mounts an Azure Files volume and this may be its data. If it is, it's not waste. Tag it waste-hunter:ignore=true to stop it being reported. |

## Unassociated public IPs: 3 finding(s), 10.22 CAD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [pip-old-lb-frontend](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-web/providers/Microsoft.Network/publicIPAddresses/pip-old-lb-frontend)<br><sub>microsoft.network/publicipaddresses</sub> | demo-prod<br><sub>rg-web</sub> | brazilsouth | web@example.com / web / prod | unknown | 5.11 CAD<br><sub>estimated</sub> | **high** | Not associated with any resource (Standard / Static); has a DNS label, releasing it frees the FQDN | Check DNS records and firewall or partner allowlists that reference this IP (a released static IP can't be recovered), then delete it. |
| 2 | [pip-vm-old01](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-legacy/providers/Microsoft.Network/publicIPAddresses/pip-vm-old01)<br><sub>microsoft.network/publicipaddresses</sub> | demo-dev<br><sub>rg-legacy</sub> | eastus | platform@example.com / - / dev | unknown | 5.11 CAD<br><sub>estimated</sub> | **high** | Associated only with an orphaned NIC (no VM) (Standard / Static) | Check DNS records and firewall or partner allowlists that reference this IP (a released static IP can't be recovered), then delete it. |
| 3 | [pip-test-dyn](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-sandbox/providers/Microsoft.Network/publicIPAddresses/pip-test-dyn)<br><sub>microsoft.network/publicipaddresses</sub> | demo-dev<br><sub>rg-sandbox</sub> | centralindia | sandbox@example.com / - / - | unknown | 0.00 CAD<br><sub>free</sub> | **low** | Not associated with any resource (Basic / Dynamic); Basic dynamic and unassociated, so no charge, clutter only | No charge. Delete to reduce clutter. |

## Orphaned NICs (no VM attached): 2 finding(s), 0.00 CAD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [nic-vm-old01](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-legacy/providers/Microsoft.Network/networkInterfaces/nic-vm-old01)<br><sub>microsoft.network/networkinterfaces</sub> | demo-dev<br><sub>rg-legacy</sub> | eastus | platform@example.com / - / dev | unknown | 0.00 CAD<br><sub>free</sub> | **high** | No VM, private endpoint or private link service attached; still holds a public IP (see unassociated public IPs); has an NSG association | Delete the NIC if nothing will reattach it. This frees its private IP and releases its public IP association. |
| 2 | [aks-nodepool1-nic-7](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/mc_rg-aks_aks-prod_eastus/providers/Microsoft.Network/networkInterfaces/aks-nodepool1-nic-7)<br><sub>microsoft.network/networkinterfaces</sub> | demo-prod<br><sub>mc_rg-aks_aks-prod_eastus</sub> | eastus | - / - / - | unknown | 0.00 CAD<br><sub>free</sub> | **medium** | No VM, private endpoint or private link service attached; lives in a platform-managed resource group, check the owning service first | Delete the NIC if nothing will reattach it. This frees its private IP. |

## Log Analytics: paid retention or unqueried data: 1 finding(s), cost unknown

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [log-security-archive](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-security/providers/Microsoft.OperationalInsights/workspaces/log-security-archive)<br><sub>microsoft.operationalinsights/workspaces</sub> | demo-prod<br><sub>rg-security</sub> | eastus | secops@example.com / - / prod | age 400d | unknown | **medium** | retention is 365 days, above the free 31 days; 2,400,000 records ingested in 30 days but 0 queries, including alert queries. Cost depends on GB ingested and retained, which platform metrics do not expose (see the workspace's Usage and estimated costs page). | Check the workspace's Usage and estimated costs page for the real GB and cost. Lower retention to the free period unless a compliance rule needs more (or move old data to the cheaper long-term/archive tier). If nobody queries the data, stop sending it (diagnostic settings, data collection rules) or delete the workspace. |

## Empty resource groups: 1 finding(s), 0.00 CAD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [rg-old-poc](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-old-poc)<br><sub>microsoft.resources/subscriptions/resourcegroups</sub> | demo-dev<br><sub>rg-old-poc</sub> | eastus | - / - / dev | unknown | 0.00 CAD<br><sub>free</sub> | **medium** | Resource group contains no resources indexed by Resource Graph | Delete it if nothing is about to be deployed there. Check for locks and role assignments others may rely on first. |

## Backups of deleted VMs: 1 finding(s), cost unknown

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [rsv-dev/vm-old01](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-backup/providers/Microsoft.RecoveryServices/vaults/rsv-dev/backupFabrics/Azure/protectionContainers/IaasVMContainer;iaasvmcontainerv2;rg-legacy;vm-old01/protectedItems/VM;iaasvmcontainerv2;rg-legacy;vm-old01)<br><sub>microsoft.recoveryservices/vaults/backupfabrics/protectioncontainers/protecteditems</sub> | demo-dev<br><sub>rg-backup</sub> | eastus | platform@example.com / - / dev | unknown | unknown | **low** | Backups of VM vm-old01, which no longer exists (protection state ProtectionStopped). Retained recovery points keep billing backup storage | Do NOT delete before confirming with the owner (platform@example.com): this may be the only copy of the deleted VM's data, kept on purpose. Check retention, legal hold or compliance requirements first. If it's not needed, stop protection and delete the backup data (soft delete keeps it recoverable for 14 more days). |

## Underused reservations: 1 finding(s), cost unknown

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [Standard_D4s_v5 (bbbbbbbb)](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/providers/Microsoft.Capacity/reservationOrders/aaaaaaaa-1111-2222-3333-444444444444/reservations/bbbbbbbb-1111-2222-3333-444444444444)<br><sub>microsoft.capacity/reservationorders/reservations</sub> | <br><sub></sub> |  | - / - / - | unknown | unknown | **high** | Used 30% of its reserved hours in the last 30 days (864 of 2,880 hours). The unused hours are prepaid and lost | Find what it was bought for in the portal (Reservations > Utilization). Widen its scope to shared or a management group so more resources can use it, exchange it for a size or region that runs now, or let it lapse at renewal. Unused hours are not refunded. |

## Coverage

| Tenant | Scope | Subscriptions | Status |
|---|---|---|---|
| `00000000-0000-0000-0000-00000000demo` | 2 of 2 subscription(s) visible | demo-prod, demo-dev | ok |

Rows returned per query (including ignored): `01-unattached-disks` 4, `02-orphaned-nics` 2, `03-unassociated-public-ips` 3, `04-empty-app-service-plans` 3, `05-vms-stopped-not-deallocated` 2, `06-old-snapshots` 2, `07-advisor-cost` 4, `08-idle-container-apps` 3, `09-log-analytics-workspaces` 2, `10-idle-storage-accounts` 5, `11-container-registries` 3, `12-openai-accounts` 1, `13-idle-load-balancers` 2, `14-idle-application-gateways` 1, `15-idle-network-gateways` 3, `16-idle-bastion-hosts` 2, `17-idle-sql-databases` 2, `18-premium-disks-on-deallocated-vms` 2, `19-empty-resource-groups` 1, `20-idle-ddos-protection-plans` 1, `21-app-service-plans-all-apps-stopped` 2, `22-orphaned-vm-backups` 1, `23-idle-firewalls` 3, `24-overprovisioned-cosmos-db` 4, `25-idle-data-platforms` 5, `26-idle-redis-caches` 2, `27-idle-messaging-namespaces` 3, `28-idle-api-management` 2, `29-idle-ml-compute-clusters` 1, `30-orphaned-private-endpoints` 2, `31-unused-public-ip-prefixes` 1, `32-empty-edge-profiles` 2, `33-nonprod-vms-always-on` 1, `35-hybrid-benefit-not-applied` 2, `36-nonprod-geo-redundant-storage` 2, `37-underused-vms` 3.

Checked without a Resource Graph query: Underused reservations 1 row(s). Reservation orders checked: 1 (from `-ReservationOrder` and usage records).

az calls: 109, 0 retried after throttling or a transient error, 0 metric read(s) served from cache. Metric checks ran 4 at a time (`-Parallel`).

Metric checks (a candidate is only reported when 30 days of metrics confirm it): Idle Container Apps with always-on replicas: 3 resource(s) checked, 2 finding(s); Log Analytics: paid retention or unqueried data: 2 resource(s) checked, 1 finding(s); Idle storage accounts: 4 resource(s) checked, 3 finding(s); Idle container registries: 3 resource(s) checked, 3 finding(s); Idle Azure OpenAI deployments that bill hourly: 1 account(s) checked, 2 finding(s); Idle Bastion hosts: 2 resource(s) checked, 1 finding(s); Idle SQL databases: 2 resource(s) checked, 1 finding(s); Premium disks on long-deallocated VMs: 2 resource(s) checked, 1 finding(s); Idle Azure Firewalls: 3 resource(s) checked, 2 finding(s); Over-provisioned Cosmos DB throughput: 4 resource(s) checked, 2 finding(s); Idle Fabric, Synapse and Data Explorer compute: 5 resource(s) checked, 3 finding(s); Idle Redis caches: 2 resource(s) checked, 1 finding(s); Idle Service Bus and Event Hubs namespaces: 3 resource(s) checked, 2 finding(s); Idle API Management instances: 2 resource(s) checked, 1 finding(s); ML compute clusters that never scale to zero: 1 resource(s) checked, 2 finding(s); Geo-redundant storage in non-production: 2 resource(s) checked, 1 finding(s); Oversized VMs (CPU nearly idle): 3 resource(s) checked, 1 finding(s).

**Warnings and errors:**

- Skipped subscription 'demo-retired' (33333333-3333-3333-3333-333333333333): state Disabled.
- 10 finding(s) priced from pricing.json (US East, USD) because no regional price was available.

The CSV with every finding, including reference commands, is `findings.csv` in this folder. Reference commands are text only. Review them and run them yourself if you decide to act.

