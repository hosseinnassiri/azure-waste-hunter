# azure-waste-hunter

A [Claude Code](https://claude.com/claude-code) skill that finds wasted spend in Azure and writes a
ranked report with estimated monthly savings. **It's read-only. It never creates, changes, stops or
deletes anything.**

Ask Claude in this repo things like *"find waste in my tenant"*, *"cleanup candidates in
subscription X"* or *"orphaned resources under management group Y"*. Or run the script directly.

## What it finds

| # | Waste type | How |
|---|---|---|
| 1 | Unattached managed disks | Resource Graph `diskState == Unattached`; idle time from `LastOwnershipUpdateTime` |
| 2 | Orphaned NICs | no VM, private endpoint, private link service or hosted workload |
| 3 | Unassociated public IPs | no association, or attached only to an orphaned NIC |
| 4 | Empty App Service plans | `numberOfSites == 0`, cross-checked against sites in Resource Graph |
| 5 | VMs stopped but not deallocated | `PowerState/stopped` (compute still billed); idle time from 90 days of CPU metrics |
| 6 | Snapshots older than 90 days | `timeCreated`, plus whether the source disk still exists |
| 7 | Azure Advisor cost recommendations | merged into findings 1–6 when they cover the same resource, so nothing is listed twice |
| 8 | Idle Container Apps | `minReplicas` of 1 or more, with no requests or traffic in 30 days (scale-to-zero apps cost nothing idle and are skipped) |
| 9 | Log Analytics workspaces | retention above the free period, or data ingested that nobody queries |
| 10 | Idle storage accounts / unread Hot blobs | 0 transactions in 30 days; or 100 GiB or more on Hot with 0 reads (Cool is cheaper) |
| 11 | Idle or oversized container registries | 0 pulls in 30 days; or Premium without Premium features |
| 12 | Idle Azure OpenAI deployments | PTU or fine-tuned deployments (billed hourly) with 0 requests in 30 days |
| 13 | Load balancers with no backends | Standard load balancers whose pools have no members |
| 14 | Application Gateways with no backends | running gateways whose backend pools are all empty |
| 15 | Idle NAT, VPN and ExpressRoute gateways | NAT on no subnet, gateways with no connections, unprovisioned circuits |
| 16 | Idle Bastion hosts | 0 sessions in 30 days |
| 17 | Idle SQL databases | 0 successful connections in 30 days |
| 18 | Premium disks on long-deallocated VMs | VM off 30+ days, so the disk could be Standard SSD meanwhile |
| 19 | Empty resource groups | free, but clutter |
| 20 | DDoS protection plans protecting nothing | no VNets or public IPs; the plan bills about USD 2,900/month regardless |
| 21 | App Service plans whose apps are all stopped | stopped apps still bill their plan's instances |
| 22 | Backups of deleted VMs | the vault keeps billing for retained recovery points (low confidence: may be the only copy) |
| 23 | Idle Azure Firewalls | 0 rule hits and under 1 GiB processed in 30 days |

Types 8–12, 16–18 and 23 start as candidates from Resource Graph and are only reported when 30 days of Azure
Monitor metrics confirm them. Anything that may be an app's data store or dependency (a storage
account behind an Azure Files mount, a registry a Container App pulls from) is rated low confidence
with a "do not delete" note.

Each finding includes: resource ID and portal link, type, subscription, resource group, location,
owner/app/env tags, age or idle time, estimated monthly cost and its source, confidence
(high/medium/low) with the reason, and a suggested action (text only).

## Prerequisites

- Azure CLI 2.60+ logged in (`az login`) with **Reader** on the subscriptions you want scanned
- `az extension add -n resource-graph`
- PowerShell 7.5+ (`pwsh`)
- Optional, for idle time and billed cost: **Monitoring Reader** and **Cost Management Reader**

## Usage

