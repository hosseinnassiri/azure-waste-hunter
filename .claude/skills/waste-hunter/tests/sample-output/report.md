# Azure waste report

## Estimated monthly savings: **1,246.67 USD**

16 finding(s) across 7 waste type(s). 2 resource(s) excluded by `waste-hunter:ignore=true`.

Generated 2026-11-26 13:46 UTC. Scope: tenant(s) 00000000-0000-0000-0000-00000000demo. **Read-only scan: nothing in Azure was changed.**

> **SYNTHETIC DEMO DATA** loaded from `fixtures`. No Azure calls were made and these resources are not real.

| Waste type | Findings | Est. monthly | High | Medium | Low | Excluded |
|---|---:|---:|---:|---:|---:|---:|
| Unattached managed disks | 3 | 182.74 USD | 1 | 0 | 2 | 1 |
| Orphaned NICs (no VM attached) | 2 | 0.00 USD | 1 | 1 | 0 | 0 |
| Unassociated public IPs | 3 | 7.30 USD | 2 | 0 | 1 | 0 |
| Empty App Service plans | 2 | 248.20 USD | 1 | 0 | 1 | 0 |
| VMs stopped but not deallocated | 2 | 374.01 USD | 2 | 0 | 0 | 0 |
| Disk snapshots older than 90 days | 2 | 57.60 USD | 1 | 0 | 1 | 0 |
| Other Azure Advisor cost recommendations | 2 | 376.82 USD | 1 | 1 | 0 | 1 |

**Cost sources:** *billed* is the actual 30-day cost from the Consumption API, scaled to 30 days. *advisor* is Azure Advisor's monthly savings estimate. *estimated* is the list price from `scripts/pricing.json` (approximate USD PAYG; snapshot estimates are upper bounds). Advisor recommendations that match a finding above are merged into it and not counted twice.

## Other Azure Advisor cost recommendations: 2 finding(s), 376.82 USD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [vm-api-01](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourcegroups/rg-api/providers/microsoft.compute/virtualmachines/vm-api-01)<br><sub>microsoft.compute/virtualmachines</sub> | demo-prod<br><sub>rg-api</sub> | eastus | - / - / - | unknown | 280.32 USD<br><sub>advisor</sub> | **high** | Advisor (High impact): Right-size or shutdown underutilized virtual machines | Advisor suggests: Resize Standard_D16s_v5 to Standard_D8s_v5. Review it on the Advisor Cost tab. |
| 2 | [demo-prod](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111)<br><sub>subscriptions</sub> | demo-prod<br><sub></sub> | eastus | - / - / - | unknown | 96.50 USD<br><sub>advisor</sub> | **medium** | Advisor (Medium impact): Consider virtual machine reserved instance to save over your on-demand costs | Advisor suggests: Buy a 1-year Dsv5 reservation (East US). Review it on the Advisor Cost tab. |

## VMs stopped but not deallocated: 2 finding(s), 374.01 USD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [vm-build-agent-02](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-build/providers/Microsoft.Compute/virtualMachines/vm-build-agent-02)<br><sub>microsoft.compute/virtualmachines</sub> | demo-dev<br><sub>rg-build</sub> | eastus | ci@example.com / build / dev | age 420d, idle 47d | 276.48 USD<br><sub>billed</sub> | **high** | Power state is Stopped (not deallocated), so compute is still billed | Deallocate it to stop compute billing (its disks keep billing), or delete it if it's no longer needed. Deallocating releases dynamic public IPs. |
| 2 | [vm-win-jumpbox](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-ops/providers/Microsoft.Compute/virtualMachines/vm-win-jumpbox)<br><sub>microsoft.compute/virtualmachines</sub> | demo-prod<br><sub>rg-ops</sub> | eastus | ops@example.com / - / prod | age 800d, idle 90d+ | 97.53 USD<br><sub>estimated</sub> | **high** | Power state is Stopped (not deallocated), so compute is still billed | Deallocate it to stop compute billing (its disks keep billing), or delete it if it's no longer needed. Deallocating releases dynamic public IPs. |

