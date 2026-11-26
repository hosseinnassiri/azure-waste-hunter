# azure-waste-hunter

A [Claude Code](https://claude.com/claude-code) skill that finds wasted spend in Azure and writes a
ranked report with estimated monthly savings. **It's read-only. It never creates, changes, stops or
deletes anything.**

Ask Claude in this repo things like *"find waste in my tenant"*, *"cleanup candidates in
subscription X"* or *"orphaned resources under management group Y"*. Or run the script directly.

## What it finds (phase 1)

| # | Waste type | How |
|---|---|---|
| 1 | Unattached managed disks | Resource Graph `diskState == Unattached`; idle time from `LastOwnershipUpdateTime` |
| 2 | Orphaned NICs | no VM, private endpoint, private link service or hosted workload |
| 3 | Unassociated public IPs | no association, or attached only to an orphaned NIC |
| 4 | Empty App Service plans | `numberOfSites == 0`, cross-checked against sites in Resource Graph |
| 5 | VMs stopped but not deallocated | `PowerState/stopped` (compute still billed); idle time from 90 days of CPU metrics |
| 6 | Snapshots older than 90 days | `timeCreated`, plus whether the source disk still exists |
| 7 | Azure Advisor cost recommendations | merged into findings 1–6 when they cover the same resource, so nothing is listed twice |

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
```

Output goes to `reports/<timestamp>/`:
- `report.md`: total estimated monthly savings at the top, a summary per waste type, findings
  ranked by cost within each type, then coverage and warnings.
- `findings.csv`: every finding, including a `referenceCommandNotExecuted` column you can review and
  run yourself if you decide to act.

See [a sample report](.claude/skills/waste-hunter/tests/sample-output/report.md). It's generated
from **synthetic** data with `-FixtureDir .claude/skills/waste-hunter/tests/fixtures`, so you can see
the format without touching Azure.

## Excluding resources

Tag a resource `waste-hunter:ignore=true` to skip it. Exclusions are counted in the report, not
hidden silently.

## How costs are estimated

In order of preference, with the source shown per finding:
1. **billed**: actual cost over the last 30 days (`az consumption usage list`), scaled to 30 days
2. **advisor**: Azure Advisor's monthly savings figure
3. **estimated**: pay-as-you-go list price **in the resource's own region**, in `-Currency`, from
   the public [Azure Retail Prices API](https://learn.microsoft.com/rest/api/cost-management/retail-prices/azure-retail-prices).
   If there's no regional price (Premium SSD v2, Ultra and Elastic Premium plans have no flat monthly
   meter) or the API is unreachable, it falls back to `scripts/pricing.json` (approximate US East
   USD), and the report says which findings were priced that way. Snapshot estimates are upper bounds.

Works in every region. Portal links follow Azure Government and Azure China, and regional prices cover
the public cloud and US Gov.

## Safety

- Every `az` call in the runner goes through an allow list: `graph query`, `monitor metrics list`,
  `advisor recommendation list`, `consumption usage list`, `account show/list/set`. Anything else
  throws. `account set` only switches the local CLI context for multi-tenant scans, and the
  original default subscription is restored afterwards.
- The only non-`az` call is a GET to the public Retail Prices API. It's sent only service, SKU,
  region and currency, never anything from your tenant. Use `-OfflinePricing` to skip it.
- `.claude/settings.json` denies write and secret-reading `az` commands for Claude Code itself.
- Queries project named columns only, never `properties` wholesale, so no secrets reach the output.
- Coverage is checked: Resource Graph silently skips subscriptions you can't read, so the runner
  checks which subscriptions it actually saw and marks a tenant `partial`/`failed`. A scope that
  wasn't fully read never shows up as clean.

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
  queries/01..07-*.kql                      one Resource Graph query per waste type
  scripts/Invoke-WasteHunt.ps1              runner: scan, idle time, cost, merge, rank, report
  scripts/coverage-check.kql                which subscriptions Resource Graph can see
  scripts/pricing.json                      fallback list prices
  tests/fixtures/, New-Fixtures.ps1         synthetic offline demo data
  tests/sample-output/                      report generated from that data
```