```powershell
# Every enabled subscription in the current tenant
pwsh ./.claude/skills/waste-hunter/scripts/Invoke-WasteHunt.ps1

pwsh ./.claude/skills/waste-hunter/scripts/Invoke-WasteHunt.ps1 -AllTenants
pwsh ./.claude/skills/waste-hunter/scripts/Invoke-WasteHunt.ps1 -ManagementGroup mg-platform
pwsh ./.claude/skills/waste-hunter/scripts/Invoke-WasteHunt.ps1 -Subscription "Prod,0000-..."   # names or IDs, comma-separated

# Prices in another currency (USD by default)
pwsh ./.claude/skills/waste-hunter/scripts/Invoke-WasteHunt.ps1 -Currency CAD

# Faster: skip metrics and consumption calls (list-price estimates only)
pwsh ./.claude/skills/waste-hunter/scripts/Invoke-WasteHunt.ps1 -SkipMetrics -SkipConsumption

# No network calls for pricing (pricing.json only)
pwsh ./.claude/skills/waste-hunter/scripts/Invoke-WasteHunt.ps1 -OfflinePricing

# Metric checks run 4 at a time by default; 1-16 allowed
pwsh ./.claude/skills/waste-hunter/scripts/Invoke-WasteHunt.ps1 -Parallel 8
```

Throttled (HTTP 429) and transient `az` errors are retried with backoff, up to 4 attempts; sign-in and
permission errors fail at once. Repeated metric reads are served from a cache. The report's Coverage
section counts calls, retries and cache hits.

Output goes to `reports/<timestamp>/`:
- `report.md`: total estimated monthly savings (and the high-confidence part) at the top, a summary
  per waste type, **changes since the last scan**, **findings by owner**, findings ranked by cost
  within each type, then coverage and warnings.
- `report.html`: the same report as one self-contained page to share (search, filters, sortable
  columns, light/dark), with no external scripts.
- `findings.csv`: every finding, including a `referenceCommandNotExecuted` column you can review and
  run yourself if you decide to act, plus `status` (new/open) and `firstSeen`.
