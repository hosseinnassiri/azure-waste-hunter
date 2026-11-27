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
| **Split the runner** into `scripts/lib/` and one record per waste type in `scripts/types/`. Output verified byte for byte against the old runner. | done (section 4) |

## 3. New waste types, by likely savings

| Priority | Type | Detection | Typical cost |
| --- | --- | --- | --- |
| ★★★ | DDoS Protection plan with no virtual networks attached — **done** (query 20) | Resource Graph | ~USD 2,900/month each |
| ★★★ | Azure Firewall with ~0 data processed — **done** (query 23) | metric-confirmed | USD 900–1,300+/month |
| ★★★ | App Service plan where every app is stopped — **done** (query 21) | Resource Graph | full plan price |
| ★★ | Backup items whose source VM was deleted — **done** (query 22: VMs, and SQL Server / SAP HANA databases on them) | Resource Graph `recoveryservicesresources` | protected-instance fee + storage |
| ★★ | Cosmos DB provisioned RU/s far above use — **done** (query 24, see section 5) | metric-confirmed | often hundreds/month |
| ★★ | Idle Redis, API Management, Service Bus/Event Hubs, Synapse dedicated pools, Data Explorer, Fabric capacities — **done** (queries 25-28; Power BI Embedded not yet) | metric-confirmed | high |
| ★ | Full (non-incremental) snapshots that could be incremental | Resource Graph | storage saving |
| ★ | Uniform scale set instances stopped but not deallocated — **done** (query 39) | Resource Graph `computeresources` | compute |
| ★★ | Underused reservations — **done** (type 34, no query) | `az consumption reservation summary list`, for orders found in usage records or passed with `-ReservationOrder` (listing every order would need a command outside the allowed list) | the unused share of the commitment |

Each new type needs fixture cases it must flag, cases it must drop, and an entry in the suite's
expected finding set.

## 4. Features

1. **Local exclusions file** — done. `waste-hunter.exclusions.json` (gitignored, or `-ExclusionsFile`):
   exact `id` or wildcard `pattern`, required `reason`, optional `wasteType` and `until`. Applied before
   metric checks (no az calls for excluded candidates) and after (deployments, Hot blobs). Expired and
   unused entries are reported; a malformed file stops the scan. `excluded.csv` lists every exclusion
   (tag or file) with its reason. **Still to do:** a `waste-hunter:ignore-until=<date>` tag (see
   section 6).
2. **Configurable thresholds**: snapshot age (90 days), minimum age (30 days), Hot-blob size
   (100 GiB), Container Apps traffic (100 MiB).
3. **Scheduled-scan template** — not needed (decided 2026-11-27). Scans run locally on demand, and
   reports stay in the gitignored `reports/` folder. CI runs only the offline test suite.
4. **Trends across N scans** — done. Every earlier scan of the same scope: one row per scan (also
   `trends.csv`), median days to resolve overall and per owner (from resolutions each scan now
   records in `findings.json`), and the findings open longest.
5. **Billed cost for MCA accounts** — investigated 2026-11-27, not pursued. The current
   `costmanagement` CLI extension has no `query` command (only `export` and `show-operation-result`).
   The remaining routes each need a new exception to the read-only rules: a narrow `az rest` POST to
   `Microsoft.CostManagement/query`, pinning an old unmaintained extension, or the Az PowerShell
   module with a second login. Decision: keep the current fallback (warn, then Advisor or list prices).

## 5. Second round (2026-11-27)

Ten suggestions from a second review, all done (commit `bb3b02a`). Every new query runs without
errors against a live login, which caught `shards` being a reserved word (query 26). The detection
logic is tested on fixtures only, because the author's tenant has none of these resource types:

| # | Item | Where |
|---|---|---|
| 1 | Over-provisioned Cosmos DB throughput: RU/s summed per database and container, peak normalized use under 10%, saving down to twice the peak | query 24 |
| 2 | Data platforms left running: Synapse dedicated pools, Data Explorer clusters; Fabric capacities at low confidence (no Azure Monitor usage metric) | query 25 |
| 3 | Idle Redis caches, Service Bus Premium and Event Hubs namespaces, API Management (Service Bus Standard added 2026-11-27) | queries 26-28 |
| 4 | ML compute clusters that never scale to zero, from workspace node metrics per cluster. Compute instances aren't in Resource Graph and have no idle metric, so they're not covered | query 29 |
| 5 | Private endpoints with a Disconnected or Rejected connection; unused public IP prefixes; Front Door profiles with no endpoints (and empty Traffic Manager profiles, free) | queries 30-32 |
| 6 | Non-prod VMs running with no auto-shutdown schedule (saving: off outside 07:00-19:00 weekdays) | query 33 |
| 7 | Underused reservations, with one new read on the allow list (`consumption reservation summary list`) and a new record kind, `Collect`, for types with no Resource Graph query | type 34 |
| 8 | Azure Hybrid Benefit not applied (Windows VMs, SQL VMs, vCore SQL), always low confidence, Dev/Test subscriptions skipped | query 35 |
| 9 | Geo-redundant storage in non-prod (GRS/GZRS to LRS/ZRS). Zone-redundant SQL in non-prod wasn't added: its price difference isn't a single meter | query 36 |
| 10 | Oversized VMs: 95th percentile of hourly CPU under 5% on 4+ vCPUs (merges with Advisor's right-size recommendation) | query 37 |
| - | Quick wins list (`QuickWin` record flag), per-owner `.md` summaries, exclusions health (gone / no longer flagged / expiring within 14 days) | report |

## 6. What's left (as of 2026-11-27)

Everything in sections 1-5 is done or decided against. The open items:

### Validate what was built

| Item | Why it matters |
|---|---|
| **Live check of types 24-39 on a tenant that has those resources.** Checked 2026-11-27 without them: all 15 queries (24-33, 35-39) run against a live login, query 36's property paths (`sku.name`, `kind`, `properties.accessTier`, `properties.creationTime`) are populated on a real storage account, and every live price lookup these types make resolves in the Retail Prices API (the `pricing.json` fallbacks for Fabric, ML clusters, private endpoints, Front Door, SQL Hybrid Benefit and GRS storage are by design). Still unverified, and needs real resources: metric names, dimensions and aggregations (`ProvisionedThroughput` per database/container, `Idle Nodes` per cluster, `QueryResult` count), the other property paths (Synapse `properties.status`, Fabric `properties.state`, private endpoint connection state, scale set instance `sku.name` and `properties.timeCreated`) and the dev/test subscription test on `quotaId` (query 35). Creating a throwaway set was decided against; note the runner skips resources under 30 days old, so a fresh set could only be probed directly (a property-path query and `az monitor metrics list` per metric), not scanned. | a wrong dimension value reads as 0 traffic, which looks idle; a wrong metric name or aggregation fails the check instead |
| **Reservation output schema** — checked 2026-11-27 against the installed Azure CLI's own schema and transformer (no reservations to read live). The summary is flattened and has `reservationId`, `reservationOrderId`, `skuName`, `usageDate`, `reservedHours`, `usedHours` and min/avg/max utilization, but **no** `kind` or quantity, so type 34 no longer reads those. Usage records have no `additionalInfo`: reserved-instance details are in `additionalProperties`, returned only with `--include-additional-properties`, which `Add-BilledCosts` now passes (the flag was run against a live subscription). Still unverified: the exact text of `ReservationOrderId` inside `additionalProperties` (string or object; both are handled). | a schema mismatch gives 0 rows, not an error |
| **Metric names and aggregations** — checked 2026-11-27 against the Azure Monitor metric reference: `ProvisionedThroughput` (Maximum; DatabaseName, CollectionName, Region; PT1H supported), `NormalizedRUConsumption`, `connectedclients` (Maximum), `IncomingMessages`/`OutgoingMessages` (Total), Synapse `Connections`/`ActiveQueries` (Total), Data Explorer `IngestionVolumeInMB` (Total) and `QueryResult` (Count), ML `Idle Nodes`/`Idle Cores`/`Active Nodes` (ClusterName). Several are published only at PT1M; the hourly requests rely on Azure Monitor rolling them up, which a live read should confirm. | |

### New waste types and gaps in existing ones

| Priority | Item | Notes |
|---|---|---|
| ~~★★~~ | ~~Backups of deleted databases (SQL in VM, SAP HANA)~~ — **done** 2026-11-27 | query 22 now also emits `orphaned-workload-backup` for database backups whose host VM is gone (checked live: the query runs). Not covered: a database dropped from a VM that still exists, which Resource Graph can't tell apart from one that's just unprotected |
| ~~★★~~ | ~~Memory check for oversized VMs (type 37)~~ — **done** 2026-11-27 | `Available Memory Percentage` read in the same call as CPU: over 50% used at the busiest hour is dropped (half the size wouldn't fit), 40% or less is high confidence, no data stays medium. Disk throughput, which also halves, is still not checked |
| ~~★★~~ | ~~Azure Managed Redis (`microsoft.cache/redisenterprise`)~~ — **done** 2026-11-27 | type 26 now covers both. Managed Redis is priced per instance (2 with high availability, per the docs); legacy Enterprise and Enterprise Flash are priced as list price x capacity units, which is an **assumption to check** against a real bill. The docs warn that internal processes can show as connected clients, so a strict "0 clients" can miss idle caches (it never flags a busy one) |
| ★ | Zone-redundant SQL databases in non-prod | left out of type 36: no single price meter for the difference |
| ~~★~~ | ~~Power BI Embedded (A SKUs) capacities left running~~ — **done** 2026-11-27 | type 25 platform `powerbi`: Gen2 `cpu_metric` under 1% in the busiest hour (high at 0%), no CPU data (Gen1, or no activity) low |
| ~~★~~ | ~~Full snapshots that could be incremental~~ — **done** 2026-11-27 | query 38: Premium full snapshots (medium) and all but the newest of 2+ full snapshots of a disk (low, upper bound), under 90 days old so they don't overlap query 06 |
| ~~★~~ | ~~Uniform scale set instances stopped but not deallocated~~ — **done** 2026-11-27 | query 39: `computeresources` has `properties.extended.instanceView.powerState.code` for Uniform instances (Flexible ones are VMs, already #5). Tags and Spot priority come from a join to the scale set; AKS nodes are medium with a node-pool action. Checked live: the query runs (no scale sets in the tenant, so the instance property paths `sku.name`, `properties.timeCreated`, `properties.licenseType` are unverified) |
| ~~★~~ | ~~Service Bus Standard, IPv6 prefixes, classic Front Door~~ — **done or decided** 2026-11-27 | **Service Bus Standard**: added to type 27 (one `Standard Base Unit` at 0.013441 USD/hour, about 9.81 a month; operations extra). **IPv6 prefixes**: no charge per the docs and no Retail Prices meter, so type 31 is right to skip them. Looking into it found a false positive: prefixes derived from a custom IP prefix (BYOIP) are free too, and query 31 now skips them (`properties.customIPPrefix.id`; checked live: the query runs). **Classic Front Door**: decided against. It retires on 2027-03-31 and can't be created any more, so every one left needs migrating anyway, and its routing-rule meters (an "included" tier at 0 and at 0.03/hour from 5 rules) don't say plainly what an idle profile costs |

### Features

| Item | Notes |
|---|---|
| `waste-hunter:ignore-until=<date>` tag | the same change in all 36 queries, plus a live check |
| Configurable thresholds | snapshot age (90 days), minimum age (30 days), Hot-blob size (100 GiB), Container Apps traffic (100 MiB), the new 10% Cosmos peak and 5% VM CPU |
| Smaller fixtures | `metrics.json` is about 250 KB because the hourly series (ML clusters, VM CPU) need 480+ points; generating them at test time would keep the repo small |

### Can't be done with the allowed commands (recorded so they aren't re-investigated)

| Item | Blocker |
|---|---|
| Listing every reservation order | needs `az reservations` (outside the allow list), so type 34 only sees orders named in usage records or passed with `-ReservationOrder` |
| Reservation prices | not readable, so type 34 has no cost, only the unused share of hours |
| ML compute instances | not in Resource Graph and no idle metric |
| Fabric capacity usage | no Azure Monitor metric (it's in the Fabric Capacity Metrics app), so type 25 reports Fabric at low confidence |
| Billed cost on MCA accounts | decided against (section 4, item 5) |
| Scheduled scans | not needed (section 4, item 3) |

## Order (history)

1. Correctness (section 1).
2. Scaling: throttling retry, parallel metric checks, metric cache.
3. Value: exclusions file, DDoS, Firewall, all-stopped plans, orphaned VM backups (all done; queries 20-23 checked live on 2026-11-27, which caught and fixed a Resource Graph join limit in 22).
4. Product: split the runner with one record per type (done), trends (done); scheduled CI and MCA billing not pursued.
5. Second round: types 24-37, quick wins, owner summaries, exclusions health (done, section 5).
6. Next: the live validation in section 6 first, since everything after it builds on those checks being right.
