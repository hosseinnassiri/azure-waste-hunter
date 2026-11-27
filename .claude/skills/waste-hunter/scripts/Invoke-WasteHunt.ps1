#requires -Version 7.5
<#
.SYNOPSIS
    azure-waste-hunter: read-only scan for wasted Azure spend.

.DESCRIPTION
    Runs ../queries/*.kql through Azure Resource Graph, adds idle time from Azure Monitor metrics
    and billed cost from the Consumption API, merges Azure Advisor cost recommendations without
    duplicating anything, and writes a ranked markdown report plus a CSV.

    READ-ONLY. Every az call goes through Invoke-AzRead, which refuses any command not on
    $AllowedAz. The only command that changes anything is 'az account set'. It switches the local
    CLI context between tenants and is reset to your original default subscription in a finally block.

    Estimated costs use each resource's own region. Prices come from the public Azure Retail Prices
    API (prices.azure.com, unauthenticated GET, sent only SKU/region/currency filters) in -Currency,
    with scripts/pricing.json (US East, USD) as the fallback. -OfflinePricing skips the API.

.EXAMPLE
    pwsh ./Invoke-WasteHunt.ps1                                # enabled subscriptions in the current tenant
    pwsh ./Invoke-WasteHunt.ps1 -AllTenants                    # every tenant this login can reach
    pwsh ./Invoke-WasteHunt.ps1 -ManagementGroup mg-platform
    pwsh ./Invoke-WasteHunt.ps1 -Subscription "Sub A,0000-..."  # names or IDs, comma-separated, any tenant
    pwsh ./Invoke-WasteHunt.ps1 -Currency EUR                  # regional list prices in euros
    pwsh ./Invoke-WasteHunt.ps1 -FixtureDir ../tests/fixtures  # demo with synthetic data, no Azure calls
#>
[CmdletBinding(DefaultParameterSetName = 'Tenant')]
param(
    [Parameter(ParameterSetName = 'Tenant')] [switch] $AllTenants,
    [Parameter(ParameterSetName = 'Tenant')] [string[]] $Tenant,
    [Parameter(ParameterSetName = 'ManagementGroup', Mandatory)] [string] $ManagementGroup,
    [Parameter(ParameterSetName = 'Subscriptions', Mandatory)] [string[]] $Subscription,
    [string] $OutDir,
    [switch] $SkipMetrics,
    [switch] $SkipConsumption,
    [ValidateSet('USD', 'AUD', 'BRL', 'CAD', 'CHF', 'CNY', 'DKK', 'EUR', 'GBP', 'INR', 'JPY', 'KRW', 'NOK', 'NZD', 'RUB', 'SEK', 'TWD')]
    [string] $Currency = 'USD',
    [switch] $OfflinePricing,
    [string] $Compare = 'auto',      # 'auto' = newest earlier report of the same scope, a report folder, or 'none'
    [ValidateRange(1, 16)] [int] $Parallel = 4,   # concurrent metric checks (az processes); 1 = sequential
    [string] $ExclusionsFile,        # default: ./waste-hunter.exclusions.json if it exists (not in fixture mode)
    [string] $FixtureDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Functions live in lib/ (dot-sourced here, so they share this script's variables). Every az call
# still goes through Invoke-AzRead (lib/AzRead.ps1) and the allow list below.
$LibFiles = @('Common', 'AzRead', 'Metrics', 'Pricing', 'WasteTypes', 'Trends' | ForEach-Object { Join-Path $PSScriptRoot "lib/$_.ps1" })
foreach ($lib in $LibFiles) { . $lib }
# Waste types: one record per type in types/NN-<name>.ps1 (see lib/WasteTypes.ps1). A bad record stops here.
$TypesDir = Join-Path $PSScriptRoot 'types'
$WasteTypes = Import-WasteTypes $TypesDir

# 'pwsh -File' can't pass arrays, so also accept comma-separated lists: -Subscription "A,B"
if ($Subscription) { $Subscription = @($Subscription | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
if ($Tenant)       { $Tenant       = @($Tenant       | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }

$SkillDir = Split-Path -Parent $PSScriptRoot
$QueryDir = Join-Path $SkillDir 'queries'
$Pricing  = Get-Content (Join-Path $PSScriptRoot 'pricing.json') -Raw | ConvertFrom-Json -AsHashtable
# Two clocks. $RunTime is when this scan ran: report timestamps, baseline ordering, firstSeen.
# $Now is the clock the data is judged against: metric windows, idle days, ages. They're the same
# for a real scan. Fixture timestamps are absolute, written when New-Fixtures.ps1 ran, so in fixture
# mode $Now is that generation time (clock.json). Otherwise idle days drift by one every day and the
# committed fixtures go stale.
$RunTime  = [DateTime]::UtcNow
$Now      = $RunTime
if (-not $OutDir) { $OutDir = Join-Path (Get-Location) (Join-Path 'reports' $RunTime.ToString('yyyyMMdd-HHmmss')) }
if ($FixtureDir) {
    $FixtureDir = (Resolve-Path $FixtureDir).Path
    $clockFile = Join-Path $FixtureDir 'clock.json'
    if (-not (Test-Path $clockFile)) { throw "Fixture folder has no clock.json (the fixture generation time). Regenerate it with tests/New-Fixtures.ps1." }
    $Now = [DateTime]::Parse((Get-Content $clockFile -Raw | ConvertFrom-Json -AsHashtable -DateKind String)['now'],
                             [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles] 'AdjustToUniversal, AssumeUniversal')
}

# ---------------------------------------------------------------------------------------------
# Read-only guard
# ---------------------------------------------------------------------------------------------
$AllowedAz = @(
    'graph query'
    'monitor metrics list'
    'advisor recommendation list'
    'consumption usage list'
    'cognitiveservices account deployment list'   # OpenAI deployments aren't in Resource Graph; names/SKUs/capacity only
    'account show'
    'account list'
    'account set'      # local CLI context only, restored at the end
)
# Never let az install an extension on its own. With dynamic install on, a missing extension
# makes az prompt (and fail reading stdin) or, with yes_without_prompt, install it silently. Both are
# a local change the user must make themselves. Process-local: child az processes inherit it, and
# the user's CLI config is untouched.
$env:AZURE_EXTENSION_USE_DYNAMIC_INSTALL = 'no'

# ---------------------------------------------------------------------------------------------
# Regional list prices: Azure Retail Prices API. A public, unauthenticated, read-only GET, and the
# only allowed non-az read. Requests contain only service/SKU/region/currency filters, never tenant data.
# ---------------------------------------------------------------------------------------------
$PriceApi   = 'https://prices.azure.com/api/retail/prices'
$PriceCache = @{}
$PriceStats = @{ live = 0; fallback = 0; failedLookups = 0 }
$script:PriceApiDown = [bool] $OfflinePricing
$script:PriceFailStreak = 0

# GET with retry. The API rate-limits (429), so back off (honouring Retry-After) on 429, 5xx and
# network errors, up to 4 attempts.

# Matching price items (Consumption only), priced in $Cur. Returns elements, not a nested array.

# Exchange rate From -> $Currency, used ONLY to rank findings whose amounts are in different
# currencies. The price list converts every price from USD at one rate per currency, so the ratio of
# the same meter's price in both currencies is that rate. A P80 disk (about USD 3,400/month) keeps
# rounding error small. $null when unavailable (offline, API down).
$FxRates = @{}

# The one place az runs. Called only by Invoke-AzRead, after the allow-list check.

# Seconds to wait before retrying a failed az call, or $null when it shouldn't be retried.
# Retried: throttling (Resource Graph allows ~15 requests per 5 seconds per user; Monitor and ARM have
# their own limits), 5xx and dropped connections. Never retried: sign-in, permission and request
# errors, which fail the same way every time. Up to 4 attempts, honouring "retry after N seconds".
$AzMaxAttempts = 4
$RetryBaseSeconds = $FixtureDir ? 0 : 2     # fixture runs exercise the retry path without waiting

# Shared across parallel runspaces, so all thread-safe: call/retry/cache events and the metrics cache
$AzEvents    = [Collections.Concurrent.ConcurrentQueue[string]]::new()
$MetricCache = [Collections.Concurrent.ConcurrentDictionary[string, object]]::new()

# Fixture mode: canned responses from -FixtureDir, plus optional injected failures from faults.json,
# [{ cmd, match, failures, stderr }]: the first <failures> calls of <cmd> whose arguments contain
# <match> fail with <stderr>. That tests retry and error handling offline.
$FixtureFaults = @()
if ($FixtureDir -and (Test-Path (Join-Path $FixtureDir 'faults.json'))) {
    $FixtureFaults = @(foreach ($f in @(Get-Content (Join-Path $FixtureDir 'faults.json') -Raw | ConvertFrom-Json -AsHashtable)) {
        $tokens = [Collections.Concurrent.ConcurrentQueue[int]]::new(); foreach ($i in 1..([int] $f['failures'])) { $tokens.Enqueue($i) }
        @{ Cmd = [string] $f['cmd']; Match = [string] $f['match']; Stderr = [string] $f['stderr']; Tokens = $tokens }
    })
}

# Offline mode. Reads canned responses from -FixtureDir so the whole pipeline runs without Azure.

# ---------------------------------------------------------------------------------------------
# Azure reads
# ---------------------------------------------------------------------------------------------

# Last Percentage CPU datapoint. A VM that is stopped emits no CPU metrics.
# The metrics API silently clips a request to its most recent ~30 days, so 90 days of history
# means three 30-day windows, newest first, stopping at the first one with data.

# Generic metrics read. Returns @{ <metric name> = @{ Sum; Points; Last; BySplit } }. A window of
# 30 days or less is never clipped. Null datapoints and absent series (no activity) count as zero.
# With -Filter "<Dim> eq '*'", BySplit holds per-dimension-value sums.

# Metric-confirmed waste types (records with Candidate). Their query rows are candidates: Confirm-Candidate
# turns each into 0..n findings, or drops it when the metrics show it's in use.
$CandidateTypes = @($WasteTypes.Values | Where-Object { $_['Candidate'] } | ForEach-Object { $_.Name })
$MinAgeDays = 30   # need 30 days of history before calling anything idle

# ---------------------------------------------------------------------------------------------
# Exclusions file: the way to exclude resources without write access to tag them. A local file,
# so nothing in Azure changes. Each entry has "id" (exact) or "pattern" (wildcards * and ?), a
# required "reason", and optional "wasteType" (one or a list) and "until" (yyyy-MM-dd; the entry
# stops applying after that day). Matching is case-insensitive. A malformed file stops the scan,
# because silently ignoring it would report everything it was meant to exclude.
# Loaded before any Azure call so a bad file fails fast; applied by Set-Exclusion (lib/Common.ps1).
# ---------------------------------------------------------------------------------------------
if (-not $ExclusionsFile -and -not $FixtureDir -and (Test-Path 'waste-hunter.exclusions.json')) { $ExclusionsFile = 'waste-hunter.exclusions.json' }
$Exclusions = @(); $ExpiredExclusions = @()
# A config error is printed whole on one line (PowerShell's concise error view cuts long messages)
try {
if ($ExclusionsFile) {
    if (-not (Test-Path $ExclusionsFile)) { throw "Exclusions file not found: $ExclusionsFile" }
    try { $doc = Get-Content $ExclusionsFile -Raw | ConvertFrom-Json -AsHashtable -DateKind String }
    catch { throw "Exclusions file $ExclusionsFile is not valid JSON: $($_.Exception.Message)" }
    $entries = @((Get-Key $doc 'exclusions') | Where-Object { $null -ne $_ })
    if (-not ($doc -is [System.Collections.IDictionary]) -or -not $doc.Contains('exclusions')) { throw "Exclusions file $ExclusionsFile needs a top-level ""exclusions"" list." }
    $n = 0
    foreach ($e in $entries) {
        $n++
        $where = "Exclusions file entry $n"
        if (-not ($e -is [System.Collections.IDictionary])) { throw "${where}: must be an object." }
        $id = [string] (Get-Key $e 'id'); $pattern = [string] (Get-Key $e 'pattern'); $reason = [string] (Get-Key $e 'reason')
        if ([bool] $id -eq [bool] $pattern) { throw "${where}: needs exactly one of ""id"" or ""pattern""." }
        if (-not $reason.Trim()) { throw "${where} ($id$pattern): needs a ""reason"", so the exclusion is on record." }
        $until = $null; $untilText = [string] (Get-Key $e 'until')
        if ($untilText) {
            $d = [DateTime]::MinValue
            if (-not [DateTime]::TryParseExact($untilText, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles] 'AdjustToUniversal, AssumeUniversal', [ref] $d)) {
                throw "${where} ($id$pattern): ""until"" must be a date like 2027-03-31, got '$untilText'."
            }
            $until = $d.AddDays(1)    # inclusive: applies through the whole "until" day (UTC)
        }
        $x = [pscustomobject] @{ Id = $id.ToLower(); Pattern = $pattern.ToLower(); Types = @((Get-Key $e 'wasteType') | Where-Object { $_ } | ForEach-Object { [string] $_ })
                                 Reason = $reason.Trim(); Until = $untilText; Label = ($id ? $id : $pattern); Hits = 0 }
        if ($until -and $Now -ge $until) { $ExpiredExclusions += $x } else { $Exclusions += $x }
    }
}
}
catch { [Console]::Error.WriteLine("waste-hunter: $($_.Exception.Message)"); exit 2 }

# ---------------------------------------------------------------------------------------------
# Scope -> passes (one per tenant, since az graph query uses the current tenant's token)
# ---------------------------------------------------------------------------------------------
$accounts = @(Invoke-AzRead @('account', 'list', '--all'))
$original = Invoke-AzRead @('account', 'show')
$enabled  = @($accounts | Where-Object { $_.state -eq 'Enabled' })
$SubName  = @{}; foreach ($a in $accounts) { $SubName[$a.id] = $a.name }
$warnings = [Collections.Generic.List[string]]::new()
foreach ($d in @($accounts | Where-Object { $_.state -ne 'Enabled' })) { $warnings.Add("Skipped subscription '$($d.name)' ($($d.id)): state $($d.state).") }

$passes = @()
switch ($PSCmdlet.ParameterSetName) {
    'Tenant' {
        $tenantIds = if ($AllTenants) { @($enabled | ForEach-Object { $_.tenantId } | Sort-Object -Unique) }
                     elseif ($Tenant) { $Tenant } else { @($original.tenantId) }
        foreach ($t in $tenantIds) {
            $subs = @($enabled | Where-Object { $_.tenantId -eq $t } | ForEach-Object { $_.id })
            if ($subs) { $passes += @{ TenantId = $t; Subscriptions = $subs; Mg = $null } }
            else { $warnings.Add("Tenant ${t}: no enabled subscriptions visible, skipped.") }
        }
        $ScopeLabel = $AllTenants ? 'all reachable tenants' : "tenant(s) $($tenantIds -join ', ')"
    }
    'Subscriptions' {
        $resolved = foreach ($s in $Subscription) {
            $m = @($accounts | Where-Object { $_.id -eq $s -or $_.name -eq $s })
            if (-not $m) { throw "Subscription '$s' not found in 'az account list --all'." }
            if ($m[0].state -ne 'Enabled') { $warnings.Add("Subscription '$s' is $($m[0].state), skipped."); continue }
            $m[0]
        }
        foreach ($g in @($resolved | Group-Object { $_.tenantId })) {
            $passes += @{ TenantId = $g.Name; Subscriptions = @($g.Group | ForEach-Object { $_.id }); Mg = $null }
        }
        $ScopeLabel = "subscriptions $(@($resolved | ForEach-Object { $_.name }) -join ', ')"
    }
    'ManagementGroup' {
        $passes += @{ TenantId = $original.tenantId; Subscriptions = @(); Mg = $ManagementGroup }
        $ScopeLabel = "management group $ManagementGroup"
    }
}
if (-not $passes) { throw 'Nothing to scan: no enabled subscriptions in scope.' }

# ---------------------------------------------------------------------------------------------
# Scan
# ---------------------------------------------------------------------------------------------
$queryFiles    = @(Get-ChildItem $QueryDir -Filter '*.kql' | Sort-Object Name)
$CoverageQuery = Join-Path $PSScriptRoot 'coverage-check.kql'
$RgOwnerQuery  = Join-Path $PSScriptRoot 'rg-owners.kql'
$RgOwners      = @{}

# What each query can report, read from its `wasteType = '...'`, plus the extra types some candidate
# checks produce. Used to tell "resolved" from "not rechecked" when a query fails.
$DerivedTypes = @{}
foreach ($t in @($WasteTypes.Values | Where-Object { $_['Parent'] })) { $DerivedTypes[$t.Parent] = @($DerivedTypes[$t.Parent]) + $t.Name | Where-Object { $_ } }
$QueryWasteTypes = @{}
foreach ($qf in $queryFiles) {
    $ts = @([regex]::Matches((Get-Content $qf.FullName -Raw), "wasteType\s*=\s*'([^']+)'") | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    $QueryWasteTypes[$qf.BaseName] = @($ts + @($ts | ForEach-Object { $DerivedTypes[$_] } | Where-Object { $_ }))
}
$ScannedSubs     = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$UnverifiedTypes = [Collections.Generic.HashSet[string]]::new()
$UncheckedIds    = [Collections.Generic.HashSet[string]]::new()
$rowsAll    = [Collections.Generic.List[object]]::new()
$coverage   = [Collections.Generic.List[object]]::new()
$queryStats = [ordered]@{}
$billed     = @{}
$idleInfo   = @{}
$CandidateStats = @{}
$activeSub  = $original.id
$EnabledIds = [Collections.Generic.HashSet[string]]::new([string[]] @($enabled | ForEach-Object { $_.id }), [StringComparer]::OrdinalIgnoreCase)

try {
    foreach ($p in $passes) {
        $status = 'ok'; $errors = @(); $p.Visible = 0
        $passRows = [Collections.Generic.List[object]]::new()
        try {
            $ctxSub = $p.Mg ? $original.id : (($p.Subscriptions -contains $activeSub) ? $activeSub : $p.Subscriptions[0])
            if ($ctxSub -ne $activeSub) { Invoke-AzRead @('account', 'set', '--subscription', $ctxSub) | Out-Null; $activeSub = $ctxSub }

            # Coverage check. Resource Graph silently drops subscriptions the token can't read, so
            # "0 rows" proves nothing until we know which subscriptions it actually saw.
            $subRows = Invoke-GraphQuery $CoverageQuery $p.Subscriptions $p.Mg     # a List; enumerate it, don't pipe it whole
            $visible = @(foreach ($sr in $subRows) { [string] $sr.subscriptionId })
            $p.Visible = $visible.Count
            foreach ($v in $visible) { [void] $ScannedSubs.Add($v) }
            if ($p.Subscriptions) {
                $missing = @($p.Subscriptions | Where-Object { $_ -notin $visible })
                if ($missing.Count -eq $p.Subscriptions.Count) { throw "Resource Graph can't see any of the $($missing.Count) subscription(s) in this tenant. Check login and permissions (az login --tenant $($p.TenantId))." }
                foreach ($m in $missing) { $errors += "Resource Graph can't see subscription '$($SubName[$m] ?? $m)'. Its results are missing." }
            }
            elseif (-not $visible) { throw "Resource Graph returned no subscriptions under management group $($p.Mg)." }

            # Resource group owner tags, the fallback for findings whose resource has no owner tag
            try { foreach ($o in (Invoke-GraphQuery $RgOwnerQuery $p.Subscriptions $p.Mg)) { $RgOwners["$($o.subscriptionId)|$($o.resourceGroup)".ToLower()] = [string] $o.owner } }
            catch { $warnings.Add("Couldn't read resource group owner tags in tenant $($p.TenantId): $($_.Exception.Message)") }

            foreach ($qf in $queryFiles) {
                try {
                    Write-Host "  [$($p.TenantId.Substring(0,8))] $($qf.Name) ..." -NoNewline
                    $rows = Invoke-GraphQuery $qf.FullName $p.Subscriptions $p.Mg
                    $rows = @($rows | Where-Object { $EnabledIds.Contains([string] $_.subscriptionId) })
                    Write-Host " $($rows.Count) rows"
                    $prev = $queryStats[$qf.BaseName]
                    $queryStats[$qf.BaseName] = (($prev -is [int]) ? $prev : 0) + $rows.Count
                    foreach ($r in $rows) { $passRows.Add($r) }
                }
                catch {
                    Write-Host ' FAILED'; $errors += "$($qf.Name): $($_.Exception.Message)"; $queryStats[$qf.BaseName] = 'FAILED'
                    foreach ($t in @($QueryWasteTypes[$qf.BaseName])) { [void] $UnverifiedTypes.Add($t) }
                }
            }
            $queryErrors = @($errors | Where-Object { $_ -like '*.kql:*' }).Count
            if ($queryErrors -eq $queryFiles.Count) { $status = 'failed' } elseif ($errors) { $status = 'partial' }

            # Confirm metric-based candidates ($CandidateTypes) in this tenant's context. A candidate
            # becomes 0..n findings; one the metrics show is in use is dropped. Ignored rows are kept
            # so they still count as excluded.
            # Exclusions (tag or file) apply before the metric checks, so excluded candidates cost no az calls
            foreach ($row in $passRows) { Set-Exclusion $row }
            $cands = @($passRows | Where-Object { $_.wasteType -in $CandidateTypes -and -not [bool] $_.ignored })
            if ($cands -and -not $SkipMetrics) { Write-Host "  checking $($cands.Count) candidate(s) against 30 days of metrics ..." }
            # Checks run -Parallel at a time; results come back in candidate order.
            $checks = $SkipMetrics ? @() : @(Invoke-InParallel $cands 'Confirm-Candidate')
            $confirmed = [Collections.Generic.List[object]]::new()
            $j = 0
            foreach ($row in $passRows) {
                if ($row.wasteType -notin $CandidateTypes -or [bool] $row.ignored) { $confirmed.Add($row); continue }
                if (-not $CandidateStats.ContainsKey($row.wasteType)) { $CandidateStats[$row.wasteType] = @{ checked = 0; flagged = 0; skipped = 0; failed = 0 } }
                $st = $CandidateStats[$row.wasteType]
                if ($SkipMetrics) { $st.skipped++; [void] $UncheckedIds.Add(([string] $row.id).ToLower()); continue }
                $st.checked++
                $c = $checks[$j++]
                if ($c.Error) {
                    $st.failed++; [void] $UncheckedIds.Add(([string] $row.id).ToLower())
                    $warnings.Add("Couldn't check $($row.name) ($($row.wasteType)), so it's not in this report: $($c.Error)")
                    continue
                }
                foreach ($fnd in @($c.Value)) { if ($fnd) { $confirmed.Add($fnd); $st.flagged++ } }
            }
            $passRows = $confirmed
            # ...and again after, for findings a check creates (an OpenAI deployment, Hot blobs on an account)
            foreach ($row in $passRows) { Set-Exclusion $row }

            # Idle time for stopped VMs (needs this tenant's context)
            $vms = @($passRows | Where-Object { $_.wasteType -eq 'vm-stopped-not-deallocated' -and -not $_.ignored })
            if ($vms -and -not $SkipMetrics) {
                $acts = @(Invoke-InParallel @($vms | ForEach-Object { $_.id }) 'Get-LastCpuActivity')
                for ($k = 0; $k -lt $vms.Count; $k++) {
                    if ($acts[$k].Error) { $warnings.Add("Metrics unavailable for $($vms[$k].name): $($acts[$k].Error)") }
                    else { $idleInfo[$vms[$k].id.ToLower()] = @($acts[$k].Value)[0] }
                }
            }

            # Billed cost, only for subscriptions that have findings
            if (-not $SkipConsumption) {
                $subsWithFindings = @($passRows | Where-Object { -not $_.ignored } | ForEach-Object { $_.subscriptionId } | Sort-Object -Unique)
                foreach ($s in $subsWithFindings) {
                    try { Write-Host "  consumption $s ..." -NoNewline; $n = Add-BilledCosts $s $billed; Write-Host " $n usage rows" }
                    catch { Write-Host ' unavailable'; $warnings.Add("Billed cost unavailable for '$($SubName[$s] ?? $s)', using estimates: $($_.Exception.Message)") }
                }
            }
        }
        catch { $status = 'failed'; $errors += $_.Exception.Message }

        foreach ($r in $passRows) { $rowsAll.Add($r) }
        $coverage.Add([ordered]@{
            Tenant = $p.TenantId
            Scope = ($p.Mg ? "MG $($p.Mg) ($($p.Visible ?? 0) subscription(s) visible)" : "$($p.Visible ?? 0) of $($p.Subscriptions.Count) subscription(s) visible")
            Subscriptions = @($p.Subscriptions | ForEach-Object { $SubName[$_] ?? $_ }) -join ', '
            Status = $status; Errors = $errors
        })
    }
}
finally {
    if ($activeSub -ne $original.id) {
        try { Invoke-AzRead @('account', 'set', '--subscription', $original.id) | Out-Null }
        catch { Write-Warning "Could not restore default subscription $($original.id): $($_.Exception.Message)" }
    }
}

# ---------------------------------------------------------------------------------------------
# Findings: exclusions, Advisor merge, idle time, cost, actions
# ---------------------------------------------------------------------------------------------
# Report labels, in report order
$TypeInfo = [ordered]@{}; foreach ($t in $WasteTypes.Values) { $TypeInfo[$t.Name] = $t.Label }
$ConfRank = @{ high = 0; medium = 1; low = 2 }

$excluded = @{}
foreach ($r in $rowsAll) { if ([bool] $r.ignored) { $excluded[$r.wasteType] = ($excluded[$r.wasteType] ?? 0) + 1 } }
$excludedRows = @($rowsAll | Where-Object { [bool] $_.ignored })
$exclByFile = @($excludedRows | Where-Object { (Get-Key $_ 'excludedBy') -eq 'file' }).Count
foreach ($x in $ExpiredExclusions) { $warnings.Add("Exclusion for '$($x.Label)' expired on $($x.Until) ($($x.Reason)), so its findings are reported again. Extend or remove it in the exclusions file.") }
foreach ($x in @($Exclusions | Where-Object { $_.Hits -eq 0 })) { $warnings.Add("Exclusion for '$($x.Label)' matched nothing in this scan (resource gone, out of scope, or a typo). Remove it if it's no longer needed.") }

$live     = @($rowsAll | Where-Object { -not [bool] $_.ignored })
# Deduplicated by waste type + ID (the finding key), so the same row seen twice collapses but two
# different waste types on one resource are both kept
$detected = @($live | Where-Object { $_.wasteType -ne 'advisor-cost' } | Group-Object { "$($_.wasteType)|$(([string] $_.id).ToLower())" } | ForEach-Object { $_.Group[0] })
$advisor  = @($live | Where-Object { $_.wasteType -eq 'advisor-cost' })
$advByRes = @{}
foreach ($a in $advisor) { $k = ([string] $a.id).ToLower(); if (-not $advByRes[$k]) { $advByRes[$k] = @() }; $advByRes[$k] += $a }
$consumed = [Collections.Generic.HashSet[string]]::new()

# Billing tier of a managed disk (P30, E10, S20, ...). properties.tier when set (premium performance
# tiers), otherwise the smallest tier that fits the size. $null for per-GiB disks (Premium SSD v2, Ultra).

# Monthly list price in the resource's own region, from the Retail Prices API. $null means no
# regional price was found, so the caller falls back to Get-Estimate.

# Load Balancer and NAT Gateway list prices are published per zone ('Global', 'US Gov'), not per region

# One meter's price in $Currency, or $null when not found. The API rounds very small per-second
# prices to 0 in every currency except USD (Container Apps idle: USD 0.000003, CAD 0), so a zero
# price that's non-zero in USD is replaced by USD x the price-list exchange rate.

# Shared cost formulas, used with live prices and with pricing.json fallbacks

# Waste types whose saving is a tier change (a price difference), not the resource's whole bill.
# Log Analytics findings for retention only are marked per finding (partialSaving).
$PartialSavingTypes = @($WasteTypes.Values | Where-Object { $_['PartialSaving'] } | ForEach-Object { $_.Name })

# Waste types whose cost a reservation or savings plan can cover
$CommitmentEligible = @($WasteTypes.Values | Where-Object { $_['CommitmentEligible'] } | ForEach-Object { $_.Name })

# Sovereign clouds have their own portals
$PortalHost = @{ AzureUSGovernment = 'portal.azure.us'; AzureChinaCloud = 'portal.azure.cn' }[[string] $original.environmentName] ?? 'portal.azure.com'

$findings = [Collections.Generic.List[object]]::new()
foreach ($r in @($detected) + @($advisor)) {
    $key = ([string] $r.id).ToLower()
    if ($r.wasteType -eq 'advisor-cost' -and $consumed.Contains([string] $r.recommendationId)) { continue }

    $f = [ordered]@{}; foreach ($k in $r.Keys) { $f[$k] = $r[$k] }
    $f.advisorMonthly = $null; $f.advisorCurrency = ''

    if ($r.wasteType -eq 'advisor-cost') {
        $f.advisorMonthly = $r.monthlySavings; $f.advisorCurrency = $r.currency
    }
    # A recommendation merges into the first finding for its resource only, so a resource with two
    # waste types doesn't count Advisor's saving twice
    elseif (($recs = @($advByRes[$key] | Where-Object { $_ -and -not $consumed.Contains([string] $_.recommendationId) }))) {
        foreach ($a in $recs) { [void] $consumed.Add([string] $a.recommendationId) }
        $sum = ($recs | ForEach-Object { [double] ($_.monthlySavings ?? 0) } | Measure-Object -Sum).Sum
        if ($sum -gt 0) { $f.advisorMonthly = $sum; $f.advisorCurrency = $recs[0].currency }
        $f.confidence = Step-Confidence $f.confidence
        $advText = @($recs | ForEach-Object { $_.reason -replace '^Advisor \([^)]*\): ', '' }) -join ' / '
        $f.reason += "; corroborated by Advisor: $advText"
    }

    # Idle time for stopped VMs
    if ($r.wasteType -eq 'vm-stopped-not-deallocated') {
        $ii = $idleInfo[$key]
        if ($SkipMetrics -or -not $ii) { $f.idleSource = 'not measured' }
        elseif ($ii.Last) { $f.idleDays = [int] [math]::Floor(($Now - $ii.Last).TotalDays); $f.idleSource = "last CPU datapoint $($ii.Last.ToString('yyyy-MM-dd'))" }
        elseif ($null -ne $r.ageDays -and [int] $r.ageDays -lt $ii.Window) { $f.idleDays = [int] $r.ageDays; $f.idleSource = 'no CPU data since creation' }
        else { $f.idleDays = $ii.Window; $f.idleSource = "no CPU data in last $($ii.Window) days ($($ii.Window)+)" }
    }

    # Cost order: billed, then Advisor, then list-price estimate
    # (An Advisor-only finding uses Advisor's savings figure. The resource's full bill is not what it saves.)
    # A partial-saving finding (a tier change, or retention only) saves a delta, not the resource's
    # whole bill, so its billed cost is context only and never the saving.
    $b = ($r.wasteType -ne 'advisor-cost') ? $billed[$key] : $null
    $partial = ($r.wasteType -in $PartialSavingTypes) -or [bool] (Get-Key $f 'partialSaving')
    $billedWhole = ($b -and $b.Days.Count -gt 0) ? @{ Cost = [math]::Round($b.Cost / $b.Days.Count * 30, 2); Currency = $b.Currency } : $null
    if ($partial) { $b = $null }
    if ($b -and $b.Days.Count -gt 0) {
        $f.monthlyCost = [math]::Round($b.Cost / $b.Days.Count * 30, 2); $f.currency = $b.Currency
        $f.costSource = "billed (30-day actual, $($b.Days.Count) day(s) of usage)"
    }
    elseif ($null -ne $f.advisorMonthly) {
        $f.monthlyCost = [math]::Round([double] $f.advisorMonthly, 2); $f.currency = $f.advisorCurrency ? $f.advisorCurrency : 'USD'; $f.costSource = 'advisor'
    }
    else {
        $lp = Get-LivePrice $f
        if ($lp) {
            $f.monthlyCost = [math]::Round([double] $lp.Cost, 2); $f.currency = $Currency
            $f.costSource = "estimated ($($lp.Note), Retail Prices API)"
            if ($lp.Cost -gt 0) { $PriceStats.live++ }
        }
        else {
            $e = Get-Estimate $f
            $f.monthlyCost = ($null -ne $e.Cost) ? [math]::Round([double] $e.Cost, 2) : $null
            $f.currency = $Pricing.currency
            if ($null -eq $e.Cost) { $f.costSource = "unknown ($($e.Note))" }
            elseif ($e.Cost -gt 0) { $f.costSource = "estimated ($($e.Note), pricing.json US East USD)"; $PriceStats.fallback++ }
            else { $f.costSource = "free ($($e.Note))"; $f.currency = $Currency }   # zero is zero in any currency
        }
    }
    if ($partial -and $billedWhole) {
        $f.costSource += ' [whole resource billed {0:N2} {1}/month; this change saves only part of it]' -f $billedWhole.Cost, $billedWhole.Currency
    }

    # Reservations and savings plans: an estimated (list-price) saving on a type they can cover may
    # overstate the real saving, because a commitment is prepaid. Billed cost already reflects them.
    # Reservations aren't readable with the allowed commands, so this is a caveat, not a match.
    $f.commitmentCaveat = ([string] $f.costSource -like 'estimated*') -and ($f.wasteType -in $CommitmentEligible) -and [double] ($f.monthlyCost ?? 0) -gt 0

    # Owner: the resource's own tag, else its resource group's owner tag
    $f.ownerSource = $f.owner ? 'resource tag' : ''
    if (-not $f.owner) {
        $rgo = $RgOwners["$($f.subscriptionId)|$($f.resourceGroup)".ToLower()]
        if ($rgo) { $f.owner = $rgo; $f.ownerSource = 'resource group tag' }
    }

    $act = Get-Action $f
    $f.suggestedAction = $act[0]; $f.referenceCommand = $act[1]
    $f.subscriptionName = $SubName[[string] $r.subscriptionId] ?? ''
    $f.portalUrl = "https://$PortalHost/#@$($r.tenantId)/resource$($r.id)"
    $f.createdTime = Format-Day $r.createdTime
    $findings.Add($f)
}

# Ranking value: monthly cost converted to $Currency, so a USD amount and a CAD amount compare
# fairly. Display amounts stay in their original currency.
# Conversion is only needed when non-zero amounts are in more than one currency. Otherwise raw ranking is exact.
$fxUsed = @{}; $fxMissing = [Collections.Generic.HashSet[string]]::new()
$nonZeroCurrencies = @($findings | Where-Object { [double] ($_.monthlyCost ?? 0) -ne 0 -and $_.currency } | ForEach-Object { $_.currency } | Sort-Object -Unique)
foreach ($f in $findings) {
    $c = [double] ($f.monthlyCost ?? 0)
    if ($nonZeroCurrencies.Count -le 1 -or $c -eq 0 -or -not $f.currency -or $f.currency -eq $Currency) { $f.rankValue = $c; continue }
    $rate = Get-FxRate $f.currency
    if ($null -eq $rate) { [void] $fxMissing.Add($f.currency); $f.rankValue = $c }
    else { $fxUsed[$f.currency] = $rate; $f.rankValue = $c * $rate }
}
if ($fxMissing.Count) {
    $warnings.Add("No exchange rate available for $(@($fxMissing) -join ', ') to $Currency, so findings in different currencies were ranked by their raw amounts. The order between them is approximate.")
}

# Rank: within each type by converted cost, then confidence; types by converted total
$groups = foreach ($t in $TypeInfo.Keys) {
    $items = @($findings | Where-Object { $_.wasteType -eq $t } |
        Sort-Object @{ e = { [double] $_.rankValue }; Descending = $true }, @{ e = { $ConfRank[$_.confidence] } })
    [pscustomobject] @{ Type = $t; Label = $TypeInfo[$t]; Items = $items
        Total = [double] (($items | ForEach-Object { [double] $_.rankValue } | Measure-Object -Sum).Sum) }
}
$groups = @($groups | Sort-Object @{ e = { $_.Items.Count -gt 0 }; Descending = $true }, @{ e = 'Total'; Descending = $true })

# ---------------------------------------------------------------------------------------------
# Changes since the last scan. Each report folder has findings.json. The newest earlier one with the
# same scope (and same real/synthetic mode) is the baseline. A finding missing now is "resolved" only
# if its subscription was read this time and its type was really checked; otherwise it's "not rechecked".
# ---------------------------------------------------------------------------------------------
New-Item -ItemType Directory -Force $OutDir | Out-Null
$OutFull = (Resolve-Path $OutDir).Path
$today = $RunTime.ToString('yyyy-MM-dd')
$prev = $null; $prevDir = $null
$History = [Collections.Generic.List[object]]::new()   # every earlier matching scan, oldest first (for trends)
if ($Compare -ne 'none') {
    $candidates = if ($Compare -ne 'auto') { @(Get-Item $Compare -ErrorAction SilentlyContinue) }
                  else { @(Get-ChildItem (Split-Path -Parent $OutFull) -Directory -ErrorAction SilentlyContinue | Where-Object { $_.FullName -ne $OutFull }) }
    $best = $null
    foreach ($d in $candidates) {
        $fj = Join-Path $d.FullName 'findings.json'
        if (-not (Test-Path $fj)) { continue }
        try { $j = Get-Content $fj -Raw | ConvertFrom-Json -AsHashtable -DateKind String } catch { continue }
        $meta = Get-Key $j 'meta'
        if (-not $meta) { continue }
        if ($Compare -eq 'auto' -and ((Get-Key $meta 'scope') -ne $ScopeLabel -or [bool] (Get-Key $meta 'synthetic') -ne [bool] $FixtureDir)) { continue }
        if ([string] (Get-Key $meta 'generated') -ge $RunTime.ToString('o')) { continue }
        $History.Add(@{ meta = $meta; json = $j; dir = $d.FullName })
        if (-not $best -or [string] (Get-Key $meta 'generated') -gt [string] (Get-Key $best.meta 'generated')) { $best = $History[-1] }
    }
    if ($best) { $prev = $best.json; $prevDir = $best.dir }
    $History = @($History | Sort-Object { [string] (Get-Key $_.meta 'generated') })
}
$excludedKeys = [Collections.Generic.HashSet[string]]::new()
foreach ($r in $rowsAll) { if ([bool] $r.ignored) { [void] $excludedKeys.Add((Get-FindingKey $r)) } }
$prevByKey = @{}
if ($prev) { foreach ($p in @(Get-Key $prev 'findings')) { if ($p) { $prevByKey[[string] $p['key']] = $p } } }
$currentKeys = [Collections.Generic.HashSet[string]]::new()
foreach ($f in $findings) {
    $k = Get-FindingKey $f; [void] $currentKeys.Add($k)
    $p = $prevByKey[$k]
    $f.status = $prev ? ($p ? 'open' : 'new') : 'baseline'
    $f.firstSeen = $p ? [string] $p['firstSeen'] : $today
}
$resolved = @(); $notRechecked = @(); $nowExcluded = @()
foreach ($k in $prevByKey.Keys) {
    if ($currentKeys.Contains($k)) { continue }
    $p = $prevByKey[$k]
    $prevId = ([string] $p['id']).ToLower()    # (not $pid: that's PowerShell's read-only process-ID variable)
    $unchecked = -not $ScannedSubs.Contains([string] $p['subscriptionId']) -or $UnverifiedTypes.Contains([string] $p['wasteType']) -or
                 @($UncheckedIds | Where-Object { $prevId -eq $_ -or $prevId.StartsWith("$_/") }).Count -gt 0 -or   # itself or a child (OpenAI deployments), not '.../st1' for '.../st10'
                 ($SkipMetrics -and ([string] $p['wasteType'] -in ($CandidateTypes + @($DerivedTypes.Values | ForEach-Object { $_ }))))
    if ($excludedKeys.Contains($k)) { $nowExcluded += $p }
    elseif ($unchecked) { $notRechecked += $p }
    else { $resolved += $p }
}

# Trends across every earlier scan of this scope: savings over time, time to resolve, oldest open
$Trend = $prev ? (Get-TrendData $History) : $null

. (Join-Path $PSScriptRoot 'lib/Report.ps1')