- `by-owner/<owner>.csv`: one list per owner tag (falling back to the resource group's tag), plus
  `_no-owner.csv`.
- `findings.json`: the baseline the next scan compares against (`-Compare auto|<folder>|none`). A
  finding counts as **resolved** only when its subscription was read and its type was checked again.
  Otherwise it's listed as "not rechecked", so a failed query never looks like a fix.

See [a sample report](.claude/skills/waste-hunter/tests/sample-output/report.md). It's generated
from **synthetic** data with `-FixtureDir .claude/skills/waste-hunter/tests/fixtures -Currency CAD`,
so you can see the format without touching Azure. Its estimates are live CAD list prices for 9
regions; its billed and Advisor amounts are in USD, which shows how mixed currencies are reported.

## Tests

```powershell
pwsh ./.claude/skills/waste-hunter/tests/Test-WasteHunt.ps1
```

43 offline tests, with no Azure, no network and no dependencies:
- **Static checks:** queries are read-only and never project `properties` or `tags` whole; the
  command allow list is exact; `az` is only called through the guard; SKILL.md has no
  `$`-placeholders.
- **Scenario runs on the synthetic fixtures:** the exact finding set, metric-confirmed drops,
  exclusions, confidence on possible data stores, prices, Advisor merging, coverage failures,
  `-SkipMetrics`, scan-to-scan changes, owner routing, HTML/CSV escaping and mixed currencies.

Several tests pin bugs found during development. GitHub Actions runs the suite on Linux and
Windows on every push (`.github/workflows/tests.yml`).

## Excluding resources

Tag a resource `waste-hunter:ignore=true` to skip it, or, without write access to tag, list it in
`waste-hunter.exclusions.json` in the repo root (or pass `-ExclusionsFile <path>`):

```json
{ "exclusions": [
  { "id": "/subscriptions/.../disks/disk-forensics-2026", "reason": "legal hold", "until": "2027-03-31" },
  { "pattern": "/subscriptions/*/resourceGroups/rg-dr-*/*", "wasteType": ["unattached-disk"], "reason": "DR seeds" }
] }
```

Each entry needs an exact `id` or a wildcard `pattern`, and a `reason`. `wasteType` and `until`
(inclusive) are optional. Expired entries and entries that matched nothing show up as warnings, and a
malformed file stops the scan. The file is gitignored because it names resource IDs. See
`.claude/skills/waste-hunter/exclusions.example.json`. Exclusions are counted in the report and listed
with their reason in `excluded.csv`, not hidden silently.

## How costs are estimated

In order of preference, with the source shown per finding:
1. **billed**: actual cost over the last 30 days (`az consumption usage list`), scaled to 30 days.
   Not used when the fix saves only part of the bill (a tier change, or Log Analytics retention only).
   Those findings use the price difference instead.
2. **advisor**: Azure Advisor's monthly savings figure
3. **estimated**: pay-as-you-go list price **in the resource's own region**, in `-Currency`, from
   the public [Azure Retail Prices API](https://learn.microsoft.com/rest/api/cost-management/retail-prices/azure-retail-prices).
   If there's no regional price (Premium SSD v2, Ultra and Elastic Premium plans have no flat monthly
   meter) or the API is unreachable, it falls back to `scripts/pricing.json` (approximate US East
   USD), and the report says which findings were priced that way. Snapshot estimates are upper bounds.

Works in every region. Portal links follow Azure Government and Azure China, and regional prices cover
the public cloud and US Gov.

Billed and Advisor amounts keep their own currency, so a report can mix currencies (for example
`1,036.68 USD + 376.96 CAD`). Amounts are never added across currencies, but findings are **ranked**
after converting to `-Currency` at the exchange rate implied by Microsoft's price list, and the
report states that rate.

## Safety

- Every `az` call in the runner goes through an allow list: `graph query`, `monitor metrics list`,
  `advisor recommendation list`, `consumption usage list`, `cognitiveservices account deployment list`,
  `account show/list/set`. Anything else
  throws. `account set` only switches the local CLI context for multi-tenant scans, and the
  original default subscription is restored afterwards.
- The only non-`az` call is a GET to the public Retail Prices API. It's sent only service, SKU,
  region and currency, never anything from your tenant. Use `-OfflinePricing` to skip it.
- `.claude/settings.json` denies write and secret-reading `az` commands for Claude Code itself.
- Queries project named columns only, never `properties` wholesale, so no secrets reach the output.
- Coverage is checked: Resource Graph silently skips subscriptions you can't read, so the runner
  checks which subscriptions it actually saw and marks a tenant `partial`/`failed`. A scope that
  wasn't fully read never shows up as clean.

## Reservations and savings plans

They aren't readable with the allowed commands. Billed costs already reflect them. Estimated costs
on types a commitment can cover (VMs, OpenAI PTU, SQL, App Service, disks) are marked † in the report:
if a reservation covers the resource, the commitment is prepaid and the bill drops by less.

## Known limitations

- `az consumption usage list` returns no per-resource cost for some billing account types (MCA,
  some Visual Studio offers). The report warns and falls back to Advisor or list prices.
- Resource Graph has no creation time for NICs, public IPs or App Service plans, so their age shows as unknown.
- Uniform VM scale set instances aren't covered yet.

## Layout

```
CLAUDE.md                                   project rules (read-only Azure, no secrets)
.claude/settings.json                       deny rules backing those rules
.claude/skills/waste-hunter/
  SKILL.md                                  when to trigger, inputs, steps, output contract
  queries/01..23-*.kql                      one Resource Graph query per waste type (08-12, 16-18, 23: metric-confirmed candidates)
  scripts/Invoke-WasteHunt.ps1              runner: allow list, scope, scan, merge, rank
  scripts/lib/*.ps1                         its functions (az reads, metrics, pricing, dispatch) and the report writer
  scripts/types/NN-*.ps1                    one record per waste type: label, flags, metric check, prices, suggested action
  scripts/coverage-check.kql                which subscriptions Resource Graph can see
  scripts/rg-owners.kql                     resource group owner tags (owner fallback)
  scripts/pricing.json                      fallback list prices
  tests/Test-WasteHunt.ps1                  offline test suite
  tests/fixtures/, New-Fixtures.ps1         synthetic offline demo data (clock.json: the time it was generated)
  tests/sample-output/                      report generated from that data
.github/workflows/tests.yml                 runs the tests on every push
```
