# Roadmap

Improvement plan from the project review on 2026-11-26. Status is kept up to date as items land.
Every item follows `CLAUDE.md`: read-only Azure, no secrets in output, and a test that fails without
the change.

## 0. Fixture clock — done

Fixture timestamps are absolute, but the runner judged them against the system clock, so idle days
drifted one per day and CI failed the day after the fixtures were generated (`vm-build-agent-02`
went from 47 to 48 idle days). `New-Fixtures.ps1` now writes `fixtures/clock.json`. Fixture mode
uses it as `$Now`, and report metadata uses the real run time (`$RunTime`).

## 1. Correctness

| Item | Status |
|---|---|
| **Partial savings reported at the whole bill.** Tier changes (Premium disk to Standard SSD, Hot to Cool, Premium registry to Standard) and retention-only Log Analytics findings used the resource's full 30-day bill as the saving. They now use the price difference, and the bill is shown as context. | done |
| **Deny-rule gaps** in `.claude/settings.json`: `set`, `add`, `remove`, `assign`, `import`, `swap`, `failover`, `restore`, `upgrade`, `regenerate`/`renew`, `upload`/`download`, `containerapp secret`. `az account set` must stay allowed. Tightening only, and needs the user's approval. | proposed |
| **Skill description** listed only waste types 1–12, so requests about types 13–19 might not trigger the skill. | done |
| **Prefix match in "not rechecked".** A failed check on `.../st1` hid the resolution of `.../st10`. It now matches the ID itself or its children only. | done |
| **Deduplication by ID only.** Two waste types on one resource kept only the first. Findings are now deduplicated by type + ID, and an Advisor recommendation merges into one finding only. | done |
| Doc fixes: Advisor merge applies to every type (not just 1–6), README "phase 1" heading, README layout block. | done |

## 2. Scaling to large tenants

- **Retry on throttling (HTTP 429)** in `Invoke-AzRead`. Resource Graph allows about 15 requests per
  5 seconds, and one throttled page currently fails the whole query and marks the tenant partial.
  Reuse the backoff in `Invoke-PriceApi`.
- **Parallel metric checks.** Every storage account is a candidate and costs 2–4 sequential `az`
  calls, so 500 accounts means over 1,000 calls (30+ minutes). Use `ForEach-Object -Parallel` with
  a throttle limit, plus a cache keyed by resource and metric.
- **Split the runner** (about 1,600 lines) into dot-sourced files: pricing, checks, actions,
  report. Today a new waste type touches `$TypeInfo`, `$CandidateTypes`, `Confirm-Candidate`,
  `Get-LivePrice`, `Get-Estimate` and `Get-Action`. Make it one record per type, ideally before
  adding many new types.

## 3. New waste types, by likely savings

| Priority | Type | Detection | Typical cost |
|---|---|---|---|
| ★★★ | DDoS Protection plan with no virtual networks attached | Resource Graph | ~USD 2,900/month each |
| ★★★ | Azure Firewall with ~0 data processed | metric-confirmed | USD 900–1,300+/month |
| ★★★ | App Service plan where every app is stopped (#4 misses it because the plan isn't empty) | Resource Graph | full plan price |
| ★★ | Backup items whose source VM or database was deleted | Resource Graph `recoveryservicesresources` | protected-instance fee + storage |
| ★★ | Cosmos DB provisioned RU/s with ~0 requests | metric `TotalRequests` | often hundreds/month |
| ★★ | Idle Redis, API Management, Service Bus/Event Hubs Premium, Synapse dedicated pools, Fabric/Power BI Embedded capacities | metric-confirmed | high |
| ★ | Full (non-incremental) snapshots that could be incremental | Resource Graph | storage saving |
| ★ | Uniform scale set instances stopped but not deallocated (known limitation) | check whether `computeresources` exposes their power state | |
| ? | Underused reservations | `az consumption reservation summary` is a consumption read, but needs a reservation order ID; listing orders probably needs a command outside the allowed list (user decision) | |

Each new type needs fixture cases it must flag, cases it must drop, and an entry in the suite's
expected finding set.

## 4. Features

1. **Local exclusions file** (`exclusions.json`: ID or pattern, reason, expiry). Scanning needs only
   Reader, but tagging needs write access, so many users can't exclude anything today. Also a
   `waste-hunter:ignore-until=<date>` tag.
2. **Configurable thresholds**: snapshot age (90 days), minimum age (30 days), Hot-blob size
   (100 GiB), Container Apps traffic (100 MiB).
3. **Scheduled-scan template**: a GitHub Actions workflow that signs in through OIDC with a
   Reader-only identity, a `-FailOnHighConfidenceAbove <amount>` exit code, a job summary, and reports
   kept as short-lived artifacts (they contain resource IDs).
4. **Trends across N scans**: savings over time, time to resolve per owner, oldest open findings.
5. **Billed cost for MCA accounts** through Cost Management queries. `CLAUDE.md` allows cost
   queries, but this needs the `costmanagement` CLI extension and an allow-list addition.

## Order

1. Correctness (section 1).
2. Scaling: throttling retry, parallel metric checks, metric cache.
3. Value: exclusions file, then DDoS, Firewall, all-stopped plans, orphaned backups.
4. Product: split the runner with one record per type, scheduled CI, trends, MCA billing.