## Empty App Service plans: 2 finding(s), 248.20 USD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [asp-legacy-api](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-api/providers/Microsoft.Web/serverFarms/asp-legacy-api)<br><sub>microsoft.web/serverfarms</sub> | demo-prod<br><sub>rg-api</sub> | eastus | api-team@example.com / orders-api / prod | unknown | 248.20 USD<br><sub>advisor</sub> | **high** | Plan hosts 0 apps (PremiumV3 P1v3 x2 instance(s)); corroborated by Advisor: Unused or empty App Service plan | Delete the plan if no deployment is planned. If it's being kept for upcoming work, scale it down to Free or B1 until needed. |
| 2 | [asp-playground](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-sandbox/providers/Microsoft.Web/serverFarms/asp-playground)<br><sub>microsoft.web/serverfarms</sub> | demo-dev<br><sub>rg-sandbox</sub> | centralus | - / - / - | unknown | 0.00 USD<br><sub>estimated</sub> | **low** | Plan hosts 0 apps (Free F1 x1 instance(s)); free/consumption tier, no charge while empty | No charge while empty. Delete to reduce clutter. |

## Unattached managed disks: 3 finding(s), 182.74 USD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [disk-sql-data-old](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-sql-prod/providers/Microsoft.Compute/disks/disk-sql-data-old)<br><sub>microsoft.compute/disks</sub> | demo-prod<br><sub>rg-sql-prod</sub> | eastus | data-team@example.com / billing-db / prod | age 610d, idle 140d | 135.18 USD<br><sub>billed</sub> | **high** | Unattached for 140 days (LastOwnershipUpdateTime) | Confirm with the owner (data-team@example.com) that the data isn't needed. If unsure, take an incremental snapshot (cheaper per GiB), then delete the disk. |
| 2 | [asrseeddisk-web01-a1b2c3](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-dr/providers/Microsoft.Compute/disks/asrseeddisk-web01-a1b2c3)<br><sub>microsoft.compute/disks</sub> | demo-prod<br><sub>rg-dr</sub> | westus2 | - / web / prod | age 200d, idle 45d | 37.96 USD<br><sub>estimated</sub> | **low** | Unattached for 45 days (LastOwnershipUpdateTime); looks like an Azure Site Recovery replica/seed disk | Confirm with the resource group owner that the data isn't needed. If unsure, take an incremental snapshot (cheaper per GiB), then delete the disk. |
| 3 | [disk-temp-build](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-build/providers/Microsoft.Compute/disks/disk-temp-build)<br><sub>microsoft.compute/disks</sub> | demo-dev<br><sub>rg-build</sub> | eastus | ci@example.com / - / dev | age 9d, idle 3d | 9.60 USD<br><sub>estimated</sub> | **low** | Unattached for 3 days (LastOwnershipUpdateTime); recently detached, may be mid-redeploy | Confirm with the owner (ci@example.com) that the data isn't needed. If unsure, take an incremental snapshot (cheaper per GiB), then delete the disk. |

## Disk snapshots older than 90 days: 2 finding(s), 57.60 USD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [snap-sql-pre-upgrade-2025](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-sql-prod/providers/Microsoft.Compute/snapshots/snap-sql-pre-upgrade-2025)<br><sub>microsoft.compute/snapshots</sub> | demo-prod<br><sub>rg-sql-prod</sub> | eastus | data-team@example.com / billing-db / prod | age 412d, idle 412d | 51.20 USD<br><sub>estimated</sub> | **high** | Snapshot is 412 days old (full); source disk still exists | Check whether a retention policy requires it. If not, delete it. If it must be kept, make sure it's incremental on Standard storage. |
| 2 | [snap-vm-old01-osdisk](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-legacy/providers/Microsoft.Compute/snapshots/snap-vm-old01-osdisk)<br><sub>microsoft.compute/snapshots</sub> | demo-dev<br><sub>rg-legacy</sub> | eastus | - / - / dev | age 150d, idle 150d | 6.40 USD<br><sub>estimated</sub> | **low** | Snapshot is 150 days old (incremental); source disk was deleted, may be the only copy | The source disk is gone or this is Azure Backup data. Confirm the data is not needed. Check whether a retention policy requires it. If not, delete it. If it must be kept, make sure it's incremental on Standard storage. |

