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
    [string] $FixtureDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 'pwsh -File' can't pass arrays, so also accept comma-separated lists: -Subscription "A,B"
if ($Subscription) { $Subscription = @($Subscription | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
if ($Tenant)       { $Tenant       = @($Tenant       | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }

$SkillDir = Split-Path -Parent $PSScriptRoot
$QueryDir = Join-Path $SkillDir 'queries'
$Pricing  = Get-Content (Join-Path $PSScriptRoot 'pricing.json') -Raw | ConvertFrom-Json -AsHashtable
$Now      = [DateTime]::UtcNow
if (-not $OutDir) { $OutDir = Join-Path (Get-Location) (Join-Path 'reports' $Now.ToString('yyyyMMdd-HHmmss')) }
if ($FixtureDir) { $FixtureDir = (Resolve-Path $FixtureDir).Path }

# ---------------------------------------------------------------------------------------------
# Read-only guard
# ---------------------------------------------------------------------------------------------
$AllowedAz = @(
    'graph query'
    'monitor metrics list'
    'advisor recommendation list'
    'consumption usage list'
    'account show'
    'account list'
    'account set'      # local CLI context only, restored at the end
)

# ---------------------------------------------------------------------------------------------
# Regional list prices: Azure Retail Prices API. A public, unauthenticated, read-only GET, and the
# only allowed non-az read. Requests contain only service/SKU/region/currency filters, never tenant data.
# ---------------------------------------------------------------------------------------------
$PriceApi   = 'https://prices.azure.com/api/retail/prices'
$PriceCache = @{}
$PriceStats = @{ live = 0; fallback = 0; failedLookups = 0 }
$script:PriceApiDown = [bool] $OfflinePricing
$script:PriceFailStreak = 0

function Get-ODataLiteral([object] $s) { ([string] $s) -replace "'", "''" }

# GET with retry. The API rate-limits (429), so back off (honouring Retry-After) on 429, 5xx and
# network errors, up to 4 attempts.
function Invoke-PriceApi([string] $Url) {
    for ($attempt = 1; ; $attempt++) {
        try { return Invoke-RestMethod -Uri $Url -Method Get -TimeoutSec 20 }
        catch {
            $resp = $_.Exception.PSObject.Properties['Response'] ? $_.Exception.Response : $null
            $code = $resp ? [int] $resp.StatusCode : 0
            $maxAttempts = ($code -eq 0) ? 2 : 4     # network errors: retry once; rate limits and 5xx: up to 4
            if ($attempt -ge $maxAttempts -or -not ($code -eq 0 -or $code -eq 429 -or $code -ge 500)) { throw }
            $wait = 2 * $attempt
            if ($resp -and $resp.Headers.RetryAfter -and $resp.Headers.RetryAfter.Delta) { $wait = [math]::Min(30, [math]::Ceiling($resp.Headers.RetryAfter.Delta.TotalSeconds)) }
            Start-Sleep -Seconds $wait
        }
    }
}

# Matching price items (Consumption only), priced in $Cur. Returns elements, not a nested array.
function Get-RetailItems([string] $Filter, [string] $Cur = $Currency) {
    $cacheKey = "$Cur|$Filter"
    if ($PriceCache.ContainsKey($cacheKey)) { return $PriceCache[$cacheKey] }
    if ($script:PriceApiDown) { return }
    $url = "${PriceApi}?currencyCode='$Cur'&`$filter=" + [uri]::EscapeDataString("$Filter and priceType eq 'Consumption'")
    $items = [Collections.Generic.List[object]]::new()
    try {
        for ($page = 0; $url -and $page -lt 5; $page++) {
            if (-not $url.StartsWith($PriceApi)) { throw "unexpected price API URL $url" }
            $r = Invoke-PriceApi $url
            foreach ($it in @($r.Items)) { $items.Add($it) }
            $url = $r.NextPageLink
        }
        $script:PriceFailStreak = 0
    }
    catch {
        # One failed lookup falls back for that finding only. Three in a row means the API is
        # unreachable, so stop asking.
        $PriceStats.failedLookups++
        $script:PriceFailStreak++
        if ($script:PriceFailStreak -ge 3) {
            $script:PriceApiDown = $true
            $warnings.Add("Retail Prices API unavailable after repeated failures, so the rest of this scan uses pricing.json (US East, USD). Last error: $($_.Exception.Message)")
        }
        return
    }
    $PriceCache[$cacheKey] = $items
    return $items
}

# Exchange rate From -> $Currency, used ONLY to rank findings whose amounts are in different
# currencies. The price list converts every price from USD at one rate per currency, so the ratio of
# the same meter's price in both currencies is that rate. A P80 disk (about USD 3,400/month) keeps
# rounding error small. $null when unavailable (offline, API down).
$FxRates = @{}
function Get-FxRate([string] $From) {
    if (-not $From -or $From -eq $Currency) { return 1.0 }
    if ($FxRates.ContainsKey($From)) { return $FxRates[$From] }
    $filter = "serviceName eq 'Storage' and armRegionName eq 'eastus' and productName eq 'Premium SSD Managed Disks' and skuName eq 'P80 LRS'"
    $price = @{}
    foreach ($c in $From, $Currency) {
        $it = @(Get-RetailItems $filter $c) | Where-Object { $_.meterName -eq 'P80 LRS Disk' -and $_.unitOfMeasure -eq '1/Month' } | Select-Object -First 1
        $price[$c] = $it ? [double] $it.retailPrice : 0.0
    }
    $FxRates[$From] = ($price[$From] -gt 0 -and $price[$Currency] -gt 0) ? $price[$Currency] / $price[$From] : $null
    return $FxRates[$From]
}

function Invoke-AzRead {
    param([Parameter(Mandatory)] [string[]] $AzArgs)

    $lead = foreach ($a in $AzArgs) { if ($a.StartsWith('-')) { break }; $a }
    $cmd  = @($lead) -join ' '
    if ($cmd -notin $AllowedAz) { throw "Refusing non-read-only az command: 'az $cmd'" }

    if ($FixtureDir) { return Get-FixtureResponse $cmd $AzArgs }

    $errFile = [IO.Path]::GetTempFileName()
    try {
        $out  = & az @AzArgs --only-show-errors -o json 2> $errFile
        $code = $LASTEXITCODE
        if ($code -ne 0) {
            $msg = (Get-Content $errFile | Where-Object { $_ -match 'ERROR|AADSTS|message' } | Select-Object -First 3) -join ' '
            if (-not $msg) { $msg = (Get-Content $errFile -TotalCount 2) -join ' ' }
            throw "az $cmd failed (exit $code): $msg"
        }
        $text = ($out -join "`n").Trim()
        if (-not $text) { return $null }
        # No comma-wrap here: a JSON array must reach the caller's @() as its elements, not as one
        # nested array. (A nested array made every Where-Object filter match everything.)
        return ($text | ConvertFrom-Json -AsHashtable -Depth 64 -DateKind String)
    }
    finally { Remove-Item $errFile -ErrorAction SilentlyContinue }
}

# Offline mode. Reads canned responses from -FixtureDir so the whole pipeline runs without Azure.
function Get-FixtureResponse([string] $cmd, [string[]] $AzArgs) {
    $read = { param($f) $p = Join-Path $FixtureDir $f; if (Test-Path $p) { Get-Content $p -Raw | ConvertFrom-Json -AsHashtable -DateKind String } }
    switch ($cmd) {
        'account show' { return & $read 'account.json' }
        'account list' { return @(& $read 'accounts.json') }
        'account set'  { return $null }
        'graph query'  {
            $q = $AzArgs[[array]::IndexOf($AzArgs, '-q') + 1].TrimStart('@')
            $rows = @(& $read ([IO.Path]::GetFileNameWithoutExtension($q) + '.json'))
            return @{ count = $rows.Count; data = $rows; skip_token = $null }
        }
        'monitor metrics list' {
            $id = $AzArgs[[array]::IndexOf($AzArgs, '--resource') + 1].ToLower()
            $m = & $read 'metrics.json'
            return ($m -and $m.ContainsKey($id)) ? $m[$id] : @{ value = @() }
        }
        'consumption usage list' {
            $sub = $AzArgs[[array]::IndexOf($AzArgs, '--subscription') + 1]
            return @(@(& $read 'consumption.json') | Where-Object { $_ -and $_.instanceId -like "/subscriptions/$sub/*" })
        }
    }
}

# ---------------------------------------------------------------------------------------------
# Azure reads
# ---------------------------------------------------------------------------------------------
function Invoke-GraphQuery([string] $QueryFile, [string[]] $Subscriptions, [string] $MgId) {
    $rows = [Collections.Generic.List[object]]::new()
    $skip = $null
    do {
        $a = @('graph', 'query', '-q', "@$QueryFile", '--first', '1000')
        if ($MgId) { $a += @('--management-groups', $MgId) }
        elseif ($Subscriptions) { $a += '--subscriptions'; $a += $Subscriptions }
        if ($skip) { $a += @('--skip-token', $skip) }
        $res = Invoke-AzRead $a
        foreach ($r in @($res.data)) { if ($null -ne $r) { $rows.Add($r) } }
        $skip = $res.skip_token
    } while ($skip)
    return , $rows
}

# Last Percentage CPU datapoint. A VM that is stopped emits no CPU metrics.
# The metrics API silently clips a request to its most recent ~30 days, so 90 days of history
# means three 30-day windows, newest first, stopping at the first one with data.
function Get-LastCpuActivity([string] $ResourceId) {
    for ($k = 0; $k -lt 3; $k++) {
        $end = $Now.AddDays(-30 * $k); $start = $end.AddDays(-30)
        $res = Invoke-AzRead @('monitor', 'metrics', 'list', '--resource', $ResourceId, '--metric', 'Percentage CPU',
            '--interval', 'P1D', '--aggregation', 'Maximum',
            '--start-time', $start.ToString('yyyy-MM-ddTHH:mm:ssZ'), '--end-time', $end.ToString('yyyy-MM-ddTHH:mm:ssZ'))
        $stamps = foreach ($v in @($res.value)) { foreach ($ts in @($v.timeseries)) { foreach ($d in @($ts.data)) {
            if ($d -and $null -ne $d.maximum -and [double] $d.maximum -gt 0) { [string] $d.timeStamp } } } }
        $last = @($stamps) | Sort-Object | Select-Object -Last 1
        if ($last) { return @{ Window = 90; Last = [DateTimeOffset]::Parse($last, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime } }
    }
    return @{ Window = 90; Last = $null }
}

# Actual cost per resource over the last 30 days, keyed by lower-case resource ID.
function Add-BilledCosts([string] $SubscriptionId, [hashtable] $Billed) {
    $usage = Invoke-AzRead @('consumption', 'usage', 'list', '--subscription', $SubscriptionId,
        '--start-date', $Now.AddDays(-30).ToString('yyyy-MM-dd'), '--end-date', $Now.ToString('yyyy-MM-dd'))
    $n = 0; $total = 0
    foreach ($u in @($usage)) {
        if ($u) { $total++ }
        if (-not $u -or -not $u.instanceId -or $null -eq $u.pretaxCost -or [string] $u.pretaxCost -eq 'None') { continue }
        $key = ([string] $u.instanceId).ToLower()
        if (-not $Billed.ContainsKey($key)) { $Billed[$key] = @{ Cost = 0.0; Days = [Collections.Generic.HashSet[string]]::new(); Currency = '' } }
        $e = $Billed[$key]
        $e.Cost += [double] $u.pretaxCost
        if ($u.usageStart) { [void] $e.Days.Add(([string] $u.usageStart).Substring(0, 10)) }
        if ($u.currency) { $e.Currency = [string] $u.currency }
        $n++
    }
    # Newer billing accounts (MCA, some Visual Studio offers) return usage records that
    # 'az consumption' maps to its legacy schema with no instanceId or cost. Report that instead of
    # pretending the cost is zero.
    if ($total -gt 0 -and $n -eq 0) { throw "Consumption API returned $total usage record(s) with no instanceId/pretaxCost (billing schema not readable by 'az consumption')" }
    return $n
}

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
$rowsAll    = [Collections.Generic.List[object]]::new()
$coverage   = [Collections.Generic.List[object]]::new()
$queryStats = [ordered]@{}
$billed     = @{}
$idleInfo   = @{}
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
            if ($p.Subscriptions) {
                $missing = @($p.Subscriptions | Where-Object { $_ -notin $visible })
                if ($missing.Count -eq $p.Subscriptions.Count) { throw "Resource Graph can't see any of the $($missing.Count) subscription(s) in this tenant. Check login and permissions (az login --tenant $($p.TenantId))." }
                foreach ($m in $missing) { $errors += "Resource Graph can't see subscription '$($SubName[$m] ?? $m)'. Its results are missing." }
            }
            elseif (-not $visible) { throw "Resource Graph returned no subscriptions under management group $($p.Mg)." }

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
                catch { Write-Host ' FAILED'; $errors += "$($qf.Name): $($_.Exception.Message)"; $queryStats[$qf.BaseName] = 'FAILED' }
            }
            $queryErrors = @($errors | Where-Object { $_ -like '*.kql:*' }).Count
            if ($queryErrors -eq $queryFiles.Count) { $status = 'failed' } elseif ($errors) { $status = 'partial' }

            # Idle time for stopped VMs (needs this tenant's context)
            foreach ($vm in @($passRows | Where-Object { $_.wasteType -eq 'vm-stopped-not-deallocated' -and -not $_.ignored })) {
                if ($SkipMetrics) { break }
                try { $idleInfo[$vm.id.ToLower()] = Get-LastCpuActivity $vm.id }
                catch { $warnings.Add("Metrics unavailable for $($vm.name): $($_.Exception.Message)") }
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
$TypeInfo = [ordered]@{
    'unattached-disk'            = 'Unattached managed disks'
    'orphaned-nic'               = 'Orphaned NICs (no VM attached)'
    'unassociated-public-ip'     = 'Unassociated public IPs'
    'empty-app-service-plan'     = 'Empty App Service plans'
    'vm-stopped-not-deallocated' = 'VMs stopped but not deallocated'
    'old-snapshot'               = 'Disk snapshots older than 90 days'
    'advisor-cost'               = 'Other Azure Advisor cost recommendations'
}
$ConfRank = @{ high = 0; medium = 1; low = 2 }
function Step-Confidence([string] $c) { @{ low = 'medium'; medium = 'high'; high = 'high' }[$c] }

$excluded = @{}
foreach ($r in $rowsAll) { if ([bool] $r.ignored) { $excluded[$r.wasteType] = ($excluded[$r.wasteType] ?? 0) + 1 } }

$live     = @($rowsAll | Where-Object { -not [bool] $_.ignored })
$detected = @($live | Where-Object { $_.wasteType -ne 'advisor-cost' } | Group-Object { $_.id.ToLower() } | ForEach-Object { $_.Group[0] })
$advisor  = @($live | Where-Object { $_.wasteType -eq 'advisor-cost' })
$advByRes = @{}
foreach ($a in $advisor) { $k = ([string] $a.id).ToLower(); if (-not $advByRes[$k]) { $advByRes[$k] = @() }; $advByRes[$k] += $a }
$consumed = [Collections.Generic.HashSet[string]]::new()

# Billing tier of a managed disk (P30, E10, S20, ...). properties.tier when set (premium performance
# tiers), otherwise the smallest tier that fits the size. $null for per-GiB disks (Premium SSD v2, Ultra).
function Get-DiskTier($f) {
    $t = $Pricing.disks[([string] $f.sku) -replace '_ZRS$', '_LRS']
    if (-not ($t -is [System.Collections.IDictionary] -and $t.ContainsKey('tiers'))) { return $null }
    $i = [array]::IndexOf($t.tiers, [string] $f.tier)
    if ($i -lt 0) {
        $sizes = $Pricing.disks.tierSizesGb; $i = $sizes.Count - 1
        for ($j = 0; $j -lt $sizes.Count; $j++) { if ([int] $f.sizeGb -le $sizes[$j]) { $i = $j; break } }
    }
    return @{ Name = $t.tiers[$i]; Price = $t.prices[$i] }
}

# Monthly list price in the resource's own region, from the Retail Prices API. $null means no
# regional price was found, so the caller falls back to Get-Estimate.
function Get-LivePrice($f) {
    $region = ([string] $f.location).ToLower()
    if ($script:PriceApiDown -or -not $region -or $region -eq 'global') { return $null }
    $sku = [string] $f.sku; $rg = Get-ODataLiteral $region; $hours = $Pricing.hoursPerMonth
    $red = ($sku -like '*_ZRS') ? 'ZRS' : 'LRS'
    switch ($f.wasteType) {
        'unattached-disk' {
            $prod = @{ Premium = 'Premium SSD Managed Disks'; StandardSSD = 'Standard SSD Managed Disks'; Standard = 'Standard HDD Managed Disks' }[($sku -split '_')[0]]
            $tier = Get-DiskTier $f
            if (-not $prod -or -not $tier) { return $null }
            $m = "$($tier.Name) $red"
            $it = @(Get-RetailItems "serviceName eq 'Storage' and armRegionName eq '$rg' and productName eq '$prod' and skuName eq '$m'") |
                Where-Object { $_.meterName -eq "$m Disk" -and $_.unitOfMeasure -eq '1/Month' } | Select-Object -First 1
            if ($it) { return @{ Cost = [double] $it.retailPrice; Note = "$m list price, $region" } }
        }
        'old-snapshot' {
            $prod = ($sku -like 'Premium*') ? 'Premium SSD Managed Disks' : 'Standard HDD Managed Disks'
            $it = @(Get-RetailItems "serviceName eq 'Storage' and armRegionName eq '$rg' and productName eq '$prod' and skuName eq 'Snapshots $red'") |
                Where-Object { $_.meterName -eq "$red Snapshots" -and $_.unitOfMeasure -eq '1 GB/Month' } | Select-Object -First 1
            if ($it) { return @{ Cost = [double] $it.retailPrice * [int] $f.sizeGb; Note = "$red snapshot list price, $region; upper bound, provisioned GiB" } }
        }
        'unassociated-public-ip' {
            if ($sku -ne 'Standard' -and $f.confidence -eq 'low') { return $null }   # no charge; Get-Estimate says so
            $ipSku = ($f.tier -eq 'Global') ? 'Global' : $sku
            $it = @(Get-RetailItems "serviceName eq 'Virtual Network' and armRegionName eq '$rg' and productName eq 'IP Addresses' and skuName eq '$(Get-ODataLiteral $ipSku)'") |
                Where-Object { $_.meterName -eq "$ipSku IPv4 Static Public IP" -and $_.unitOfMeasure -eq '1 Hour' } | Select-Object -First 1
            if ($it) { return @{ Cost = [double] $it.retailPrice * $hours; Note = "$ipSku static IP list price, $region" } }
        }
        'empty-app-service-plan' {
            if ($sku -in $Pricing.appServicePlans.free -or $f.tier -in $Pricing.appServicePlans.free) { return $null }   # free; Get-Estimate says so
            if ($sku -like 'EP*' -or $sku -like 'WS*') { return $null }   # Elastic Premium / Workflow: vCPU+memory meters
            # The API spells some SKUs with a space ('P1 v3', 'I1 v2') and others without ('P0v3', 'P1mv3')
            $alt = $sku -replace '(\d)(v\d)$', '$1 $2'
            $linux = $f.os -eq 'Linux'
            $it = @(Get-RetailItems "serviceName eq 'Azure App Service' and armRegionName eq '$rg' and (skuName eq '$(Get-ODataLiteral $sku)' or skuName eq '$(Get-ODataLiteral $alt)')") |
                Where-Object { $_.unitOfMeasure -eq '1 Hour' -and (($_.productName -like '* - Linux') -eq $linux) } | Select-Object -First 1
            if ($it) { $n = [math]::Max(1, [int] $f.sizeGb); return @{ Cost = [double] $it.retailPrice * $hours * $n; Note = "$sku $($f.os) list price x$n, $region" } }
        }
        'vm-stopped-not-deallocated' {
            $spot = $f.tier -eq 'Spot'
            $win  = $f.os -eq 'Windows' -and $f.extra -ne 'Windows_Server'   # Azure Hybrid Benefit = Linux rate
            $it = @(Get-RetailItems "serviceName eq 'Virtual Machines' and armRegionName eq '$rg' and armSkuName eq '$(Get-ODataLiteral $sku)'") |
                Where-Object { $_.unitOfMeasure -eq '1 Hour' -and ($_.skuName -notlike '*Low Priority*') -and (($_.skuName -like '*Spot*') -eq $spot) -and (($_.productName -like '*Windows*') -eq $win) } |
                Select-Object -First 1
            if ($it) { return @{ Cost = [double] $it.retailPrice * $hours; Note = "$sku $($win ? 'Windows' : 'Linux')$($spot ? ' Spot' : '') list price, $region" } }
        }
    }
    return $null
}

function Get-Estimate($f) {
    $sku = [string] $f.sku
    switch ($f.wasteType) {
        'unattached-disk' {
            $tier = Get-DiskTier $f
            if ($tier) {
                $mult = ($sku -like '*_ZRS') ? $Pricing.disks.zrsMultiplier : 1
                return @{ Cost = $tier.Price * $mult; Note = "list price $($tier.Name)" }
            }
            $perGb = $Pricing.disks.perGbFallback[$sku] ?? $Pricing.disks.perGbFallback.default
            return @{ Cost = $perGb * [int] $f.sizeGb; Note = 'list price per GiB, capacity only' }
        }
        'old-snapshot' {
            $perGb = $Pricing.snapshotsPerGb[$sku] ?? $Pricing.snapshotsPerGb.default
            return @{ Cost = $perGb * [int] $f.sizeGb; Note = 'upper bound, provisioned GiB (billed on used GiB)' }
        }
        'unassociated-public-ip' {
            if ($sku -eq 'Standard') { return @{ Cost = $Pricing.publicIps.Standard; Note = 'list price' } }
            if ($f.confidence -eq 'low') { return @{ Cost = 0.0; Note = 'no charge' } }
            return @{ Cost = $Pricing.publicIps['Basic|Static']; Note = 'list price' }
        }
        'empty-app-service-plan' {
            if ($sku -in $Pricing.appServicePlans.free -or $f.tier -in $Pricing.appServicePlans.free) { return @{ Cost = 0.0; Note = 'free tier' } }
            $tbl = $Pricing.appServicePlans[[string] $f.os]
            $price = $tbl ? $tbl[$sku] : $null
            if ($null -eq $price) { return @{ Cost = $null; Note = "no list price for $sku" } }
            $n = [math]::Max(1, [int] $f.sizeGb)
            return @{ Cost = $price * $n; Note = "list price $sku x$n" }
        }
        'vm-stopped-not-deallocated' {
            if ($sku -notmatch '^(?:Standard|Basic)_([A-Za-z])[A-Za-z]*?(\d+)') { return @{ Cost = $null; Note = "unknown size $sku" } }
            $fam = $Matches[1].ToUpper(); $vcpu = [int] $Matches[2]
            $rate = $Pricing.vms.perVcpuHourByFamily[$fam] ?? $Pricing.vms.defaultPerVcpuHour
            if ($f.os -eq 'Windows' -and $f.extra -ne 'Windows_Server') { $rate += $Pricing.vms.windowsPerVcpuHour }
            $cost = $rate * $vcpu * $Pricing.hoursPerMonth
            if ($f.tier -eq 'Spot') { $cost *= 0.2 }
            return @{ Cost = $cost; Note = "list price ~$vcpu vCPU $fam-family$(($f.tier -eq 'Spot') ? ', Spot' : '')" }
        }
        'orphaned-nic' { return @{ Cost = 0.0; Note = 'NICs are free' } }
    }
    return @{ Cost = $null; Note = '' }
}

function Get-Action($f) {
    $who = $f.owner ? "the owner ($($f.owner))" : 'the resource group owner'
    $id = $f.id
    switch ($f.wasteType) {
        'unattached-disk' { return @(
            "Confirm with $who that the data isn't needed. If unsure, take an incremental snapshot (cheaper per GiB), then delete the disk.",
            "az disk delete --ids $id") }
        'orphaned-nic' { return @(
            "Delete the NIC if nothing will reattach it. This frees its private IP$(($f.extra -eq 'holds-public-ip') ? ' and releases its public IP association' : '').",
            "az network nic delete --ids $id") }
        'unassociated-public-ip' {
            if ($f.confidence -eq 'low') { return @('No charge. Delete to reduce clutter.', "az network public-ip delete --ids $id") }
            return @("Check DNS records and firewall or partner allowlists that reference this IP (a released static IP can't be recovered), then delete it.",
                     "az network public-ip delete --ids $id") }
        'empty-app-service-plan' {
            if ($f.confidence -eq 'low') { return @('No charge while empty. Delete to reduce clutter.', "az appservice plan delete --ids $id") }
            return @("Delete the plan if no deployment is planned. If it's being kept for upcoming work, scale it down to Free or B1 until needed.",
                     "az appservice plan delete --ids $id") }
        'vm-stopped-not-deallocated' { return @(
            "Deallocate it to stop compute billing (its disks keep billing), or delete it if it's no longer needed. Deallocating releases dynamic public IPs.",
            "az vm deallocate --ids $id") }
        'old-snapshot' {
            $pre = ($f.confidence -eq 'low') ? 'The source disk is gone or this is Azure Backup data. Confirm the data is not needed. ' : ''
            return @("${pre}Check whether a retention policy requires it. If not, delete it. If it must be kept, make sure it's incremental on Standard storage.",
                     "az snapshot delete --ids $id") }
        'advisor-cost' { return @("Advisor suggests: $($f.extra). Review it on the Advisor Cost tab.", '') }
    }
}

function Format-Day($v) { if (-not $v) { return '' }; try { [DateTimeOffset]::Parse([string] $v, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime.ToString('yyyy-MM-dd') } catch { [string] $v } }

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
    elseif ($advByRes[$key]) {
        $recs = @($advByRes[$key])
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
    $b = ($r.wasteType -ne 'advisor-cost') ? $billed[$key] : $null
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
# Output
# ---------------------------------------------------------------------------------------------
function Esc([object] $s) { (([string] $s) -replace '\|', '\|' -replace '\r?\n', ' ').Trim() }
function Format-Money([hashtable] $byCur) {
    $parts = @($byCur.GetEnumerator() | Where-Object { $_.Value -ne 0 } | Sort-Object Value -Descending)
    if (-not $parts) { return "0.00 $Currency" }
    (@($parts | ForEach-Object { '{0:N2} {1}' -f $_.Value, $_.Key })) -join ' + '
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
    }
} }
$csvPath = Join-Path $OutDir 'findings.csv'
@($csvRows) | Export-Csv $csvPath -Encoding utf8
if (-not $csvRows) { Set-Content $csvPath ('"rank","wasteType","wasteTypeLabel","name","resourceId","type","tenantId","subscriptionId","subscriptionName","resourceGroup","location","owner","app","env","createdTime","ageDays","idleDays","idleSource","sku","sizeGbOrInstances","monthlyCost","currency","costSource","advisorMonthlySavings","confidence","reason","suggestedAction","referenceCommandNotExecuted","portalUrl"') -Encoding utf8 }

$md = [Text.StringBuilder]::new()
function L([string] $s = '') { [void] $md.AppendLine($s) }
$totals = Get-Totals $findings
$exclTotal = ($excluded.Values | Measure-Object -Sum).Sum
L '# Azure waste report'
L ''
L "## Estimated monthly savings: **$(Format-Money $totals)**"
L ''
L "$($findings.Count) finding(s) across $(@($groups | Where-Object { $_.Items.Count }).Count) waste type(s). $([int] $exclTotal) resource(s) excluded by ``waste-hunter:ignore=true``."
L ''
L "Generated $($Now.ToString('yyyy-MM-dd HH:mm')) UTC. Scope: $ScopeLabel. **Read-only scan: nothing in Azure was changed.**"
if ($FixtureDir) { L ''; L "> **SYNTHETIC DEMO DATA** loaded from ``$(Split-Path $FixtureDir -Leaf)``. No Azure calls were made and these resources are not real." }
L ''
L '| Waste type | Findings | Est. monthly | High | Medium | Low | Excluded |'
L '|---|---:|---:|---:|---:|---:|---:|'
foreach ($t in $TypeInfo.Keys) {
    $g = $groups | Where-Object { $_.Type -eq $t }
    $c = @{}; foreach ($lvl in 'high', 'medium', 'low') { $c[$lvl] = @($g.Items | Where-Object { $_.confidence -eq $lvl }).Count }
    L "| $($TypeInfo[$t]) | $($g.Items.Count) | $(Format-Money (Get-Totals $g.Items)) | $($c.high) | $($c.medium) | $($c.low) | $($excluded[$t] ?? 0) |"
}
L ''
$priceMode = $OfflinePricing ? "offline: ``scripts/pricing.json`` (US East, USD)" : "pay-as-you-go list prices for each resource's own region, in $Currency, from the Azure Retail Prices API, with ``scripts/pricing.json`` (US East, USD) as the fallback"
L "**Cost sources:** *billed* is the actual 30-day cost from the Consumption API, scaled to 30 days. *advisor* is Azure Advisor's monthly savings estimate. *estimated* is $priceMode. Snapshot estimates are upper bounds. Advisor recommendations that match a finding above are merged into it and not counted twice."
if ($fxUsed.Count) {
    $rates = (@($fxUsed.GetEnumerator() | Sort-Object Key | ForEach-Object { '1 {0} = {1:N4} {2}' -f $_.Key, $_.Value, $Currency })) -join ', '
    L ''
    L "**Ranking across currencies:** amounts are shown in their original currency, but findings are ranked after converting them to $Currency at the rate implied by Microsoft's price list ($rates)."
}
L ''

foreach ($g in @($groups | Where-Object { $_.Items.Count })) {
    L "## $($g.Label): $($g.Items.Count) finding(s), $(Format-Money (Get-Totals $g.Items))/month"
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
        $cost = ($null -ne $i.monthlyCost) ? ('{0:N2} {1}<br><sub>{2}</sub>' -f $i.monthlyCost, $i.currency, ($i.costSource -replace ' \(.*$', '')) : 'unknown'
        L ("| $n | [$(Esc $i.name)]($($i.portalUrl))<br><sub>$(Esc $i.type)</sub> | $(Esc ($i.subscriptionName ? $i.subscriptionName : $i.subscriptionId))<br><sub>$(Esc $i.resourceGroup)</sub> | $(Esc $i.location) | $(Esc $tagsCell) | $ageCell | $cost | **$($i.confidence)** | $(Esc $i.reason) | $(Esc $i.suggestedAction) |")
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

Write-Host ''
Write-Host "Estimated monthly savings: $(Format-Money $totals)  ($($findings.Count) findings, $([int] $exclTotal) excluded)"
foreach ($c in $coverage) { if ($c.Status -ne 'ok') { Write-Host "Tenant $($c.Tenant): $($c.Status)" -ForegroundColor Yellow } }
Write-Host "Report: $mdPath"
Write-Host "CSV:    $csvPath"
