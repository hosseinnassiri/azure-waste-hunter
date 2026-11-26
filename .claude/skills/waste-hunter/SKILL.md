---
name: waste-hunter
description: Read-only scan of Azure for wasted spend (unattached disks, orphaned NICs, unassociated public IPs, empty App Service plans, VMs stopped but not deallocated, snapshots over 90 days old, and Azure Advisor cost recommendations). Produces a ranked markdown report and CSV with estimated monthly savings. Use when the user asks to "find waste", "find wasted spend", "cleanup candidates", "orphaned resources", "unused resources", "Azure cost savings", "what can we delete in Azure", or similar, for a tenant, management group or subscription list.
---

# waste-hunter

Finds Azure resources that cost money and do nothing, estimates what they cost each month, and writes
a ranked report. **It never changes anything in Azure.**

## Non-negotiable rules

- READ-ONLY. The only `az` commands allowed are `az graph query`, `az monitor metrics list`,
  `az advisor recommendation list`, `az consumption` and other cost reads, and `az account show/list/set`.
  The runner enforces this with an allow list (`Invoke-AzRead`).
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

Optional: `-SkipMetrics` (faster, no idle time for VMs), `-SkipConsumption` (no billed cost,
estimates only), `-OutDir <path>`.

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
   - the total estimated monthly savings, and what share of it is *billed*, *advisor* or *estimated*
   - the top findings (around 5) by cost, with their confidence and reason
   - **coverage problems first and plainly**: any tenant marked `failed`/`partial`, or any
     subscription Resource Graph couldn't see. "0 findings" from a scope that wasn't fully read is
     not a clean result. Give the fix (for example `az login --tenant <id>`).
   - the paths to the report and CSV
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

**No duplicates with Advisor.** A recommendation whose impacted resource matches a finding from 1–6 is
merged into that finding: the confidence goes up one level and the reason gets "corroborated by
Advisor". Only unmatched recommendations appear under "Other Azure Advisor cost recommendations".
Advisor's own reservation, savings plan and right-size figures can overlap each other, so treat that
section's total as an upper bound.

## Exclusions

Any resource tagged `waste-hunter:ignore=true` (key and value case-insensitive) is skipped, including
Advisor recommendations on that resource. The report shows how many were excluded for each waste type.

## Cost (monthly, per finding)

1. **billed**: actual cost over the last 30 days from `az consumption usage list`, scaled to 30
   days. Not available for every billing type; the report warns when it falls back.
2. **advisor**: Advisor's `savingsAmount` (monthly).
3. **estimated**: list price from `scripts/pricing.json` (approximate USD pay-as-you-go). Snapshot
   estimates are upper bounds, because snapshots are billed on the GiB actually used.

## Output

- `report.md`: total savings at the top, a summary table per waste type (count, cost,
  high/medium/low, excluded), then one section per waste type ranked by cost, then coverage, then
  warnings.
- `findings.csv`: every finding, including `referenceCommandNotExecuted` (for example
  `az disk delete --ids ...`). It's for the user to review, **not for you to run**.

## Fallback if `pwsh` isn't available

Run each `queries/*.kql` with `az graph query -q @<file> --first 1000` for each tenant, plus
`scripts/coverage-check.kql` first. Drop rows where `ignored` is 1. Merge `07` rows into matching
IDs. Price findings from `pricing.json`. Write a report in the same shape. Say clearly that idle
time and billed cost were skipped.

## Demo without Azure

`-FixtureDir .claude/skills/waste-hunter/tests/fixtures` runs the full pipeline on synthetic data
(the report is labeled SYNTHETIC). `tests/New-Fixtures.ps1` regenerates those files.
