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
- In `SKILL.md`, never write `$0`, `$1` or `$ARGUMENTS`, even as prices. The skill loader replaces
  them with the invocation arguments ("Cost $0" was rendered as "Cost -AllTenants").
- In the runner, don't `return , $array` from a function whose result is piped or `@()`-wrapped.
  That nests the array and turns every `Where-Object` into a match-all.

## Validating changes

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
