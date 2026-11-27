# azure-waste-hunter

A Claude Code skill that finds wasted spend in an Azure tenant and writes a ranked report. The skill
is `.claude/skills/waste-hunter/`. The runner is `scripts/Invoke-WasteHunt.ps1` (PowerShell 7.5+).

## Hard rules

1. **All Azure access is READ-ONLY.** Never run an `az` command that creates, updates, deletes,
   deallocates, starts, stops, restarts, resizes, moves, locks or tags anything. Only these are allowed:
   - `az graph query`
   - `az monitor metrics list`
   - `az advisor recommendation list`
   - `az consumption ...` reads and other cost *queries*
   - `az cognitiveservices account deployment list`, because Azure OpenAI deployments aren't in
     Resource Graph. Read only name, SKU, capacity, model and creation date from its output.
   - `az account show` / `az account list`, plus `az account set`, which only switches the local
     CLI context between tenants and must be restored to the user's original default afterwards.

   **One non-az read is allowed:** `GET https://prices.azure.com/api/retail/prices` (the public,
   unauthenticated Azure Retail Prices API) for regional list prices. Send only
   service/SKU/region/currency filters, never resource IDs, names, tags or anything else from the tenant.
   No other external endpoints.

   That means no `az rest`, no `az resource invoke-action`, no `run-command`, and nothing that
   changes Azure "just to test". The suggested actions and reference commands in reports are
   **text for a human**. Never execute them, even if asked in passing. Tell the user to run them
   themselves.
2. **Prefer Azure Resource Graph for inventory.** One `.kql` file per waste type in
   `.claude/skills/waste-hunter/queries/`.
3. **Never print secrets, keys or connection strings.** Queries project named columns only, never
   `properties` or `tags` wholesale. Don't run commands that return secrets (`keys list`,
   `list-keys`, `show-connection-string`, `keyvault secret show`, `appsettings list`,
   `credential show`, `grant-access`, `generate-sas`, `get-credentials`). If a secret shows up in
   output anyway, don't repeat it. Redact it.

`.claude/settings.json` backs these rules with deny rules. Don't loosen them to get past a block.
Ask the user instead.

## Conventions

- Every waste query returns the same columns: `wasteType, id, name, type, tenantId, subscriptionId,
  resourceGroup, location, owner, app, env, createdTime, ageDays, idleDays, idleSource, sku, tier,
  sizeGb, os, extra, confidence, reason, ignored`. `07-advisor-cost.kql` adds `recommendationId,
  monthlySavings, currency`. The runner relies on this schema, so a new waste type must keep it.
- Queries 08-12 return **candidates** plus a `checkInputs` object (only the fields the metric check
  needs). The runner's `Confirm-Candidate` checks 30 days of metrics and turns each candidate into
  findings or drops it as in use, so nothing is reported as idle on inventory alone. Never put env
  vars, app settings or connection strings in `checkInputs`. A candidate type must come with
  synthetic test cases that it should flag AND cases it should drop.
- Anything that may be some app's data store or dependency (a storage account behind an Azure Files
  mount, a registry a Container App references) gets low confidence and "do not delete" wording.
  Quiet is not the same as safe to delete.
- Exclusion: queries compute `ignored` from the tag `waste-hunter:ignore=true` (case-insensitive) and
  the runner drops those rows and counts them. Don't filter them in KQL, or the excluded count is lost.
- Run queries from files: `az graph query -q @path/to/file.kql`. Passing KQL inline through
  `az.cmd` on Windows mangles double quotes. `//` comments in `.kql` files are fine.
- Resource Graph returns booleans as `0`/`1`.
- Number files `NN-name.kql`. The runner runs every `queries/*.kql` in order.

## Gotchas found during validation (keep these fixed)

- **Resource Graph silently drops subscriptions the token can't read**, so "0 rows" isn't proof of
  "no waste". The runner runs `scripts/coverage-check.kql` first in each tenant pass and marks the
  tenant `partial`/`failed` for any expected subscription it can't see. Never remove this.
- `az graph query` uses the *current* subscription's tenant token, so multi-tenant scans need one
  pass per tenant, switched with `az account set` and restored in `finally`.
