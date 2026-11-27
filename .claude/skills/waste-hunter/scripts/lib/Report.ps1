# Part of Invoke-WasteHunt.ps1: the output section (report.md, report.html, CSVs, findings.json).
# Dot-sourced at the end of the run, in the runner's scope. Writes local files only.

# ---------------------------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------------------------
function Esc([object] $s) { (([string] $s) -replace '\|', '\|' -replace '\r?\n', ' ').Trim() }
function Format-Money([hashtable] $byCur) {
    $parts = @($byCur.GetEnumerator() | Where-Object { $_.Value -ne 0 } | Sort-Object Value -Descending)
    if (-not $parts) { return "0.00 $Currency" }
    (@($parts | ForEach-Object { '{0:N2} {1}' -f $_.Value, $_.Key })) -join ' + '
}
# A group's cost for display: unknown costs say so instead of reading as 0.00
function Format-GroupCost($items) {
    # Drop nulls: an empty list from a pipeline arrives as a single $null
    $items = @($items | Where-Object { $null -ne $_ })
    $unknown = @($items | Where-Object { $null -eq $_.monthlyCost }).Count
    if ($items.Count -and $unknown -eq $items.Count) { return 'cost unknown' }
    $s = Format-Money (Get-Totals $items)
    return $unknown ? "$s + $unknown unknown" : $s
}
function Get-Totals($items) {
    $t = @{}; foreach ($i in @($items)) { if ($null -ne $i.monthlyCost) { $t[$i.currency] = ($t[$i.currency] ?? 0) + [double] $i.monthlyCost } }; $t
}

New-Item -ItemType Directory -Force $OutDir | Out-Null
$rank = 0
$csvRows = foreach ($g in $groups) { foreach ($i in $g.Items) {
    $rank++
    [pscustomobject] [ordered] @{
        rank = $rank; wasteType = $i.wasteType; wasteTypeLabel = $g.Label; name = $i.name; resourceId = $i.id; type = $i.type
        tenantId = $i.tenantId; subscriptionId = $i.subscriptionId; subscriptionName = $i.subscriptionName
        resourceGroup = $i.resourceGroup; location = $i.location; owner = $i.owner; app = $i.app; env = $i.env
        createdTime = $i.createdTime; ageDays = $i.ageDays; idleDays = $i.idleDays; idleSource = $i.idleSource
        sku = $i.sku; sizeGbOrInstances = $i.sizeGb; monthlyCost = $i.monthlyCost; currency = $i.currency; costSource = $i.costSource
        advisorMonthlySavings = $i.advisorMonthly; confidence = $i.confidence; reason = $i.reason
        suggestedAction = $i.suggestedAction; referenceCommandNotExecuted = $i.referenceCommand; portalUrl = $i.portalUrl
        status = $i.status; firstSeen = $i.firstSeen; ownerSource = $i.ownerSource; commitmentCaveat = [bool] $i.commitmentCaveat
    }
} }
# Tag values and names come from Azure and anyone can set them. A cell starting with = + - @ would
# run as a formula when the CSV is opened in Excel, so prefix those with a quote.
foreach ($row in @($csvRows)) {
    foreach ($prop in $row.PSObject.Properties) {
        if ($prop.Value -is [string] -and $prop.Value -match '^[=+\-@\t\r]') { $prop.Value = "'" + $prop.Value }
    }
}
$CsvHeader = '"rank","wasteType","wasteTypeLabel","name","resourceId","type","tenantId","subscriptionId","subscriptionName","resourceGroup","location","owner","app","env","createdTime","ageDays","idleDays","idleSource","sku","sizeGbOrInstances","monthlyCost","currency","costSource","advisorMonthlySavings","confidence","reason","suggestedAction","referenceCommandNotExecuted","portalUrl","status","firstSeen","ownerSource","commitmentCaveat"'
# excluded.csv: what was left out and why, for the record (no cost: excluded resources aren't priced)
$exclCsv = @(foreach ($x in $excludedRows) { [pscustomobject] [ordered] @{ wasteType = $x.wasteType; name = $x.name; resourceId = $x.id; subscriptionId = $x.subscriptionId
    resourceGroup = $x.resourceGroup; excludedBy = (Get-Key $x 'excludedBy'); reason = (Get-Key $x 'excludeReason'); until = (Get-Key $x 'excludeUntil') } })
