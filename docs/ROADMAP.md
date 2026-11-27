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
| --- | --- |
| **Partial savings reported at the whole bill.** Tier changes (Premium disk to Standard SSD, Hot to Cool, Premium registry to Standard) and retention-only Log Analytics findings used the resource's full 30-day bill as the saving. They now use the price difference, and the bill is shown as context. | done |
| **Deny-rule gaps** in `.claude/settings.json`: `set`, `add`, `remove`, `assign`, `import`, `swap`, `failover`, `restore`, `upgrade`, `regenerate`/`renew`, `upload`/`download`, `containerapp secret`. Added 31 patterns for both Bash and PowerShell, covering writes, secrets, data transfer and exec/ssh; a test checks they block representative writes but none of the allowed reads (it caught `az * deploy*` blocking `cognitiveservices account deployment list`). | done |
| **Skill description** listed only waste types 1–12, so requests about types 13–19 might not trigger the skill. | done |
| **Prefix match in "not rechecked".** A failed check on `.../st1` hid the resolution of `.../st10`. It now matches the ID itself or its children only. | done |
| **Deduplication by ID only.** Two waste types on one resource kept only the first. Findings are now deduplicated by type + ID, and an Advisor recommendation merges into one finding only. | done |
| Doc fixes: Advisor merge applies to every type (not just 1–6), README "phase 1" heading, README layout block. | done |

## 2. Scaling to large tenants

| Item | Status |
|---|---|
| **Retry on throttling.** `Invoke-AzRead` retries HTTP 429, 5xx and dropped connections with exponential backoff and jitter, honouring "retry after N seconds", up to 4 attempts. Sign-in, permission and request errors fail at once. The report counts retries per command. | done |
| **Parallel metric checks.** Candidate checks and VM idle lookups run `-Parallel` at a time (default 4, 1–16) in runspaces that still go through `Invoke-AzRead` and its allow list. Results keep their input order, and serial and parallel runs are tested to match. | done |
| **Metrics cache.** Identical metric reads are fetched once per run, including concurrent ones (later callers wait for the first). | done |
| **Missing `resource-graph` extension** (found on a live scan): az prompted and failed with a traceback. The runner now disables dynamic install for its az processes and names the fix. | done |
| **Offline fault injection.** `faults.json` in a fixture folder makes chosen az calls fail with real az stderr, so retry and error handling are tested without Azure. | done |
| **Split the runner** (about 1,700 lines) into dot-sourced files with one record per waste type. Moved to section 4, before adding many new types. | moved |

## 3. New waste types, by likely savings

| Priority | Type | Detection | Typical cost |
| --- | --- | --- | --- |
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

1. **Local exclusions file** — done. `waste-hunter.exclusions.json` (gitignored, or `-ExclusionsFile`):
   exact `id` or wildcard `pattern`, required `reason`, optional `wasteType` and `until`. Applied before
   metric checks (no az calls for excluded candidates) and after (deployments, Hot blobs). Expired and
   unused entries are reported; a malformed file stops the scan. `excluded.csv` lists every exclusion
   (tag or file) with its reason. **Still to do:** a `waste-hunter:ignore-until=<date>` tag, which
   needs the same change in all 19 queries and a live check (blocked until `resource-graph` is installed).
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
3. Value: exclusions file (done), then DDoS, Firewall, all-stopped plans, orphaned backups.
4. Product: split the runner with one record per type (do this before most of section 3), scheduled CI, trends, MCA billing.
