# AGENTS.md

Instructions for coding agents (GitHub Copilot, Codex and others) working in this repo. **`CLAUDE.md` is the
full, authoritative version**: read it before changing anything. Its hard rules are repeated here
because they apply to every agent, not only Claude.

## What this is

A skill that finds wasted spend in an Azure tenant and writes a ranked report. The skill is
`.claude/skills/waste-hunter/` (`SKILL.md` says when and how to use it). Copilot reads skills from
`.claude/skills/` too, so it stays there. The runner is `scripts/Invoke-WasteHunt.ps1` (PowerShell 7.5+):

```powershell
pwsh ./.claude/skills/waste-hunter/scripts/Invoke-WasteHunt.ps1                          # current tenant
pwsh ./.claude/skills/waste-hunter/scripts/Invoke-WasteHunt.ps1 -Subscription "<name or id>"
```

Reports go to `reports/<timestamp>/` (gitignored: they contain resource IDs).

## Hard rules

1. **All Azure access is READ-ONLY.** Never run an `az` command (or Az PowerShell cmdlet) that
   creates, updates, deletes, deallocates, starts, stops, restarts, resizes, moves, locks or tags
   anything. The only allowed reads are `az graph query`, `az monitor metrics list`,
   `az advisor recommendation list`, `az consumption usage list`,
   `az consumption reservation summary list`, `az cognitiveservices account deployment list`
   (name, SKU, capacity, model and creation date only), `az account show` / `list`, and
   `az account set`. `account set` only switches the local CLI context and must be put back to the
   user's original default afterwards. The one allowed non-az read is
   `GET https://prices.azure.com/api/retail/prices`, sent with service/SKU/region/currency filters
   only, never anything from the tenant. No `az rest`, no `az resource invoke-action`, no
   `run-command`, and nothing that changes Azure "just to test".
2. **Suggested actions and reference commands in reports are text for a human.** Never execute them,
   even if asked in passing. Tell the user to run them.
3. **Never print secrets, keys or connection strings.** Don't run commands that return them
   (`keys list`, `list-keys`, `show-connection-string`, `keyvault secret show`, `appsettings list`,
   `credential show`, `grant-access`, `generate-sas`, `get-credentials`). Queries project named columns
   only, never `properties` or `tags` wholesale. If a secret shows up anyway, redact it.
4. **All `az` calls in scripts go through `Invoke-AzRead`** (`scripts/lib/AzRead.ps1`), whose allow
   list enforces rule 1. The guard tests check this.
5. **Don't loosen the guard rails to get past a block.** `.claude/settings.json` holds deny rules for
   Claude Code. Ask the user instead.

The deny rules in `.claude/settings.json` only bind Claude Code. For Copilot in VS Code, the matching
approval rules are in `docs/copilot-vscode-settings.jsonc`. VS Code reads them only from **User**
settings, so the user has to paste them in. Until they do, ask before running any `az` command
yourself.

## Changing code

- Read `CLAUDE.md`'s conventions and gotchas first. They record bugs that were found and fixed.
- A new waste type is a query, a record, fixtures and test entries. See `CLAUDE.md`.
- **Run the test suite before every commit.** It must pass:
  `pwsh ./.claude/skills/waste-hunter/tests/Test-WasteHunt.ps1` (offline; CI runs it too).
- A bug fix needs a test that fails without it.