## Unassociated public IPs: 3 finding(s), 7.30 USD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [pip-old-lb-frontend](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-web/providers/Microsoft.Network/publicIPAddresses/pip-old-lb-frontend)<br><sub>microsoft.network/publicipaddresses</sub> | demo-prod<br><sub>rg-web</sub> | eastus | - / web / prod | unknown | 3.65 USD<br><sub>estimated</sub> | **high** | Not associated with any resource (Standard / Static); has a DNS label, releasing it frees the FQDN | Check DNS records and firewall or partner allowlists that reference this IP (a released static IP can't be recovered), then delete it. |
| 2 | [pip-vm-old01](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-legacy/providers/Microsoft.Network/publicIPAddresses/pip-vm-old01)<br><sub>microsoft.network/publicipaddresses</sub> | demo-dev<br><sub>rg-legacy</sub> | eastus | platform@example.com / - / dev | unknown | 3.65 USD<br><sub>estimated</sub> | **high** | Associated only with an orphaned NIC (no VM) (Standard / Static) | Check DNS records and firewall or partner allowlists that reference this IP (a released static IP can't be recovered), then delete it. |
| 3 | [pip-test-dyn](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-sandbox/providers/Microsoft.Network/publicIPAddresses/pip-test-dyn)<br><sub>microsoft.network/publicipaddresses</sub> | demo-dev<br><sub>rg-sandbox</sub> | centralus | - / - / - | unknown | 0.00 USD<br><sub>estimated</sub> | **low** | Not associated with any resource (Basic / Dynamic); Basic dynamic and unassociated, so no charge, clutter only | No charge. Delete to reduce clutter. |

## Orphaned NICs (no VM attached): 2 finding(s), 0.00 USD/month

| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |
|---:|---|---|---|---|---|---:|---|---|---|
| 1 | [nic-vm-old01](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-legacy/providers/Microsoft.Network/networkInterfaces/nic-vm-old01)<br><sub>microsoft.network/networkinterfaces</sub> | demo-dev<br><sub>rg-legacy</sub> | eastus | platform@example.com / - / dev | unknown | 0.00 USD<br><sub>estimated</sub> | **high** | No VM, private endpoint or private link service attached; still holds a public IP (see unassociated public IPs); has an NSG association | Delete the NIC if nothing will reattach it. This frees its private IP and releases its public IP association. |
| 2 | [aks-nodepool1-nic-7](https://portal.azure.com/#@00000000-0000-0000-0000-00000000demo/resource/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/mc_rg-aks_aks-prod_eastus/providers/Microsoft.Network/networkInterfaces/aks-nodepool1-nic-7)<br><sub>microsoft.network/networkinterfaces</sub> | demo-prod<br><sub>mc_rg-aks_aks-prod_eastus</sub> | eastus | - / - / - | unknown | 0.00 USD<br><sub>estimated</sub> | **medium** | No VM, private endpoint or private link service attached; lives in a platform-managed resource group, check the owning service first | Delete the NIC if nothing will reattach it. This frees its private IP. |

## Coverage

| Tenant | Scope | Subscriptions | Status |
|---|---|---|---|
| `00000000-0000-0000-0000-00000000demo` | 2 of 2 subscription(s) visible | demo-prod, demo-dev | ok |

Rows returned per query (including ignored): `01-unattached-disks` 4, `02-orphaned-nics` 2, `03-unassociated-public-ips` 3, `04-empty-app-service-plans` 2, `05-vms-stopped-not-deallocated` 2, `06-old-snapshots` 2, `07-advisor-cost` 4.

**Warnings and errors:**

- Skipped subscription 'demo-retired' (33333333-3333-3333-3333-333333333333): state Disabled.

The CSV with every finding, including reference commands, is `findings.csv` in this folder. Reference commands are text only. Review them and run them yourself if you decide to act.

