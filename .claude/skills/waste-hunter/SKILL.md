---
name: waste-hunter
description: Read-only scan of Azure for wasted spend (unattached disks, orphaned NICs, unassociated public IPs, empty App Service plans, VMs stopped but not deallocated, snapshots over 90 days old, idle Container Apps, Log Analytics retention and unqueried data, idle storage accounts and unread Hot blobs, idle or oversized container registries, idle Azure OpenAI PTU and fine-tuned deployments, load balancers and Application Gateways with no backends, idle NAT, VPN and ExpressRoute gateways, idle Bastion hosts, idle SQL databases, Premium disks on long-deallocated VMs, empty resource groups, and Azure Advisor cost recommendations). Produces a ranked markdown report and CSV with estimated monthly savings. Use when the user asks to "find waste", "find wasted spend", "cleanup candidates", "orphaned resources", "unused resources", "Azure cost savings", "what can we delete in Azure", or similar, for a tenant, management group or subscription list.
---

# waste-hunter

Finds Azure resources that cost money and do nothing, estimates what they cost each month, and writes
a ranked report. **It never changes anything in Azure.**

## Non-negotiable rules

- READ-ONLY. The only `az` commands allowed are `az graph query`, `az monitor metrics list`,
  `az advisor recommendation list`, `az consumption` and other cost reads,
  `az cognitiveservices account deployment list`, and `az account show/list/set`.
  The runner enforces this with an allow list (`Invoke-AzRead`). The only other read is the public
  Azure Retail Prices API (`prices.azure.com`) for regional list prices, which gets SKU/region/currency
  filters only.
- Suggested actions and reference commands are text for the user. **Never execute them**, and
  don't offer to. If the user wants to act, tell them to review the commands and run them themselves.
- Never print secrets, keys or connection strings.

## Inputs: scope

Work out the scope from the request. If it isn't clear, default to the current tenant and say so.

| User says | Runner flags |
|---|---|
| "my tenant", nothing specific | *(none)*: every enabled subscription in the current `az` tenant |
| "all tenants", "everything I can see" | `-AllTenants` |
| a tenant ID | `-Tenant <id>` |
| a management group | `-ManagementGroup <mg-id>` |
| one or more subscriptions (names or IDs) | `-Subscription "<name or id>,<name or id>"` (one comma-separated string) |

Optional: `-Compare auto|<report folder>|none` (default `auto`: compare with the newest earlier
report of the same scope), `-Currency <code>` (default `USD`; for example `CAD`, `EUR`, `GBP`, `JPY`; use it when
the user names a currency), `-OfflinePricing` (no price API, `pricing.json` only), `-SkipMetrics`
(faster, no idle time for VMs), `-SkipConsumption` (no billed cost, estimates only), `-Parallel <1-16>`
(concurrent metric checks, default 4; lower it if the report shows many retries), `-OutDir <path>`.

Detection works in every region and in Azure Government and Azure China. Portal links follow the
cloud; regional prices cover the public cloud and US Gov.

## Steps

1. **Preflight.** Run `az account show` to confirm a login, then check
   `az extension show -n resource-graph`. If the extension is missing, **ask the user** before
   running `az extension add -n resource-graph`. It's a local CLI change.
2. **Run** from the repo root:
   ```
   pwsh -NoProfile -File .claude/skills/waste-hunter/scripts/Invoke-WasteHunt.ps1 <scope flags>
   ```
   It writes `reports/<timestamp>/report.md` and `findings.csv`, and restores the user's default
   subscription when it finishes.
3. **Read `report.md`** and reply with:
   - the total estimated monthly savings **and the high-confidence part** (the total includes
     low-confidence findings whose advice may be "keep it"), and what share is *billed*, *advisor*
     or *estimated*
   - the top findings (around 5) by cost, with their confidence and reason
   - what changed since the last scan (new, resolved), when the report has a comparison
   - **coverage problems first and plainly**: any tenant marked `failed`/`partial`, or any
     subscription Resource Graph couldn't see. "0 findings" from a scope that wasn't fully read is
     not a clean result. Give the fix (for example `az login --tenant <id>`).
   - the paths to the report, the HTML version (for sharing) and the CSV
4. Don't paste the whole report into chat. Point to the file.

## What each finding contains

