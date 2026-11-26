# Azure waste report

## Estimated monthly savings: **16,057.66 CAD + 2,277.68 USD**

High confidence: **15,887.71 CAD + 2,181.18 USD**. The rest needs a check before acting (see each finding's confidence and reason).

28 finding(s) across 14 waste type(s). 3 resource(s) excluded by `waste-hunter:ignore=true`.

Generated 2026-11-26 22:42 UTC. Scope: tenant(s) 00000000-0000-0000-0000-00000000demo. **Read-only scan: nothing in Azure was changed.**

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
| Other Azure Advisor cost recommendations | 2 | 376.82 USD | 1 | 1 | 0 | 1 |

**Cost sources:** *billed* is the actual 30-day cost from the Consumption API, scaled to 30 days. *advisor* is Azure Advisor's monthly savings estimate. *estimated* is pay-as-you-go list prices for each resource's own region, in CAD, from the Azure Retail Prices API, with `scripts/pricing.json` (US East, USD) as the fallback. Snapshot estimates are upper bounds. Advisor recommendations that match a finding above are merged into it and not counted twice.

**Ranking across currencies:** amounts are shown in their original currency, but findings are ranked after converting them to CAD at the rate implied by Microsoft's price list (1 USD = 1.4037 CAD).

## Idle Azure OpenAI deployments that bill hourly: 2 finding(s), 15,370.51 CAD + 1,241.00 USD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [oai-research/gpt-ptu-eval](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-ml/providers/Microsoft.CognitiveServices/accounts/oai-research/deployments/gpt-ptu-eval)<br><sub>microsoft.cognitiveservices/accounts/deployments</sub> | demo-dev<br><sub>rg-ml</sub> | eastus | ml@example.com / research / dev | age 120d, idle 30d | 15,370.51 CAD<br><sub>estimated</sub> | **high** | Deployment 'gpt-ptu-eval' (model gpt-4o) bills hourly for 15 PTU of GlobalProvisionedManaged but had 0 requests in 30 days. If a PTU reservation covers it, the commitment is already paid, but the capacity is still unused | Delete the deployment (re-create it when needed). For PTU, also check whether a reservation covers it before you rely on the saving. |
| 2 | [oai-research/gpt-4o-mini-support-ft](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-ml/providers/Microsoft.CognitiveServices/accounts/oai-research/deployments/gpt-4o-mini-support-ft)<br><sub>microsoft.cognitiveservices/accounts/deployments</sub> | demo-dev<br><sub>rg-ml</sub> | eastus | ml@example.com / research / dev | age 90d, idle 30d | 1,241.00 USD<br><sub>estimated</sub> | **high** | Deployment 'gpt-4o-mini-support-ft' (model gpt-4o-mini-2024-07-18.ft-3f9a2c) bills hourly for fine-tuned model hosting but had 0 requests in 30 days | Delete the deployment (re-create it when needed). For PTU, also check whether a reservation covers it before you rely on the saving. |

## Other Azure Advisor cost recommendations: 2 finding(s), 376.82 USD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [vm-api-01](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourcegroups/rg-api/providers/microsoft.compute/virtualmachines/vm-api-01)<br><sub>microsoft.compute/virtualmachines</sub> | demo-prod<br><sub>rg-api</sub> | eastus | - / - / - | unknown | 280.32 USD<br><sub>advisor</sub> | **high** | Advisor (High impact): Right-size or shutdown underutilized virtual machines | Advisor suggests: Resize Standard_D16s_v5 to Standard_D8s_v5. Review it on the Advisor Cost tab. |
| 2 | [demo-prod](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111)<br><sub>subscriptions</sub> | demo-prod<br><sub></sub> | eastus | - / - / - | unknown | 96.50 USD<br><sub>advisor</sub> | **medium** | Advisor (Medium impact): Consider virtual machine reserved instance to save over your on-demand costs | Advisor suggests: Buy a 1-year Dsv5 reservation (East US). Review it on the Advisor Cost tab. |

## VMs stopped but not deallocated: 2 finding(s), 276.48 USD + 103.51 CAD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [vm-build-agent-02](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-build/providers/Microsoft.Compute/virtualMachines/vm-build-agent-02)<br><sub>microsoft.compute/virtualmachines</sub> | demo-dev<br><sub>rg-build</sub> | eastus | ci@example.com / build / dev | age 420d, idle 47d | 276.48 USD<br><sub>billed</sub> | **high** | Power state is Stopped (not deallocated), so compute is still billed | Deallocate it to stop compute billing (its disks keep billing), or delete it if it's no longer needed. Deallocating releases dynamic public IPs. |
| 2 | [vm-win-jumpbox](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-ops/providers/Microsoft.Compute/virtualMachines/vm-win-jumpbox)<br><sub>microsoft.compute/virtualmachines</sub> | demo-prod<br><sub>rg-ops</sub> | canadacentral | ops@example.com / - / prod | age 800d, idle 90d+ | 103.51 CAD<br><sub>estimated</sub> | **high** | Power state is Stopped (not deallocated), so compute is still billed | Deallocate it to stop compute billing (its disks keep billing), or delete it if it's no longer needed. Deallocating releases dynamic public IPs. |

## Empty App Service plans: 3 finding(s), 248.20 USD + 102.49 CAD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [asp-legacy-api](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-api/providers/Microsoft.Web/serverFarms/asp-legacy-api)<br><sub>microsoft.web/serverfarms</sub> | demo-prod<br><sub>rg-api</sub> | eastus | api-team@example.com / orders-api / prod | unknown | 248.20 USD<br><sub>advisor</sub> | **high** | Plan hosts 0 apps (PremiumV3 P1v3 x2 instance(s)); corroborated by Advisor: Unused or empty App Service plan | Delete the plan if no deployment is planned. If it's being kept for upcoming work, scale it down to Free or B1 until needed. |
| 2 | [asp-reports-weu](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-reports/providers/Microsoft.Web/serverFarms/asp-reports-weu)<br><sub>microsoft.web/serverfarms</sub> | demo-prod<br><sub>rg-reports</sub> | westeurope | bi-team@example.com / reports / prod | unknown | 102.49 CAD<br><sub>estimated</sub> | **high** | Plan hosts 0 apps (Standard S1 x1 instance(s)) | Delete the plan if no deployment is planned. If it's being kept for upcoming work, scale it down to Free or B1 until needed. |
| 3 | [asp-playground](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-sandbox/providers/Microsoft.Web/serverFarms/asp-playground)<br><sub>microsoft.web/serverfarms</sub> | demo-dev<br><sub>rg-sandbox</sub> | centralus | - / - / - | unknown | 0.00 CAD<br><sub>free</sub> | **low** | Plan hosts 0 apps (Free F1 x1 instance(s)); free/consumption tier, no charge while empty | No charge while empty. Delete to reduce clutter. |

## Unattached managed disks: 3 finding(s), 135.18 USD + 72.17 CAD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [disk-sql-data-old](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-sql-prod/providers/Microsoft.Compute/disks/disk-sql-data-old)<br><sub>microsoft.compute/disks</sub> | demo-prod<br><sub>rg-sql-prod</sub> | eastus | data-team@example.com / billing-db / prod | age 610d, idle 140d | 135.18 USD<br><sub>billed</sub> | **high** | Unattached for 140 days (LastOwnershipUpdateTime) | Confirm with the owner (data-team@example.com) that the data isn't needed. If unsure, take an incremental snapshot (cheaper per GiB), then delete the disk. |
| 2 | [asrseeddisk-web01-a1b2c3](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-dr/providers/Microsoft.Compute/disks/asrseeddisk-web01-a1b2c3)<br><sub>microsoft.compute/disks</sub> | demo-prod<br><sub>rg-dr</sub> | westeurope | - / web / prod | age 200d, idle 45d | 58.69 CAD<br><sub>estimated</sub> | **low** | Unattached for 45 days (LastOwnershipUpdateTime); looks like an Azure Site Recovery replica/seed disk | Confirm with the resource group owner that the data isn't needed. If unsure, take an incremental snapshot (cheaper per GiB), then delete the disk. |
| 3 | [disk-temp-build](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-build/providers/Microsoft.Compute/disks/disk-temp-build)<br><sub>microsoft.compute/disks</sub> | demo-dev<br><sub>rg-build</sub> | japaneast | ci@example.com / - / dev | age 9d, idle 3d | 13.48 CAD<br><sub>estimated</sub> | **low** | Unattached for 3 days (LastOwnershipUpdateTime); recently detached, may be mid-redeploy | Confirm with the owner (ci@example.com) that the data isn't needed. If unsure, take an incremental snapshot (cheaper per GiB), then delete the disk. |

## Idle container registries: 2 finding(s), 147.39 CAD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [crlegacybuild](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-build/providers/Microsoft.ContainerRegistry/registries/crlegacybuild)<br><sub>microsoft.containerregistry/registries</sub> | demo-dev<br><sub>rg-build</sub> | eastus | ci@example.com / - / dev | age 300d, idle 30d | 140.37 CAD<br><sub>estimated</sub> | **high** | 0 image pulls by any client in 30 days; 300.0 GiB stored; 1 geo-replication(s), each billed | Confirm with the owner (ci@example.com) that no pipeline or cluster pulls from it, export any images you need, then delete it. |
| 2 | [crgraphapps](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-graph/providers/Microsoft.ContainerRegistry/registries/crgraphapps)<br><sub>microsoft.containerregistry/registries</sub> | demo-prod<br><sub>rg-graph</sub> | canadacentral | - / - / - | age 300d, idle 30d | 7.02 CAD<br><sub>estimated</sub> | **low** | 0 image pulls by any client in 30 days; 3.0 GiB stored; still referenced by Container App(s) ca-graphdb. Scale-to-zero apps only pull when a replica starts, so deleting it would break the next scale-up. | Keep it while the referencing Container App(s) exist. They pull from it when a replica starts. If those apps are retired, delete the registry along with them. |

## Disk snapshots older than 90 days: 2 finding(s), 88.57 CAD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [snap-sql-pre-upgrade-2025](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-sql-prod/providers/Microsoft.Compute/snapshots/snap-sql-pre-upgrade-2025)<br><sub>microsoft.compute/snapshots</sub> | demo-prod<br><sub>rg-sql-prod</sub> | australiaeast | data-team@example.com / billing-db / prod | age 412d, idle 412d | 79.05 CAD<br><sub>estimated</sub> | **high** | Snapshot is 412 days old (full); source disk still exists | Check whether a retention policy requires it. If not, delete it. If it must be kept, make sure it's incremental on Standard storage. |
| 2 | [snap-vm-old01-osdisk](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-legacy/providers/Microsoft.Compute/snapshots/snap-vm-old01-osdisk)<br><sub>microsoft.compute/snapshots</sub> | demo-dev<br><sub>rg-legacy</sub> | uksouth | - / - / dev | age 150d, idle 150d | 9.52 CAD<br><sub>estimated</sub> | **low** | Snapshot is 150 days old (incremental); source disk was deleted, may be the only copy | The source disk is gone or this is Azure Backup data. Confirm the data is not needed. Check whether a retention policy requires it. If not, delete it. If it must be kept, make sure it's incremental on Standard storage. |

## Idle Container Apps with always-on replicas: 2 finding(s), 76.41 CAD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [ca-orders-legacy](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-orders/providers/Microsoft.App/containerApps/ca-orders-legacy)<br><sub>microsoft.app/containerapps</sub> | demo-prod<br><sub>rg-orders</sub> | northeurope | orders@example.com / orders / prod | idle 30d | 65.49 CAD<br><sub>estimated</sub> | **high** | minReplicas 2 keeps replicas running, but there were 0 requests and 5.0 MiB of network traffic in 30 days | Set minReplicas to 0 so it scales to zero when idle (the first request after idle then has a cold start), or delete the app if it's no longer needed. |
| 2 | [ca-queue-worker](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-jobs/providers/Microsoft.App/containerApps/ca-queue-worker)<br><sub>microsoft.app/containerapps</sub> | demo-dev<br><sub>rg-jobs</sub> | westeurope | - / - / dev | idle 30d | 10.92 CAD<br><sub>estimated</sub> | **medium** | minReplicas 1 keeps replicas running, but there were 0 requests and 2.0 MiB of network traffic in 30 days; no HTTP ingress, so this is judged by network traffic only (a quiet background worker looks the same) | Set minReplicas to 0 so it scales to zero when idle (the first request after idle then has a cold start), or delete the app if it's no longer needed. |

## Premium container registries not using Premium: 1 finding(s), 42.11 CAD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [crplatform](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-platform/providers/Microsoft.ContainerRegistry/registries/crplatform)<br><sub>microsoft.containerregistry/registries</sub> | demo-prod<br><sub>rg-platform</sub> | eastus | platform@example.com / - / prod | age 300d | 42.11 CAD<br><sub>estimated</sub> | **medium** | Premium registry with no geo-replications, no private endpoints and 40.0 GiB stored, which fits Standard's 100 GiB included storage. Check for other Premium-only features (content trust, dedicated data endpoints, connected registries) first | Downgrade to Standard if you rely on none of geo-replication, private endpoints, content trust, dedicated data endpoints or connected registries. |

## Hot-tier blob data nobody reads: 1 finding(s), 27.65 CAD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [stmediaarchive](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-media/providers/Microsoft.Storage/storageAccounts/stmediaarchive)<br><sub>microsoft.storage/storageaccounts</sub> | demo-prod<br><sub>rg-media</sub> | westeurope | - / media / prod | age 500d, idle 30d | 27.65 CAD<br><sub>estimated</sub> | **medium** | 2,048 GiB of blob data on the Hot tier with 0 GetBlob reads in 30 days. Cool stores it for less (reads cost more, and there's a 30-day minimum) | Move it to the Cool tier: change the account's default tier, or add a lifecycle rule that tiers blobs not accessed for 30 days. Cool has a 30-day minimum and higher read cost, so skip this if reads are about to start. |

## Idle storage accounts: 2 finding(s), 16.63 CAD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [stlegacyexports](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-legacy/providers/Microsoft.Storage/storageAccounts/stlegacyexports)<br><sub>microsoft.storage/storageaccounts</sub> | demo-dev<br><sub>rg-legacy</sub> | eastus | platform@example.com / - / dev | age 500d, idle 30d | 16.07 CAD<br><sub>estimated</sub> | **high** | 0 transactions on any service (blob, file, queue, table) in 30 days; 250.0 GiB stored | Confirm with the owner (platform@example.com) that nothing reads or writes it (apps, Functions, backups, scripts) and that its data isn't needed. Then delete it, or move the data to Cool or Archive if it must be kept. |
| 2 | [stgraphdata](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-graph/providers/Microsoft.Storage/storageAccounts/stgraphdata)<br><sub>microsoft.storage/storageaccounts</sub> | demo-prod<br><sub>rg-graph</sub> | canadacentral | - / graph / prod | age 500d, idle 30d | 0.56 CAD<br><sub>estimated</sub> | **low** | 0 transactions on any service (blob, file, queue, table) in 30 days; 20.0 GiB stored; Container App(s) in the same resource group mount an Azure Files volume (ca-graphdb). This account may be their data store, idle only because the app is scaled to zero. | Do NOT delete before confirming what uses it. A Container App in the same resource group mounts an Azure Files volume and this may be its data. If it is, it's not waste. Tag it waste-hunter:ignore=true to stop it being reported. |

## Unassociated public IPs: 3 finding(s), 10.22 CAD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [pip-old-lb-frontend](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-web/providers/Microsoft.Network/publicIPAddresses/pip-old-lb-frontend)<br><sub>microsoft.network/publicipaddresses</sub> | demo-prod<br><sub>rg-web</sub> | brazilsouth | - / web / prod | unknown | 5.11 CAD<br><sub>estimated</sub> | **high** | Not associated with any resource (Standard / Static); has a DNS label, releasing it frees the FQDN | Check DNS records and firewall or partner allowlists that reference this IP (a released static IP can't be recovered), then delete it. |
| 2 | [pip-vm-old01](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-legacy/providers/Microsoft.Network/publicIPAddresses/pip-vm-old01)<br><sub>microsoft.network/publicipaddresses</sub> | demo-dev<br><sub>rg-legacy</sub> | eastus | platform@example.com / - / dev | unknown | 5.11 CAD<br><sub>estimated</sub> | **high** | Associated only with an orphaned NIC (no VM) (Standard / Static) | Check DNS records and firewall or partner allowlists that reference this IP (a released static IP can't be recovered), then delete it. |
| 3 | [pip-test-dyn](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-sandbox/providers/Microsoft.Network/publicIPAddresses/pip-test-dyn)<br><sub>microsoft.network/publicipaddresses</sub> | demo-dev<br><sub>rg-sandbox</sub> | centralindia | - / - / - | unknown | 0.00 CAD<br><sub>free</sub> | **low** | Not associated with any resource (Basic / Dynamic); Basic dynamic and unassociated, so no charge, clutter only | No charge. Delete to reduce clutter. |

## Orphaned NICs (no VM attached): 2 finding(s), 0.00 CAD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [nic-vm-old01](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-legacy/providers/Microsoft.Network/networkInterfaces/nic-vm-old01)<br><sub>microsoft.network/networkinterfaces</sub> | demo-dev<br><sub>rg-legacy</sub> | eastus | platform@example.com / - / dev | unknown | 0.00 CAD<br><sub>free</sub> | **high** | No VM, private endpoint or private link service attached; still holds a public IP (see unassociated public IPs); has an NSG association | Delete the NIC if nothing will reattach it. This frees its private IP and releases its public IP association. |
| 2 | [aks-nodepool1-nic-7](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/mc_rg-aks_aks-prod_eastus/providers/Microsoft.Network/networkInterfaces/aks-nodepool1-nic-7)<br><sub>microsoft.network/networkinterfaces</sub> | demo-prod<br><sub>mc_rg-aks_aks-prod_eastus</sub> | eastus | - / - / - | unknown | 0.00 CAD<br><sub>free</sub> | **medium** | No VM, private endpoint or private link service attached; lives in a platform-managed resource group, check the owning service first | Delete the NIC if nothing will reattach it. This frees its private IP. |

## Log Analytics: paid retention or unqueried data: 1 finding(s), cost unknown

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [log-security-archive](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-security/providers/Microsoft.OperationalInsights/workspaces/log-security-archive)<br><sub>microsoft.operationalinsights/workspaces</sub> | demo-prod<br><sub>rg-security</sub> | eastus | secops@example.com / - / prod | age 400d | unknown | **medium** | retention is 365 days, above the free 31 days; 2,400,000 records ingested in 30 days but 0 queries, including alert queries. Cost depends on GB ingested and retained, which platform metrics do not expose (see the workspace's Usage and estimated costs page). | Check the workspace's Usage and estimated costs page for the real GB and cost. Lower retention to the free period unless a compliance rule needs more (or move old data to the cheaper long-term/archive tier). If nobody queries the data, stop sending it (diagnostic settings, data collection rules) or delete the workspace. |

## Coverage

| Tenant | Scope | Subscriptions | Status |
|---|---|---|---|
| `00000000-0000-0000-0000-00000000demo` | 2 of 2 subscription(s) visible | demo-prod, demo-dev | ok |

Rows returned per query (including ignored): `01-unattached-disks` 4, `02-orphaned-nics` 2, `03-unassociated-public-ips` 3, `04-empty-app-service-plans` 3, `05-vms-stopped-not-deallocated` 2, `06-old-snapshots` 2, `07-advisor-cost` 4, `08-idle-container-apps` 3, `09-log-analytics-workspaces` 2, `10-idle-storage-accounts` 5, `11-container-registries` 3, `12-openai-accounts` 1.

Metric checks (queries 08-12; a candidate is only reported when 30 days of metrics confirm it): Idle Container Apps with always-on replicas: 3 resource(s) checked, 2 finding(s); Log Analytics: paid retention or unqueried data: 2 resource(s) checked, 1 finding(s); Idle storage accounts: 4 resource(s) checked, 3 finding(s); Idle container registries: 3 resource(s) checked, 3 finding(s); Idle Azure OpenAI deployments that bill hourly: 1 account(s) checked, 2 finding(s).

**Warnings and errors:**

- Skipped subscription 'demo-retired' (33333333-3333-3333-3333-333333333333): state Disabled.
- 1 finding(s) priced from pricing.json (US East, USD) because no regional price was available.

The CSV with every finding, including reference commands, is `findings.csv` in this folder. Reference commands are text only. Review them and run them yourself if you decide to act.