foreach ($row in $exclCsv) { foreach ($prop in $row.PSObject.Properties) { if ($prop.Value -is [string] -and $prop.Value -match '^[=+\-@	
]') { $prop.Value = "'" + $prop.Value } } }
$exclPath = Join-Path $OutDir 'excluded.csv'
if ($exclCsv) { $exclCsv | Export-Csv $exclPath -Encoding utf8 } else { Set-Content $exclPath '"wasteType","name","resourceId","subscriptionId","resourceGroup","excludedBy","reason","until"' -Encoding utf8 }
$csvPath = Join-Path $OutDir 'findings.csv'
@($csvRows) | Export-Csv $csvPath -Encoding utf8
if (-not $csvRows) { Set-Content $csvPath $CsvHeader -Encoding utf8 }

# One CSV per owner, to hand each team its own list. Findings with no owner (resource or resource
# group tag) go to _no-owner.csv.
$ownerDir = Join-Path $OutDir 'by-owner'
New-Item -ItemType Directory -Force $ownerDir | Out-Null
Get-ChildItem $ownerDir -Filter '*.csv' -ErrorAction SilentlyContinue | Remove-Item   # this run's folder only
$ownerGroups = @(@($findings) | Group-Object { $_.owner ? ([string] $_.owner).Trim().ToLower() : '' } | ForEach-Object {
    $items = @($_.Group)
    $slug = $_.Name ? ($_.Name -replace '[^a-z0-9@._-]', '-') : '_no-owner'
    $keys = [Collections.Generic.HashSet[string]]::new([string[]] @($items | ForEach-Object { Get-FindingKey $_ }))
    @($csvRows | Where-Object { $keys.Contains("$($_.wasteType)|$(([string] $_.resourceId).ToLower())") }) | Export-Csv (Join-Path $ownerDir "$slug.csv") -Encoding utf8
    [pscustomobject] @{ Owner = $_.Name; File = "by-owner/$slug.csv"; Items = $items
        Rank = [double] (($items | ForEach-Object { [double] $_.rankValue } | Measure-Object -Sum).Sum)
        High = @($items | Where-Object { $_.confidence -eq 'high' }).Count
        FromRg = @($items | Where-Object { $_.ownerSource -eq 'resource group tag' }).Count }
} | Sort-Object @{ e = { [bool] $_.Owner }; Descending = $true }, @{ e = 'Rank'; Descending = $true })

# Machine-readable record: the baseline for the next scan's "changes since last scan"
$record = [ordered]@{
    meta = [ordered]@{ generated = $RunTime.ToString('o'); scope = $ScopeLabel; currency = $Currency; synthetic = [bool] $FixtureDir
                       scannedSubscriptions = @($ScannedSubs)
                       # What changed against the baseline (absent on a baseline scan); read by later scans' trends
                       changes = $prev ? [ordered]@{ new = @($findings | Where-Object { $_.status -eq 'new' }).Count; open = @($findings | Where-Object { $_.status -eq 'open' }).Count
                                                     resolved = @($resolved).Count; notRechecked = @($notRechecked).Count; nowExcluded = @($nowExcluded).Count } : $null }
    # Findings this scan resolved (gone, and rechecked), with when they were first seen: time to resolve
    resolved = @(foreach ($p in @($resolved | Where-Object { $null -ne $_ })) { [ordered]@{ key = $p['key']; wasteType = $p['wasteType']; name = $p['name']; owner = $p['owner']
        monthlyCost = $p['monthlyCost']; currency = $p['currency']; firstSeen = $p['firstSeen']; resolvedOn = $today } })
    findings = @(foreach ($i in $findings) { [ordered]@{ key = Get-FindingKey $i; wasteType = $i.wasteType; id = $i.id; name = $i.name
        subscriptionId = $i.subscriptionId; resourceGroup = $i.resourceGroup; owner = $i.owner
        monthlyCost = $i.monthlyCost; currency = $i.currency; confidence = $i.confidence; firstSeen = $i.firstSeen } })
}
$record | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $OutDir 'findings.json') -Encoding utf8

# trends.csv: one row per scan (amounts per currency, as "120.00 CAD + 35.00 USD"), for charting
if ($Trend) {
    @($Trend.Scans | ForEach-Object { [pscustomobject] [ordered] @{ date = $_.Date; folder = $_.Folder; findings = $_.Findings
        estimatedMonthly = (Format-Money $_.Totals); highConfidence = (Format-Money $_.High); new = $_.New; resolved = $_.Resolved } }) |
        Export-Csv (Join-Path $OutDir 'trends.csv') -Encoding utf8
}

$md = [Text.StringBuilder]::new()
function L([string] $s = '') { [void] $md.AppendLine($s) }
$totals = Get-Totals $findings
$exclTotal = ($excluded.Values | Measure-Object -Sum).Sum
L '# Azure waste report'
L ''
L "## Estimated monthly savings: **$(Format-Money $totals)**"
L ''
# The headline adds every finding, including low-confidence ones whose advice may be "keep it", so
# show the high-confidence part separately.
$highTotals = Get-Totals @($findings | Where-Object { $_.confidence -eq 'high' })
L "High confidence: **$(Format-Money $highTotals)**. The rest needs a check before acting (see each finding's confidence and reason)."
L ''
$exclSource = $ExclusionsFile ? ('the exclusions file `{0}`' -f (Split-Path $ExclusionsFile -Leaf)) : 'an exclusions file (none used)'
L "$($findings.Count) finding(s) across $(@($groups | Where-Object { $_.Items.Count }).Count) waste type(s). $([int] $exclTotal) resource(s) excluded ($([int] $exclTotal - $exclByFile) by the ``waste-hunter:ignore=true`` tag, $exclByFile by $exclSource; listed in ``excluded.csv``)."
L ''
L "Generated $($RunTime.ToString('yyyy-MM-dd HH:mm')) UTC. Scope: $ScopeLabel. **Read-only scan: nothing in Azure was changed.**"
if ($FixtureDir) { L ''; L "> **SYNTHETIC DEMO DATA** loaded from ``$(Split-Path $FixtureDir -Leaf)``. No Azure calls were made and these resources are not real." }
L ''
L '| Waste type | Findings | Est. monthly | High | Medium | Low | Excluded |'
L '|---|---:|---:|---:|---:|---:|---:|'
foreach ($t in $TypeInfo.Keys) {
    $g = $groups | Where-Object { $_.Type -eq $t }
    $c = @{}; foreach ($lvl in 'high', 'medium', 'low') { $c[$lvl] = @($g.Items | Where-Object { $_.confidence -eq $lvl }).Count }
    $gc = $g.Items.Count ? (Format-GroupCost $g.Items) : '-'
    L "| $($TypeInfo[$t]) | $($g.Items.Count) | $gc | $($c.high) | $($c.medium) | $($c.low) | $($excluded[$t] ?? 0) |"
}
L ''
$priceMode = $OfflinePricing ? "offline: ``scripts/pricing.json`` (US East, USD)" : "pay-as-you-go list prices for each resource's own region, in $Currency, from the Azure Retail Prices API, with ``scripts/pricing.json`` (US East, USD) as the fallback"
L "**Cost sources:** *billed* is the actual 30-day cost from the Consumption API, scaled to 30 days. *advisor* is Azure Advisor's monthly savings estimate. *estimated* is $priceMode. Snapshot estimates are upper bounds. Advisor recommendations that match a finding above are merged into it and not counted twice."
$caveatCount = @($findings | Where-Object { $_.commitmentCaveat }).Count
if ($caveatCount) {
    L ''
    L "**† Reservations and savings plans:** $caveatCount estimated cost(s) are for resources a reservation or savings plan can cover. If one covers them, the commitment is already paid, so the bill drops by less than shown (the unused commitment shifts elsewhere or is wasted). Check Reservations in the portal before counting these savings. Billed costs already reflect commitments."
}
if ($fxUsed.Count) {
    $rates =(@($fxUsed.GetEnumerator() | Sort-Object Key | ForEach-Object { '1 {0} = {1:N4} {2}' -f $_.Key, $_.Value, $Currency })) -join ', '
    L ''
    L "**Ranking across currencies:** amounts are shown in their original currency, but findings are ranked after converting them to $Currency at the rate implied by Microsoft's price list ($rates)."
}
L ''

L '## Changes since the last scan'
L ''
if (-not $prev) {
    L 'No earlier scan of this scope to compare with, so this report is the baseline. The next scan will show what is new, still open and resolved.'
}
else {
    $prevWhen = [DateTimeOffset]::Parse([string] (Get-Key (Get-Key $prev 'meta') 'generated'), [Globalization.CultureInfo]::InvariantCulture).UtcDateTime
    $newItems = @($findings | Where-Object { $_.status -eq 'new' }); $openItems = @($findings | Where-Object { $_.status -eq 'open' })
    $asItems = { param($list) @($list | ForEach-Object { @{ monthlyCost = $_['monthlyCost']; currency = $_['currency'] } }) }
    L "Compared with the scan of $($prevWhen.ToString('yyyy-MM-dd HH:mm')) UTC (``$(Split-Path $prevDir -Leaf)``)."
    L ''
    L '| | Findings | Est. monthly |'
    L '|---|---:|---:|'
    L "| New since then | $($newItems.Count) | $(Format-GroupCost $newItems) |"
    L "| Still open | $($openItems.Count) | $(Format-GroupCost $openItems) |"
    L "| **Resolved** (gone, and rechecked this time) | $($resolved.Count) | $(Format-GroupCost (& $asItems $resolved)) |"
    if ($nowExcluded) { L "| Now excluded (ignore tag or exclusions file) | $($nowExcluded.Count) | $(Format-GroupCost (& $asItems $nowExcluded)) |" }
    if ($notRechecked) { L "| Not rechecked this time (scope, query or metric check incomplete) | $($notRechecked.Count) | $(Format-GroupCost (& $asItems $notRechecked)) |" }
    L ''
    if ($resolved) {
        L ('**Resolved:** ' + ((@($resolved | Sort-Object { -[double] ($_['monthlyCost'] ?? 0) } | ForEach-Object {
            $c = ($null -ne $_['monthlyCost']) ? (' ({0:N2} {1}/month)' -f [double] $_['monthlyCost'], $_['currency']) : ''
            "$(Esc $_['name']) [$($TypeInfo[[string] $_['wasteType']] ?? $_['wasteType'])]$c" })) -join '; ') + '.')
        L ''
    }
    if ($newItems) {
        L ('**New:** ' + ((@($newItems | Sort-Object { -[double] $_.rankValue } | Select-Object -First 15 | ForEach-Object { "$(Esc $_.name) [$($TypeInfo[$_.wasteType])]" })) -join '; ') + $(($newItems.Count -gt 15) ? '; ...' : '') + '. New findings are marked *new* in the tables below.')
        L ''
    }
}
L ''

if ($Trend) {
    $shown = @($Trend.Scans | Select-Object -Last 13)
    L '## Trends'
    L ''
    L "$($Trend.Scans.Count) scan(s) of this scope$(($Trend.Scans.Count -gt $shown.Count) ? ", last $($shown.Count) shown (all in ``trends.csv``)" : ' (also in `trends.csv`)')."
    L ''
    L '| Scan | Findings | Est. monthly | High confidence | New | Resolved |'
    L '|---|---:|---:|---:|---:|---:|'
    foreach ($sc in $shown) {
        $label = $sc.Current ? "**$($sc.Date) (this scan)**" : "$($sc.Date) <sub>$(Esc $sc.Folder)</sub>"
        L "| $label | $($sc.Findings) | $(Format-Money $sc.Totals) | $(Format-Money $sc.High) | $($sc.New ?? '-') | $($sc.Resolved ?? '-') |"
    }
    L ''
    if ($Trend.ResolvedTimed) {
        L "**Time to resolve:** median $($Trend.MedianDays) day(s) from first seen to resolved, over $($Trend.ResolvedTimed) resolved finding(s)."
        $owners = @($Trend.ByOwner | Select-Object -First 10)
        if ($owners.Count -gt 1 -or ($owners.Count -eq 1 -and $owners[0].Owner)) {
            L ''
            L '| Owner | Resolved | Median days to resolve |'
            L '|---|---:|---:|'
            foreach ($o in $owners) { L "| $($o.Owner ? (Esc $o.Owner) : '**no owner tag**') | $($o.Count) | $($o.MedianDays) |" }
        }
        L ''
    }
    if ($Trend.Oldest) {
        L ('**Open longest:** ' + ((@($Trend.Oldest | ForEach-Object {
            $c = ($null -ne $_.MonthlyCost) ? (', {0:N2} {1}/month' -f [double] $_.MonthlyCost, $_.Currency) : ''
            "$(Esc $_.Name) [$($TypeInfo[[string] $_.WasteType] ?? $_.WasteType)] open $($_.Days) day(s) since $($_.FirstSeen)$c$(($_.Owner) ? ", $(Esc $_.Owner)" : '')" })) -join '; ') + '.')
        L ''
    }
}

if ($ownerGroups) {
    L '## By owner'
    L ''
    L 'From the `owner` tag (or `createdBy`) on the resource, falling back to its resource group''s tag. Each owner has a CSV in `by-owner/` to send them.'
    L ''
    L '| Owner | Findings | High confidence | Est. monthly | List |'
    L '|---|---:|---:|---:|---|'
    foreach ($o in $ownerGroups) {
        $who = $o.Owner ? (Esc $o.Owner) : '**no owner tag**'
        $note = $o.FromRg ? " <sub>($($o.FromRg) via resource group tag)</sub>" : ''
        L "| $who$note | $($o.Items.Count) | $($o.High) | $(Format-GroupCost $o.Items) | ``$($o.File)`` |"
    }
    $unowned = @($findings | Where-Object { -not $_.owner -and [double] $_.rankValue -gt 0 } | Sort-Object { -[double] $_.rankValue } | Select-Object -First 10)
    if ($unowned) {
        L ''
        L ('**Costly findings with no owner** (tag these to route them): ' + ((@($unowned | ForEach-Object { '{0} ({1:N2} {2})' -f (Esc $_.name), [double] $_.monthlyCost, $_.currency })) -join '; ') + '.')
    }
    L ''
}

foreach ($g in @($groups | Where-Object { $_.Items.Count })) {
    $gcost = Format-GroupCost $g.Items
    $gsuffix = ($gcost -eq 'cost unknown') ? '' : '/month'
    L "## $($g.Label): $($g.Items.Count) finding(s), $gcost$gsuffix"
    L ''
    L '| # | Resource | Subscription / RG | Location | Owner / App / Env | Age / idle | Est. monthly | Confidence | Why | Suggested action (not executed) |'
    L '|---:|---|---|---|---|---|---:|---|---|---|'
    $n = 0
    foreach ($i in $g.Items) {
        $n++
        $tagsCell = (@($i.owner, $i.app, $i.env) | ForEach-Object { $_ ? $_ : '-' }) -join ' / '
        $age = @()
        if ($null -ne $i.ageDays) { $age += "age $($i.ageDays)d" }
        if ($null -ne $i.idleDays) {
            $plus = ([string] $i.idleSource).Contains('+') ? '+' : ''
            $age += "idle $($i.idleDays)d$plus"
        }
        $ageCell = $age ? ($age -join ', ') : 'unknown'
        $dagger = $i.commitmentCaveat ? '†' : ''
        $cost = ($null -ne $i.monthlyCost) ? ('{0:N2} {1}<br><sub>{2}{3}</sub>' -f $i.monthlyCost, $i.currency, ($i.costSource -replace ' \(.*$', ''), $dagger) : 'unknown'
        $statusTag = ($i.status -eq 'new') ? '<br><sub>*new*</sub>' : (($i.status -eq 'open') ? "<br><sub>since $($i.firstSeen)</sub>" : '')
        L ("| $n | [$(Esc $i.name)]($($i.portalUrl))<br><sub>$(Esc $i.type)</sub> | $(Esc ($i.subscriptionName ? $i.subscriptionName : $i.subscriptionId))<br><sub>$(Esc $i.resourceGroup)</sub> | $(Esc $i.location) | $(Esc $tagsCell) | $ageCell | $cost | **$($i.confidence)**$statusTag | $(Esc $i.reason) | $(Esc $i.suggestedAction) |")
    }
    L ''
}
$empty = @($groups | Where-Object { -not $_.Items.Count } | ForEach-Object { $_.Label })
if ($empty) { L "**No findings:** $($empty -join '; ')."; L '' }

L '## Coverage'
L ''
L '| Tenant | Scope | Subscriptions | Status |'
L '|---|---|---|---|'
foreach ($c in $coverage) { L "| ``$($c.Tenant)`` | $($c.Scope) | $(Esc $c.Subscriptions) | $($c.Status) |" }
L ''
L ('Rows returned per query (including ignored): ' + ((@($queryStats.GetEnumerator() | ForEach-Object { "``$($_.Key)`` $($_.Value)" })) -join ', ') + '.')
$azEv = @($AzEvents.ToArray())
$azRetried = @($azEv | Where-Object { $_ -like 'retry|*' })
$retryDetail = $azRetried ? (' (' + ((@($azRetried | Group-Object { $_.Substring(6) } | ForEach-Object { "$($_.Name) x$($_.Count)" })) -join ', ') + ')') : ''
L ''
L "az calls: $(@($azEv | Where-Object { $_ -eq 'call' }).Count), $($azRetried.Count) retried after throttling or a transient error$retryDetail, $(@($azEv | Where-Object { $_ -eq 'cached' }).Count) metric read(s) served from cache. Metric checks ran $Parallel at a time (``-Parallel``)."
if ($CandidateStats.Count) {
    $parts = foreach ($k in $CandidateTypes) { $s = $CandidateStats[$k]; if ($s) {
        $unit = ($k -eq 'idle-openai-deployment') ? 'account(s)' : 'resource(s)'
        "$($TypeInfo[$k]): $($s.checked) $unit checked, $($s.flagged) finding(s)$($s.failed ? ", $($s.failed) failed" : '')$($s.skipped ? ", $($s.skipped) not checked" : '')" } }
    L ''
    L ('Metric checks (a candidate is only reported when 30 days of metrics confirm it): ' + (@($parts) -join '; ') + '.')
}
$notChecked = ($CandidateStats.Values | ForEach-Object { $_.skipped } | Measure-Object -Sum).Sum
if ($notChecked) { $warnings.Add("$notChecked candidate(s) were not checked because of -SkipMetrics. Metric-confirmed waste types ($(@($CandidateTypes | ForEach-Object { $TypeInfo[$_] }) -join '; ')) are missing from this report.") }
if ($PriceStats.fallback -and -not $OfflinePricing) {
    $why = $PriceStats.failedLookups ? " ($($PriceStats.failedLookups) price lookup(s) failed after retries)" : ''
    $warnings.Add("$($PriceStats.fallback) finding(s) priced from pricing.json (US East, USD) because no regional price was available$why.")
}
$errs = @($coverage | ForEach-Object { foreach ($e in $_.Errors) { "``$($_.Tenant)``: $e" } })
if ($errs -or $warnings) {
    L ''; L '**Warnings and errors:**'; L ''
    foreach ($e in $errs) { L "- $(Esc $e)" }
    foreach ($w in $warnings) { L "- $(Esc $w)" }
}
L ''
L "The CSV with every finding, including reference commands, is ``findings.csv`` in this folder. Reference commands are text only. Review them and run them yourself if you decide to act."

$mdPath = Join-Path $OutDir 'report.md'
Set-Content $mdPath $md.ToString() -Encoding utf8

# ---------------------------------------------------------------------------------------------
# report.html: the same report as one self-contained file to share (no external scripts or styles),
# with search, filters and sortable columns. Every value is HTML-encoded.
# ---------------------------------------------------------------------------------------------
function ConvertTo-HtmlText([object] $s) { [System.Net.WebUtility]::HtmlEncode([string] $s) }
$hb = [Text.StringBuilder]::new()
function HL([string] $s) { [void] $hb.AppendLine($s) }
$typeOptions = (@($groups | Where-Object { $_.Items.Count } | ForEach-Object { "<option value=""$(ConvertTo-HtmlText $_.Type)"">$(ConvertTo-HtmlText $_.Label)</option>" })) -join ''
HL '<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">'
HL "<title>Azure waste report</title>"
HL @'
<style>
:root { --bg:#fbfbfa; --fg:#1f2328; --muted:#5f6670; --line:#e3e3e0; --card:#ffffff; --accent:#2f6fde; --high:#1a7f37; --medium:#9a6700; --low:#6e7781; --new:#cf222e; }
@media (prefers-color-scheme: dark) { :root { --bg:#16181c; --fg:#e6e8eb; --muted:#9aa2ad; --line:#2d3139; --card:#1d2026; --accent:#6ea0ff; --high:#4ac26b; --medium:#d4a72c; --low:#8b949e; --new:#ff7b72; } }
* { box-sizing: border-box; } body { margin:0; background:var(--bg); color:var(--fg); font:14px/1.5 system-ui, -apple-system, "Segoe UI", sans-serif; }
main { max-width: 1280px; margin: 0 auto; padding: 24px 16px 48px; } h1 { font-size: 24px; margin: 0 0 4px; } h2 { font-size: 17px; margin: 32px 0 8px; }
.muted { color: var(--muted); } .banner { border:1px solid var(--medium); border-radius:8px; padding:8px 12px; margin:12px 0; }
.tiles { display:grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap:12px; margin:16px 0; }
.tile { background:var(--card); border:1px solid var(--line); border-radius:10px; padding:12px 14px; } .tile b { display:block; font-size:20px; } .tile span { color:var(--muted); font-size:12px; }
.wrap { overflow-x:auto; border:1px solid var(--line); border-radius:10px; background:var(--card); }
table { border-collapse: collapse; width:100%; } th, td { text-align:left; vertical-align:top; padding:7px 10px; border-bottom:1px solid var(--line); }
th { font-size:12px; color:var(--muted); font-weight:600; white-space:nowrap; } th.sort { cursor:pointer; } td.num, th.num { text-align:right; white-space:nowrap; }
tr:last-child td { border-bottom:0; } a { color:var(--accent); text-decoration:none; } a:hover { text-decoration:underline; }
.c-high { color:var(--high); font-weight:600; } .c-medium { color:var(--medium); font-weight:600; } .c-low { color:var(--low); font-weight:600; } .new { color:var(--new); font-size:12px; }
.small { font-size:12px; color:var(--muted); } .controls { display:flex; flex-wrap:wrap; gap:10px 16px; align-items:center; margin:8px 0 10px; }
input[type=search], select { background:var(--card); color:var(--fg); border:1px solid var(--line); border-radius:6px; padding:5px 8px; font:inherit; }
td.why { min-width: 260px; } td.act { min-width: 240px; }
</style></head><body><main>
'@
HL '<h1>Azure waste report</h1>'
HL "<div class=""muted"">Generated $(ConvertTo-HtmlText $RunTime.ToString('yyyy-MM-dd HH:mm')) UTC &middot; Scope: $(ConvertTo-HtmlText $ScopeLabel) &middot; <b>Read-only scan: nothing in Azure was changed.</b></div>"
if ($FixtureDir) { HL '<div class="banner"><b>Synthetic demo data.</b> No Azure calls were made and these resources are not real.</div>' }
HL '<div class="tiles">'
HL "<div class=""tile""><span>Estimated monthly savings</span><b>$(ConvertTo-HtmlText (Format-Money $totals))</b></div>"
HL "<div class=""tile""><span>High confidence</span><b>$(ConvertTo-HtmlText (Format-Money $highTotals))</b></div>"
HL "<div class=""tile""><span>Findings</span><b>$($findings.Count)</b></div>"
HL "<div class=""tile""><span>Excluded (tag or exclusions file)</span><b>$([int] $exclTotal)</b></div>"
if ($prev) { HL "<div class=""tile""><span>Since last scan</span><b>$(@($findings | Where-Object { $_.status -eq 'new' }).Count) new &middot; $($resolved.Count) resolved</b></div>" }
HL '</div>'

HL '<h2>Findings</h2><div class="controls">'
HL '<input type="search" id="q" placeholder="Search name, owner, reason..." aria-label="Search findings">'
HL "<select id=""type"" aria-label=""Waste type""><option value="""">All waste types</option>$typeOptions</select>"
HL '<label><input type="checkbox" class="conf" value="high" checked> high</label><label><input type="checkbox" class="conf" value="medium" checked> medium</label><label><input type="checkbox" class="conf" value="low" checked> low</label>'
HL '<label><input type="checkbox" id="newonly"> new only</label><span class="small" id="count"></span></div>'
HL '<div class="wrap"><table id="t"><thead><tr><th class="sort" data-k="type">Waste type</th><th class="sort" data-k="name">Resource</th><th>Subscription / RG</th><th>Location</th><th class="sort" data-k="owner">Owner</th><th>Age / idle</th><th class="sort num" data-k="cost">Est. monthly</th><th class="sort" data-k="conf">Confidence</th><th>Why</th><th>Suggested action (not executed)</th></tr></thead><tbody>'
$confOrder = @{ high = 0; medium = 1; low = 2 }
foreach ($g in @($groups | Where-Object { $_.Items.Count })) { foreach ($i in $g.Items) {
    $age = @(); if ($null -ne $i.ageDays) { $age += "age $($i.ageDays)d" }; if ($null -ne $i.idleDays) { $age += "idle $($i.idleDays)d$(([string] $i.idleSource).Contains('+') ? '+' : '')" }
    $costTxt = ($null -ne $i.monthlyCost) ? ('{0:N2} {1}' -f $i.monthlyCost, $i.currency) : 'unknown'
    $src = ([string] $i.costSource -replace ' \(.*$', '') + ($i.commitmentCaveat ? ' &dagger;' : '')
    $statusTxt = ($i.status -eq 'new') ? '<div class="new">new</div>' : (($i.status -eq 'open') ? "<div class=""small"">since $(ConvertTo-HtmlText $i.firstSeen)</div>" : '')
    $ownerTxt = $i.owner ? ((ConvertTo-HtmlText $i.owner) + $(($i.ownerSource -eq 'resource group tag') ? '<div class="small">via resource group</div>' : '')) : '<span class="small">none</span>'
    HL ("<tr data-type=""$(ConvertTo-HtmlText $i.wasteType)"" data-conf=""$(ConvertTo-HtmlText $i.confidence)"" data-new=""$([int] ($i.status -eq 'new'))"" data-cost=""$([double] $i.rankValue)"" data-confrank=""$($confOrder[$i.confidence])"">" +
        "<td>$(ConvertTo-HtmlText $g.Label)</td><td><a href=""$(ConvertTo-HtmlText $i.portalUrl)"" target=""_blank"" rel=""noopener"">$(ConvertTo-HtmlText $i.name)</a><div class=""small"">$(ConvertTo-HtmlText $i.type)</div></td>" +
        "<td>$(ConvertTo-HtmlText ($i.subscriptionName ? $i.subscriptionName : $i.subscriptionId))<div class=""small"">$(ConvertTo-HtmlText $i.resourceGroup)</div></td><td>$(ConvertTo-HtmlText $i.location)</td><td>$ownerTxt</td>" +
        "<td class=""small"">$(ConvertTo-HtmlText ($age ? ($age -join ', ') : 'unknown'))</td><td class=""num"">$(ConvertTo-HtmlText $costTxt)<div class=""small"">$src</div></td>" +
        "<td class=""c-$(ConvertTo-HtmlText $i.confidence)"">$(ConvertTo-HtmlText $i.confidence)$statusTxt</td><td class=""why"">$(ConvertTo-HtmlText $i.reason)</td><td class=""act"">$(ConvertTo-HtmlText $i.suggestedAction)</td></tr>")
} }
HL '</tbody></table></div>'
if ($caveatCount) { HL '<p class="small">&dagger; A reservation or savings plan can cover this resource. If one does, the commitment is already paid and the bill drops by less than shown.</p>' }

HL '<h2>By waste type</h2><div class="wrap"><table><thead><tr><th>Waste type</th><th class="num">Findings</th><th class="num">Est. monthly</th><th class="num">High</th><th class="num">Medium</th><th class="num">Low</th><th class="num">Excluded</th></tr></thead><tbody>'
foreach ($t in $TypeInfo.Keys) {
    $g = $groups | Where-Object { $_.Type -eq $t }
    if (-not $g.Items.Count -and -not ($excluded[$t] ?? 0)) { continue }
    $c = @{}; foreach ($lvl in 'high', 'medium', 'low') { $c[$lvl] = @($g.Items | Where-Object { $_.confidence -eq $lvl }).Count }
    HL "<tr><td>$(ConvertTo-HtmlText $TypeInfo[$t])</td><td class=""num"">$($g.Items.Count)</td><td class=""num"">$(ConvertTo-HtmlText ($g.Items.Count ? (Format-GroupCost $g.Items) : '-'))</td><td class=""num"">$($c.high)</td><td class=""num"">$($c.medium)</td><td class=""num"">$($c.low)</td><td class=""num"">$($excluded[$t] ?? 0)</td></tr>"
}
HL '</tbody></table></div>'

if ($ownerGroups) {
    HL '<h2>By owner</h2><div class="wrap"><table><thead><tr><th>Owner</th><th class="num">Findings</th><th class="num">High</th><th class="num">Est. monthly</th><th>List</th></tr></thead><tbody>'
    foreach ($o in $ownerGroups) {
        $who = $o.Owner ? (ConvertTo-HtmlText $o.Owner) : '<b>no owner tag</b>'
        if ($o.FromRg) { $who += "<div class=""small"">$($o.FromRg) via resource group tag</div>" }
        HL "<tr><td>$who</td><td class=""num"">$($o.Items.Count)</td><td class=""num"">$($o.High)</td><td class=""num"">$(ConvertTo-HtmlText (Format-GroupCost $o.Items))</td><td class=""small"">$(ConvertTo-HtmlText $o.File)</td></tr>"
    }
    HL '</tbody></table></div>'
}

if ($Trend) {
    HL '<h2>Trends</h2><div class="wrap"><table><thead><tr><th>Scan</th><th class="num">Findings</th><th class="num">Est. monthly</th><th class="num">High confidence</th><th class="num">New</th><th class="num">Resolved</th></tr></thead><tbody>'
    foreach ($sc in @($Trend.Scans | Select-Object -Last 13)) {
        $label = $sc.Current ? "<b>$(ConvertTo-HtmlText $sc.Date) (this scan)</b>" : "$(ConvertTo-HtmlText $sc.Date)<div class=""small"">$(ConvertTo-HtmlText $sc.Folder)</div>"
        HL "<tr><td>$label</td><td class=""num"">$($sc.Findings)</td><td class=""num"">$(ConvertTo-HtmlText (Format-Money $sc.Totals))</td><td class=""num"">$(ConvertTo-HtmlText (Format-Money $sc.High))</td><td class=""num"">$($sc.New ?? '-')</td><td class=""num"">$($sc.Resolved ?? '-')</td></tr>"
    }
    HL '</tbody></table></div>'
    if ($Trend.ResolvedTimed) { HL "<p>Time to resolve: median <b>$($Trend.MedianDays) day(s)</b> from first seen, over $($Trend.ResolvedTimed) resolved finding(s).</p>" }
    if ($Trend.Oldest) {
        HL '<p class="small">Open longest:</p><ul>'
        foreach ($o in $Trend.Oldest) { HL "<li>$(ConvertTo-HtmlText $o.Name) ($(ConvertTo-HtmlText ($TypeInfo[[string] $o.WasteType] ?? $o.WasteType))): open $($o.Days) day(s) since $(ConvertTo-HtmlText $o.FirstSeen)</li>" }
        HL '</ul>'
    }
}
HL '<h2>Coverage</h2><div class="wrap"><table><thead><tr><th>Tenant</th><th>Scope</th><th>Subscriptions</th><th>Status</th></tr></thead><tbody>'
foreach ($c in $coverage) { HL "<tr><td class=""small"">$(ConvertTo-HtmlText $c.Tenant)</td><td>$(ConvertTo-HtmlText $c.Scope)</td><td>$(ConvertTo-HtmlText $c.Subscriptions)</td><td>$(ConvertTo-HtmlText $c.Status)</td></tr>" }
HL '</tbody></table></div>'
$allWarn = @($errs) + @($warnings)
if ($allWarn) { HL '<h2>Warnings and errors</h2><ul>'; foreach ($w in $allWarn) { HL "<li>$(ConvertTo-HtmlText ($w -replace '``', ''))</li>" }; HL '</ul>' }
HL '<p class="small">Suggested actions are text only. Nothing was executed. The full data, including reference commands, is in findings.csv next to this file.</p>'
HL @'
<script>
(function () {
  var rows = Array.prototype.slice.call(document.querySelectorAll('#t tbody tr'));
  var q = document.getElementById('q'), type = document.getElementById('type'), newonly = document.getElementById('newonly');
  var confs = Array.prototype.slice.call(document.querySelectorAll('.conf')), count = document.getElementById('count');
  function apply() {
    var text = q.value.toLowerCase(), shown = 0;
    var on = confs.filter(function (c) { return c.checked; }).map(function (c) { return c.value; });
    rows.forEach(function (r) {
      var ok = (!type.value || r.dataset.type === type.value) && on.indexOf(r.dataset.conf) >= 0 &&
               (!newonly.checked || r.dataset.new === '1') && (!text || r.textContent.toLowerCase().indexOf(text) >= 0);
      r.style.display = ok ? '' : 'none'; if (ok) shown++;
    });
    count.textContent = shown + ' of ' + rows.length + ' shown';
  }
  [q, type, newonly].concat(confs).forEach(function (el) { el.addEventListener('input', apply); el.addEventListener('change', apply); });
  var dir = {};
  Array.prototype.slice.call(document.querySelectorAll('#t th.sort')).forEach(function (th, idx) {
    th.addEventListener('click', function () {
      var k = th.dataset.k; dir[k] = !dir[k];
      var tb = document.querySelector('#t tbody');
      rows.sort(function (a, b) {
        var x, y;
        if (k === 'cost') { x = +a.dataset.cost; y = +b.dataset.cost; }
        else if (k === 'conf') { x = +a.dataset.confrank; y = +b.dataset.confrank; }
        else { var col = { type: 0, name: 1, owner: 4 }[k]; x = a.cells[col].textContent.toLowerCase(); y = b.cells[col].textContent.toLowerCase(); }
        return (x < y ? -1 : x > y ? 1 : 0) * (dir[k] ? 1 : -1);
      });
      rows.forEach(function (r) { tb.appendChild(r); });
    });
  });
  apply();
})();
</script></main></body></html>
'@
$htmlPath = Join-Path $OutDir 'report.html'
Set-Content $htmlPath $hb.ToString() -Encoding utf8

Write-Host ''
Write-Host "Estimated monthly savings: $(Format-Money $totals), high confidence $(Format-Money $highTotals)  ($($findings.Count) findings, $([int] $exclTotal) excluded)"
foreach ($c in $coverage) { if ($c.Status -ne 'ok') { Write-Host "Tenant $($c.Tenant): $($c.Status)" -ForegroundColor Yellow } }
Write-Host "Report: $mdPath"
Write-Host "HTML:   $htmlPath"
Write-Host "CSV:    $csvPath  (per owner: $ownerDir)"