Resource ID (with a portal link), type, subscription, resource group, location, the `owner`/`app`/`env`
tags (case-insensitive, with `createdBy` used as the owner if there's no owner tag), age and/or idle
duration with its source, estimated monthly cost with its source, a confidence level with the reason,
and a suggested action (text only).

## Waste types and confidence

| # | Query | Detects | Confidence |
|---|---|---|---|
| 1 | `01-unattached-disks.kql` | `diskState == Unattached` | high if idle 30 days or more; medium 7–29 days; low under 7 days or an ASR replica/seed disk |
| 2 | `02-orphaned-nics.kql` | NIC with no VM, private endpoint, private link service or hosted workload | high; medium in platform-managed RGs (`MC_*`, `databricks-rg*`, `managedBy`). NICs themselves are free. A public IP it holds is costed under #3 |
| 3 | `03-unassociated-public-ips.kql` | no ipConfiguration and no NAT gateway, **or** attached only to an orphaned NIC | high; low for Basic dynamic and unassociated (no charge) |
| 4 | `04-empty-app-service-plans.kql` | `numberOfSites == 0` and no `microsoft.web/sites` points at it | high; low for Free, Shared, Consumption and Flex Consumption (no charge) |
| 5 | `05-vms-stopped-not-deallocated.kql` | `PowerState/stopped` | high. Idle time is the last non-zero CPU datapoint from 90 days of Azure Monitor metrics |
| 6 | `06-old-snapshots.kql` | `timeCreated` older than 90 days | high if over 365 days and the source disk exists; medium otherwise; low if the source disk was deleted (may be the only copy) or it's Azure Backup data |
| 7 | `07-advisor-cost.kql` | Advisor Cost recommendations (not dismissed or postponed) | Advisor impact High→high, Medium→medium, Low→low |
| 8 | `08-idle-container-apps.kql` | `minReplicas` 1 or more, with 0 requests and under 100 MiB of network traffic in 30 days | high with HTTP ingress; medium without HTTP ingress (judged by network only) or on a dedicated workload profile |
| 9 | `09-log-analytics-workspaces.kql` | retention above the free period (31 days, 90 with Sentinel), or records ingested but 0 queries in 30 days | medium when unqueried; low for retention only (may be compliance). Cost unknown: metrics count records, not GB |
| 10 | `10-idle-storage-accounts.kql` | 0 transactions in 30 days; or 100 GiB or more of Hot blobs with 0 GetBlob reads (saving = Hot minus Cool) | idle: high (medium on Cool/Cold/Archive). **Low when a Container App in the same resource group mounts Azure Files**: it may be the app's data. Unread Hot: medium |
| 11 | `11-container-registries.kql` | 0 pulls by any client in 30 days; or Premium with no replications, no private endpoints and 100 GiB or less stored | idle: high; **low when a Container App still references it**. Oversized: medium |
| 12 | `12-openai-accounts.kql` | PTU or fine-tuned deployments (both bill hourly) with 0 requests in 30 days; pay-per-token deployments are skipped | high; medium if created under 30 days ago |
| 13 | `13-idle-load-balancers.kql` | Standard load balancer with no backend pool members and no inbound NAT targets | high; low with no rules (no charge) |
| 14 | `14-idle-application-gateways.kql` | running Application Gateway whose backend pools are all empty | high |
| 15 | `15-idle-network-gateways.kql` | NAT gateway on no subnet; VPN or ExpressRoute gateway with no connections; ExpressRoute circuit not provisioned or not connected | high for NAT and unprovisioned circuits; medium for gateways (may be DR standby) |
| 16 | `16-idle-bastion-hosts.kql` | Basic, Standard or Premium Bastion with 0 sessions in 30 days (the free Developer SKU is skipped) | high |
| 17 | `17-idle-sql-databases.kql` | SQL database (not in a pool, not auto-pausing serverless) with 0 successful connections in 30 days | high |
| 18 | `18-premium-disks-on-deallocated-vms.kql` | Premium SSD attached to a VM with no CPU activity for 30+ days; saving = Premium tier minus the same Standard SSD tier | high at 60+ days, medium at 30-59 |
| 19 | `19-empty-resource-groups.kql` | resource group with no resources (managed and Azure Backup groups skipped); free, clutter only | medium (a few types aren't indexed by Resource Graph) |

Types 8-12 and 16-18 are **candidates confirmed by 30 days of metrics**. One whose metrics show use is dropped,
not reported. Resources created under 30 days ago aren't judged. With `-SkipMetrics` these types
are left out entirely, and the report says so.

**No duplicates with Advisor.** A recommendation whose impacted resource matches a finding of any other
type is merged into that finding: the confidence goes up one level and the reason gets "corroborated by
Advisor". Only unmatched recommendations appear under "Other Azure Advisor cost recommendations".
Advisor's own reservation, savings plan and right-size figures can overlap each other, so treat that
section's total as an upper bound.

## Exclusions

Any resource tagged `waste-hunter:ignore=true` (key and value case-insensitive) is skipped, including
Advisor recommendations on that resource. The report shows how many were excluded for each waste type.

## Cost (monthly, per finding)

1. **billed**: actual cost over the last 30 days from `az consumption usage list`, scaled to 30
   days. Not available for every billing type; the report warns when it falls back. Never used as
   the saving for a partial change (Premium disk to Standard SSD, Hot to Cool, Premium registry to
   Standard, Log Analytics retention only): those use the price difference, and the cost source notes
   the whole bill.
2. **advisor**: Advisor's `savingsAmount` (monthly).
3. **estimated**: pay-as-you-go list price **for the resource's own region**, in `-Currency`, from
   the Retail Prices API (looked up by disk tier, snapshot redundancy, IP SKU, App Service SKU and OS,
   or VM size, OS and Spot). If no regional price exists or the API is unreachable, it falls back to
   `scripts/pricing.json` (US East, USD); the cost source says so, and the report warns. Snapshot
   estimates are upper bounds, because snapshots are billed on the GiB actually used.
4. **free**: NICs, free-tier plans and unassociated Basic dynamic IPs cost nothing.

Billed and Advisor amounts keep their own currency. If it differs from `-Currency`, the total is shown
per currency (for example `120.00 CAD + 35.00 USD`). Never add the parts together. For **ranking
only**, mixed-currency amounts are converted to `-Currency` at the exchange rate implied by
Microsoft's price list; the report states the rate. If no rate is available, the report warns that
the order between currencies is approximate.

## Output

- `report.md`: total savings at the top, a summary table per waste type (count, cost,
  high/medium/low, excluded), then one section per waste type ranked by cost, then coverage, then
  warnings.
- `findings.csv`: every finding, including `referenceCommandNotExecuted` (for example
  `az disk delete --ids ...`). It's for the user to review, **not for you to run**. Cells that
  start with `= + - @` are prefixed with `'` so tag values can't run as spreadsheet formulas.
- `report.html`: the same report as one self-contained file to share, with search, filters and
  sortable columns. Every value is HTML-encoded.
- `by-owner/<owner>.csv`: one list per owner (the `owner`/`createdBy` tag, falling back to the
  resource group's tag), plus `_no-owner.csv`. The report's "By owner" section names costly
  findings with no owner.
- `findings.json`: machine-readable record, the baseline for the next scan. **Changes since the
  last scan** marks each finding new or still open (with first-seen date) and lists resolved ones.
  A finding is only "resolved" if its subscription was read and its type was really checked this
  time; otherwise it's "not rechecked".

**Reservations and savings plans** aren't readable with the allowed commands. Estimated costs on
types they can cover (VMs, OpenAI PTU, SQL, App Service, disks) carry a † caveat that the real saving
may be lower. Billed costs already reflect commitments.

## Fallback if `pwsh` isn't available

Run each `queries/*.kql` with `az graph query -q @<file> --first 1000` for each tenant, plus
`scripts/coverage-check.kql` first. Drop rows where `ignored` is 1. Merge `07` rows into matching
IDs. Price findings from `pricing.json` (US East, USD). Write a report in the same shape. Say clearly
that idle time, billed cost and regional prices were skipped.

## Tests

`pwsh .claude/skills/waste-hunter/tests/Test-WasteHunt.ps1` runs the offline suite (static checks
plus synthetic scenario runs, with no Azure or network). GitHub Actions runs it on every push.

## Demo without Azure

`-FixtureDir .claude/skills/waste-hunter/tests/fixtures` runs the full pipeline on synthetic data
(the report is labeled SYNTHETIC). `tests/New-Fixtures.ps1` regenerates those files.