- `az monitor metrics list` silently clips a long window to the most recent ~30 days. Query
  30-day windows.
- `az consumption usage list` returns cost-less legacy-schema records for some billing types
  (e.g. this author's Visual Studio subscriptions). The runner detects this, warns, and falls back to
  Advisor or list-price estimates.
- The Retail Prices API rate-limits (HTTP 429). `Invoke-PriceApi` retries with backoff, and the API
  is treated as down only after 3 failed lookups in a row. Its names are inconsistent: App Service
  uses `P1 v3` and `I1 v2` but also `P0v3` and `P1mv3`, so query both spellings. Elastic Premium
  (`EP*`), Premium SSD v2 and Ultra disks have no flat monthly meter and use `pricing.json`.
- **Strict mode throws on a missing key read with dot syntax**: on `[ordered]`, on plain hashtables,
  on `ConvertFrom-Json -AsHashtable` output, and on any property of `$null`. Read optional fields
  from az or API output with `Get-Key $obj 'key'` or `$h['key']`, never `$obj.key`.
- Metric quirks: Log Analytics `Ingestion Volume` counts records, not bytes, and both it and
  `Query Count` need `--aggregation Count`. `StorageUsed` (ACR) and capacity metrics only take hourly
  grains, so don't combine them with daily metrics in one call. A dimension split (`--filter
  "X eq '*'"`) returns no series at all for zero activity, which `Get-MetricStats` treats as 0.
- An empty list from a pipeline can arrive in a function as a single `$null`. Filter nulls before
  reading properties (`Format-GroupCost` crashed on a second scan with nothing resolved).
- Don't name helpers after built-in aliases: `h` is `Get-History` (the HTML escaper was `H`), and
  aliases win over functions. Don't assign `$pid`, which is read-only.
- Fixture timestamps are absolute, so fixture mode judges data against `fixtures/clock.json` (written
  by `New-Fixtures.ps1`), not the system clock. Without it, idle days drift a day each day and CI
  breaks. Report metadata (`generated`, `firstSeen`) uses the real run time (`$RunTime`).
- Billed cost is the saving only when the fix removes the whole bill. Tier changes and
  retention-only findings (`$PartialSavingTypes`, `partialSaving`) use the price difference.
- Fixture mode (`-FixtureDir`) replaces the `az` process call itself, so tests don't exercise az
  stderr or exit-code handling. Check those against a real login.
- Load Balancer and NAT Gateway prices are published under `armRegionName` `Global` / `US Gov`,
  not per region.
- In `SKILL.md`, never write `$0`, `$1` or `$ARGUMENTS`, even as prices. The skill loader replaces
  them with the invocation arguments ("Cost $0" was rendered as "Cost -AllTenants").
- In the runner, don't `return , $array` from a function whose result is piped or `@()`-wrapped.
  That nests the array and turns every `Where-Object` into a match-all.

## Validating changes

**Run the test suite before every commit.** It must pass:
`pwsh ./.claude/skills/waste-hunter/tests/Test-WasteHunt.ps1` (offline, about 2 minutes; CI runs it
too). A new waste type needs fixture cases it must flag and cases it must drop, plus an entry in the
suite's expected finding set. A bug fix needs a test that fails without it.

```powershell
# Synthetic, no Azure calls (live CAD prices from the Retail Prices API). Must produce a populated
# report. This regenerates the committed sample, which is kept in CAD:
pwsh ./.claude/skills/waste-hunter/scripts/Invoke-WasteHunt.ps1 -FixtureDir ./.claude/skills/waste-hunter/tests/fixtures -Currency CAD -OutDir ./.claude/skills/waste-hunter/tests/sample-output
# Each query against the live login (read-only):
Get-ChildItem .claude/skills/waste-hunter/queries/*.kql | % { az graph query -q "@$($_.FullName)" --first 5 --query count -o tsv }
# Full live scan:
pwsh ./.claude/skills/waste-hunter/scripts/Invoke-WasteHunt.ps1 -AllTenants
```

Reports go to `reports/<timestamp>/` (gitignored, since they contain resource IDs).
