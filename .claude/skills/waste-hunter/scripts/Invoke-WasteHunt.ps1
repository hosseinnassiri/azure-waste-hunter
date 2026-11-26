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
    'cognitiveservices account deployment list'   # OpenAI deployments aren't in Resource Graph; names/SKUs/capacity only
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
            # Keyed "<resource id>|<first metric name>" (lower case), falling back to "<resource id>"
            $id = $AzArgs[[array]::IndexOf($AzArgs, '--resource') + 1].ToLower()
            $metric = $AzArgs[[array]::IndexOf($AzArgs, '--metric') + 1].ToLower()
            $m = & $read 'metrics.json'
            if ($m) { foreach ($k in "$id|$metric", $id) { if ($m.ContainsKey($k)) { return $m[$k] } } }
            return @{ value = @() }
        }
        'cognitiveservices account deployment list' {
            # Keyed "<resource group>/<account name>" (lower case)
            $key = ($AzArgs[[array]::IndexOf($AzArgs, '-g') + 1] + '/' + $AzArgs[[array]::IndexOf($AzArgs, '-n') + 1]).ToLower()
            $d = & $read 'deployments.json'
            return ($d -and $d.ContainsKey($key)) ? @($d[$key]) : @()
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
        $stamps = foreach ($v in @((Get-Key $res 'value'))) { foreach ($ts in @((Get-Key $v 'timeseries'))) { foreach ($d in @((Get-Key $ts 'data'))) {
            $mx = Get-Key $d 'maximum'
            if ($null -ne $mx -and [double] $mx -gt 0) { [string] (Get-Key $d 'timeStamp') } } } }
        $last = @($stamps) | Sort-Object | Select-Object -Last 1
        if ($last) { return @{ Window = 90; Last = [DateTimeOffset]::Parse($last, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime } }
    }
    return @{ Window = 90; Last = $null }
}

# Generic metrics read. Returns @{ <metric name> = @{ Sum; Points; Last; BySplit } }. A window of
# 30 days or less is never clipped. Null datapoints and absent series (no activity) count as zero.
# With -Filter "<Dim> eq '*'", BySplit holds per-dimension-value sums.
function Get-MetricStats([string] $Id, [string[]] $Metrics, [string] $Aggregation = 'Total', [string] $Interval = 'P1D',
                         [int] $Days = 30, [string] $Filter) {
    $a = @('monitor', 'metrics', 'list', '--resource', $Id, '--metric') + $Metrics +
         @('--aggregation', $Aggregation, '--interval', $Interval,
           '--start-time', $Now.AddDays(-$Days).ToString('yyyy-MM-ddTHH:mm:ssZ'), '--end-time', $Now.ToString('yyyy-MM-ddTHH:mm:ssZ'))
    if ($Filter) { $a += @('--filter', $Filter) }
    $res = Invoke-AzRead $a
    $agg = $Aggregation.ToLower()
    $out = @{}
    # Index access throughout: strict mode throws on a missing key read with dot syntax, and metric
    # responses omit keys freely.
    foreach ($v in @((Get-Key $res 'value'))) {
        if (-not $v) { continue }
        $s = @{ Sum = 0.0; Points = 0; Last = $null; BySplit = @{} }
        foreach ($ts in @((Get-Key $v 'timeseries'))) {
            if (-not $ts) { continue }
            $mv = @((Get-Key $ts 'metadatavalues') | Where-Object { $_ })
            $key = $mv ? [string] (Get-Key $mv[0] 'value') : ''
            foreach ($d in @((Get-Key $ts 'data'))) {
                $x = Get-Key $d $agg
                if ($null -eq $x) { continue }
                $x = [double] $x
                $s.Sum += $x; $s.Points++; $s.Last = $x
                $s.BySplit[$key] = ($s.BySplit[$key] ?? 0.0) + $x
            }
        }
        $out[[string] (Get-Key (Get-Key $v 'name') 'value')] = $s
    }
    return $out
}

# Safe nested read: $null for a missing key or a non-dictionary, never a strict-mode error.
function Get-Key($o, [string] $k) { if ($o -is [System.Collections.IDictionary] -and $o.Contains($k)) { return $o[$k] }; return $null }
function Get-StatSum($stats, [string] $Name) { $x = $stats[$Name]; return $x ? [double] $x.Sum : 0.0 }
function Get-StatLast($stats, [string] $Name) { $x = $stats[$Name]; return ($x -and $null -ne $x.Last) ? [double] $x.Last : 0.0 }
function ConvertTo-GiB([string] $mem) {
    if ($mem -match '^\s*([\d.]+)\s*(Gi|G)?\s*$') { return [double] $Matches[1] }
    if ($mem -match '^\s*([\d.]+)\s*(Mi|M)\s*$') { return [double] $Matches[1] / 1024 }
    return 0.0
}
function Format-Bytes([double] $b) {
    if ($b -ge 1GB) { return '{0:N1} GiB' -f ($b / 1GB) }; if ($b -ge 1MB) { return '{0:N1} MiB' -f ($b / 1MB) }
    if ($b -ge 1KB) { return '{0:N0} KiB' -f ($b / 1KB) }; return '{0:N0} B' -f $b
}

# Metric-confirmed waste types (queries 08-12). Their query rows are candidates: Confirm-Candidate
# turns each into 0..n findings, or drops it when the metrics show it's in use.
$CandidateTypes = @('idle-container-app', 'log-analytics-workspace', 'idle-storage-account', 'idle-container-registry', 'idle-openai-deployment')
$MinAgeDays = 30   # need 30 days of history before calling anything idle

function New-FindingFrom($row, [hashtable] $Set) {
    $f = [ordered]@{}; foreach ($k in $row.Keys) { if ($k -ne 'checkInputs') { $f[$k] = $row[$k] } }
    foreach ($k in $Set.Keys) { $f[$k] = $Set[$k] }
    return $f
}

function Confirm-Candidate($r) {
    $ci = (Get-Key $r 'checkInputs') ?? @{}
    $young = ($null -ne $r.ageDays -and [int] $r.ageDays -lt $MinAgeDays)
    switch ($r.wasteType) {
        'idle-container-app' {
            $m = Get-MetricStats $r.id @('Requests', 'RxBytes', 'TxBytes') 'Total'
            $req = Get-StatSum $m 'Requests'; $net = (Get-StatSum $m 'RxBytes') + (Get-StatSum $m 'TxBytes')
            if ($req -gt 0 -or $net -gt 100MB) { return @() }
            $http = [bool] $ci.hasIngress -and $ci.transport -ne 'Tcp'
            $dedicated = $ci.workloadProfile -and $ci.workloadProfile -ne 'Consumption'
            $conf = ($http -and -not $dedicated) ? 'high' : 'medium'
            $why = "minReplicas $($ci.minReplicas) keeps replicas running, but there were $([int] $req) requests and $(Format-Bytes $net) of network traffic in 30 days"
            if (-not $http) { $why += '; no HTTP ingress, so this is judged by network traffic only (a quiet background worker looks the same)' }
            if ($dedicated) { $why += "; runs on dedicated workload profile '$($ci.workloadProfile)', billed per node, not per app" }
            return @(New-FindingFrom $r @{ confidence = $conf; reason = $why; idleDays = 30; idleSource = 'Requests/RxBytes/TxBytes metrics, 30 days'
                                           cpu = [double] $ci.cpu; memGiB = (@($ci.memory) | ForEach-Object { ConvertTo-GiB $_ } | Measure-Object -Sum).Sum
                                           minReplicas = [int] $ci.minReplicas; dedicated = $dedicated })
        }
        'log-analytics-workspace' {
            $m = Get-MetricStats $r.id @('Ingestion Volume', 'Query Count') 'Count'
            $records = Get-StatSum $m 'Ingestion Volume'; $queries = Get-StatSum $m 'Query Count'
            $problems = @(); $conf = 'low'
            if ([int] $ci.retention -gt [int] $ci.freeRetention) {
                $sentinelNote = [bool] $ci.sentinel ? ' with Sentinel' : ''
                $problems += "retention is $($ci.retention) days, above the free $($ci.freeRetention) days$sentinelNote"
            }
            if ($records -gt 0 -and $queries -eq 0 -and -not $young) {
                $problems += "$('{0:N0}' -f $records) records ingested in 30 days but 0 queries, including alert queries"
                $conf = 'medium'
            }
            if (-not $problems) { return @() }
            $why = ($problems -join '; ') + '. Cost depends on GB ingested and retained, which platform metrics do not expose (see the workspace''s Usage and estimated costs page).'
            if ($problems.Count -eq 1 -and $problems[0] -like 'retention*') { $why += ' Longer retention may be a compliance requirement.' }
            return @(New-FindingFrom $r @{ confidence = $conf; reason = $why; idleDays = $null; idleSource = 'Ingestion Volume/Query Count metrics, 30 days'
                                           records = $records; queries = $queries })
        }
        'idle-storage-account' {
            if ($young) { return @() }
            $tx = Get-StatSum (Get-MetricStats $r.id @('Transactions') 'Total') 'Transactions'
            $usedBytes = Get-StatLast (Get-MetricStats $r.id @('UsedCapacity') 'Average' 'PT1H' 2) 'UsedCapacity'
            $mounts = @($ci.fileMountApps | Where-Object { $_ })
            $sameRg = @($mounts | Where-Object { $_.rg -eq ([string] $r.resourceGroup).ToLower() } | ForEach-Object { $_.name })
            $tierName = [string] $ci.accessTier
            if ($tx -eq 0) {
                $conf = ($tierName -in 'Cool', 'Cold', 'Archive') ? 'medium' : 'high'
                $why = "0 transactions on any service (blob, file, queue, table) in 30 days; $(Format-Bytes $usedBytes) stored"
                if ($conf -eq 'medium') { $why += "; $tierName tier, so this may be intentional cold storage" }
                if ($sameRg) { $conf = 'low'; $why += "; Container App(s) in the same resource group mount an Azure Files volume ($($sameRg -join ', ')). This account may be their data store, idle only because the app is scaled to zero." }
                elseif ($mounts) { $conf = ($conf -eq 'high') ? 'medium' : 'low'; $why += "; Container Apps in this subscription mount Azure Files volumes ($(@($mounts | ForEach-Object { $_.name }) -join ', ')). Check that none use this account." }
                return @(New-FindingFrom $r @{ confidence = $conf; reason = $why; idleDays = 30; idleSource = 'Transactions metric, 30 days'
                                               sizeGb = [math]::Round($usedBytes / 1GB, 2); usedGiB = $usedBytes / 1GB; mounted = [bool] $sameRg })
            }
            if ($tierName -eq 'Hot' -and $ci.kind -ne 'FileStorage') {
                $blobId = "$($r.id)/blobServices/default"
                $blobGiB = (Get-StatLast (Get-MetricStats $blobId @('BlobCapacity') 'Average' 'PT1H' 2) 'BlobCapacity') / 1GB
                if ($blobGiB -lt 100) { return @() }
                $reads = Get-StatSum (Get-MetricStats $blobId @('Transactions') 'Total' -Filter "ApiName eq 'GetBlob'") 'Transactions'
                if ($reads -gt 0) { return @() }
                $why = "$('{0:N0}' -f $blobGiB) GiB of blob data on the Hot tier with 0 GetBlob reads in 30 days. Cool stores it for less (reads cost more, and there's a 30-day minimum)"
                return @(New-FindingFrom $r @{ wasteType = 'hot-blob-unread'; confidence = 'medium'; reason = $why; idleDays = 30; idleSource = 'GetBlob transactions, 30 days'
                                               sizeGb = [math]::Round($blobGiB, 1); usedGiB = $blobGiB })
            }
            return @()
        }
        'idle-container-registry' {
            if ($young) { return @() }
            $pulls = Get-StatSum (Get-MetricStats $r.id @('TotalPullCount') 'Total') 'TotalPullCount'
            $storeGiB = (Get-StatLast (Get-MetricStats $r.id @('StorageUsed') 'Average' 'PT1H' 2) 'StorageUsed') / 1GB
            $refs = @($ci.referencedBy | Where-Object { $_ })
            $repl = [int] ($ci.replications ?? 0)
            if ($pulls -eq 0) {
                $conf = $refs ? 'low' : 'high'
                $why = "0 image pulls by any client in 30 days; $('{0:N1}' -f $storeGiB) GiB stored"
                if ($repl) { $why += "; $repl geo-replication(s), each billed" }
                if ($refs) { $why += "; still referenced by Container App(s) $($refs -join ', '). Scale-to-zero apps only pull when a replica starts, so deleting it would break the next scale-up." }
                return @(New-FindingFrom $r @{ confidence = $conf; reason = $why; idleDays = 30; idleSource = 'TotalPullCount metric, 30 days'
                                               sizeGb = [math]::Round($storeGiB, 1); storeGiB = $storeGiB; replications = $repl })
            }
            if ($r.sku -eq 'Premium' -and $repl -eq 0 -and [int] ($ci.privateEndpoints ?? 0) -eq 0 -and $storeGiB -le 100) {
                $why = "Premium registry with no geo-replications, no private endpoints and $('{0:N1}' -f $storeGiB) GiB stored, which fits Standard's 100 GiB included storage. Check for other Premium-only features (content trust, dedicated data endpoints, connected registries) first"
                return @(New-FindingFrom $r @{ wasteType = 'oversized-container-registry'; confidence = 'medium'; reason = $why
                                               idleDays = $null; idleSource = "$([int] $pulls) pulls in 30 days (in use)"; sizeGb = [math]::Round($storeGiB, 1); storeGiB = $storeGiB })
            }
            return @()
        }
        'idle-openai-deployment' {
            $deps = @(Invoke-AzRead @('cognitiveservices', 'account', 'deployment', 'list', '-g', $r.resourceGroup, '-n', $r.name, '--subscription', $r.subscriptionId))
            # Only names, SKU and model are read from each deployment, never anything else
            $info = foreach ($d in $deps) {
                if (-not $d) { continue }
                $skuN = [string] (Get-Key (Get-Key $d 'sku') 'name')
                $model = [string] (Get-Key (Get-Key (Get-Key $d 'properties') 'model') 'name')
                [pscustomobject] @{ Name = [string] (Get-Key $d 'name'); Sku = $skuN; Model = $model
                    Capacity = [int] ((Get-Key (Get-Key $d 'sku') 'capacity') ?? 0)
                    Created = [string] (Get-Key (Get-Key $d 'systemData') 'createdAt')
                    Ptu = $skuN -like '*Provisioned*'; FineTuned = $model -match '\.ft-|^ft:' }
            }
            $billable = @($info | Where-Object { $_.Ptu -or $_.FineTuned })
            if (-not $billable) { return @() }
            $m = Get-MetricStats $r.id @('AzureOpenAIRequests') 'Total' -Filter "ModelDeploymentName eq '*'"
            $byDep = $m['AzureOpenAIRequests'] ? $m['AzureOpenAIRequests'].BySplit : @{}
            $out = @()
            foreach ($d in $billable) {
                $reqs = [double] ($byDep[$d.Name] ?? 0)
                if ($reqs -gt 0) { continue }
                $ageD = $d.Created ? [int] ($Now - [DateTimeOffset]::Parse($d.Created, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime).TotalDays : $null
                $billing = $d.Ptu ? "$($d.Capacity) PTU of $($d.Sku)" : 'fine-tuned model hosting'
                $conf = ($null -ne $ageD -and $ageD -lt $MinAgeDays) ? 'medium' : 'high'
                $why = "Deployment '$($d.Name)' (model $($d.Model)) bills hourly for $billing but had 0 requests in 30 days"
                if ($d.Ptu) { $why += '. If a PTU reservation covers it, the commitment is already paid, but the capacity is still unused' }
                if ($conf -eq 'medium') { $why += "; created $ageD day(s) ago" }
                $out += New-FindingFrom $r @{ id = "$($r.id)/deployments/$($d.Name)"; name = "$($r.name)/$($d.Name)"; type = 'microsoft.cognitiveservices/accounts/deployments'
                    sku = $d.Sku; tier = $d.Ptu ? 'provisioned' : 'fine-tuned'; sizeGb = $d.Capacity; extra = $d.Model
                    createdTime = $d.Created; ageDays = $ageD; idleDays = [math]::Min(30, ($ageD ?? 30)); idleSource = 'AzureOpenAIRequests by deployment, 30 days'
                    confidence = $conf; reason = $why; ptu = $d.Ptu; capacity = $d.Capacity }
            }
            return $out
        }
    }
    return @()
}

# Actual cost per resource over the last 30 days, keyed by lower-case resource ID.
function Add-BilledCosts([string] $SubscriptionId, [hashtable] $Billed) {
    $usage = Invoke-AzRead @('consumption', 'usage', 'list', '--subscription', $SubscriptionId,
        '--start-date', $Now.AddDays(-30).ToString('yyyy-MM-dd'), '--end-date', $Now.ToString('yyyy-MM-dd'))
    $n = 0; $total = 0
    foreach ($u in @($usage)) {
        if ($u) { $total++ }
        # Index access: some billing schemas omit these keys entirely
        $iid = Get-Key $u 'instanceId'; $cost = Get-Key $u 'pretaxCost'
        if (-not $iid -or $null -eq $cost -or [string] $cost -eq 'None') { continue }
        $key = ([string] $iid).ToLower()
        if (-not $Billed.ContainsKey($key)) { $Billed[$key] = @{ Cost = 0.0; Days = [Collections.Generic.HashSet[string]]::new(); Currency = '' } }
        $e = $Billed[$key]
        $e.Cost += [double] $cost
        $start = Get-Key $u 'usageStart'; $cur = Get-Key $u 'currency'
        if ($start) { [void] $e.Days.Add(([string] $start).Substring(0, 10)) }
        if ($cur) { $e.Currency = [string] $cur }
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

            # Confirm metric-based candidates (queries 08-12) in this tenant's context. A candidate
            # becomes 0..n findings; one the metrics show is in use is dropped. Ignored rows are kept
            # so they still count as excluded.
            $cands = @($passRows | Where-Object { $_.wasteType -in $CandidateTypes -and -not [bool] $_.ignored })
            if ($cands -and -not $SkipMetrics) { Write-Host "  checking $($cands.Count) candidate(s) against 30 days of metrics ..." }
            $confirmed = [Collections.Generic.List[object]]::new()
            foreach ($row in $passRows) {
                if ($row.wasteType -notin $CandidateTypes -or [bool] $row.ignored) { $confirmed.Add($row); continue }
                if (-not $CandidateStats.ContainsKey($row.wasteType)) { $CandidateStats[$row.wasteType] = @{ checked = 0; flagged = 0; skipped = 0; failed = 0 } }
                $st = $CandidateStats[$row.wasteType]
                if ($SkipMetrics) { $st.skipped++; continue }
                $st.checked++
                try { foreach ($fnd in @(Confirm-Candidate $row)) { if ($fnd) { $confirmed.Add($fnd); $st.flagged++ } } }
                catch { $st.failed++; $warnings.Add("Couldn't check $($row.name) ($($row.wasteType)), so it's not in this report: $($_.Exception.Message)") }
            }
            $passRows = $confirmed

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
    'idle-container-app'         = 'Idle Container Apps with always-on replicas'
    'log-analytics-workspace'    = 'Log Analytics: paid retention or unqueried data'
    'idle-storage-account'       = 'Idle storage accounts'
    'hot-blob-unread'            = 'Hot-tier blob data nobody reads'
    'idle-container-registry'    = 'Idle container registries'
    'oversized-container-registry' = 'Premium container registries not using Premium'
    'idle-openai-deployment'     = 'Idle Azure OpenAI deployments that bill hourly'
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
        'idle-container-app' {
            if ($f.dedicated) { return $null }
            $cf = "serviceName eq 'Azure Container Apps' and armRegionName eq '$rg'"
            $pv = Get-MeterPrice $cf { $_.meterName -eq 'Standard vCPU Idle Usage' -and $_.unitOfMeasure -eq '1 Second' }
            $pm = Get-MeterPrice $cf { $_.meterName -eq 'Standard Memory Idle Usage' -and $_.unitOfMeasure -eq '1 GiB Second' }
            if ($null -ne $pv -and $null -ne $pm) { return @{ Cost = Get-ContainerAppIdleCost $f $pv $pm; Note = "idle-rate list price x$($f.minReplicas) replica(s), $region; upper bound, free grant not applied" } }
        }
        { $_ -in 'idle-storage-account', 'hot-blob-unread' } {
            if ($sku -like 'Premium*') { return $null }
            $redName = Get-StorageRedundancyName $sku
            $items = @(Get-RetailItems "serviceName eq 'Storage' and armRegionName eq '$rg' and productName eq 'General Block Blob v2' and (meterName eq 'Hot $redName Data Stored' or meterName eq 'Cool $redName Data Stored' or meterName eq 'Cold $redName Data Stored')")
            $price = @{}
            foreach ($t in 'Hot', 'Cool', 'Cold') {
                $it = $items | Where-Object { $_.meterName -eq "$t $redName Data Stored" -and $_.unitOfMeasure -eq '1 GB/Month' } | Sort-Object { [double] $_.tierMinimumUnits } | Select-Object -First 1
                if ($it) { $price[$t] = [double] $it.retailPrice }
            }
            if ($f.wasteType -eq 'hot-blob-unread') {
                if ($price['Hot'] -and $price['Cool']) { return @{ Cost = $f.usedGiB * ($price['Hot'] - $price['Cool']); Note = "Hot minus Cool $redName list price, $region" } }
            }
            else {
                $t = $f.tier ? [string] $f.tier : 'Hot'
                if ($price[$t]) { return @{ Cost = $f.usedGiB * $price[$t]; Note = "all capacity at blob $t $redName list price, $region; approximate" } }
            }
        }
        { $_ -in 'idle-container-registry', 'oversized-container-registry' } {
            $items = @(Get-RetailItems "serviceName eq 'Container Registry' and armRegionName eq '$rg'")
            $unit = @{}
            foreach ($s in 'Basic', 'Standard', 'Premium') {
                $it = $items | Where-Object { $_.meterName -eq "$s Registry Unit" -and $_.unitOfMeasure -eq '1/Day' } | Select-Object -First 1
                if ($it) { $unit[$s] = [double] $it.retailPrice }
            }
            $stor = $items | Where-Object { $_.meterName -eq 'Data Stored' -and $_.skuName -eq $sku -and $_.unitOfMeasure -eq '1 GB/Month' } | Select-Object -First 1
            $repl = $items | Where-Object { $_.meterName -eq 'Premium Registry Replication Unit' -and $_.unitOfMeasure -eq '1/Day' } | Select-Object -First 1
            if ($f.wasteType -eq 'oversized-container-registry') {
                if ($unit['Premium'] -and $unit['Standard']) { return @{ Cost = ($unit['Premium'] - $unit['Standard']) * 30; Note = "Premium minus Standard list price, $region" } }
            }
            elseif ($unit[$sku]) {
                $c = Get-RegistryCost $f $unit[$sku] ($stor ? [double] $stor.retailPrice : 0.1) ($repl ? [double] $repl.retailPrice : 0)
                return @{ Cost = $c; Note = "$sku registry list price incl. storage over the included amount, $region" }
            }
        }
        'idle-openai-deployment' {
            if (-not $f.ptu) { return $null }   # fine-tuned hosting is priced per model: pricing.json
            $meter = @{ ProvisionedManaged = 'Provisioned Managed Regional Unit'; GlobalProvisionedManaged = 'Provisioned Managed Global Unit'; DataZoneProvisionedManaged = 'Provisioned Managed Data Zone Unit' }[$sku]
            if (-not $meter) { return $null }
            $it = @(Get-RetailItems "serviceName eq 'Foundry Models' and armRegionName eq '$rg' and productName eq 'Azure OpenAI' and meterName eq '$meter'") |
                Where-Object { $_.unitOfMeasure -eq '1/Hour' } | Select-Object -First 1
            if ($it) { return @{ Cost = [double] $it.retailPrice * $hours * $f.capacity; Note = "$($f.capacity) PTU x $meter list price, $region" } }
        }
    }
    return $null
}

# One meter's price in $Currency, or $null when not found. The API rounds very small per-second
# prices to 0 in every currency except USD (Container Apps idle: USD 0.000003, CAD 0), so a zero
# price that's non-zero in USD is replaced by USD x the price-list exchange rate.
function Get-MeterPrice([string] $Filter, [scriptblock] $Match) {
    $it = @(Get-RetailItems $Filter) | Where-Object $Match | Select-Object -First 1
    if (-not $it) { return $null }
    $p = [double] $it.retailPrice
    if ($p -eq 0 -and $Currency -ne 'USD') {
        $usd = @(Get-RetailItems $Filter 'USD') | Where-Object $Match | Select-Object -First 1
        $rate = Get-FxRate 'USD'
        if ($usd -and [double] $usd.retailPrice -gt 0 -and $null -ne $rate) { $p = [double] $usd.retailPrice * $rate }
    }
    return $p
}

# Shared cost formulas, used with live prices and with pricing.json fallbacks
function Get-ContainerAppIdleCost($f, [double] $perVcpuSecond, [double] $perGiBSecond) {
    return [double] $f.minReplicas * ([double] $f.cpu * $perVcpuSecond + [double] $f.memGiB * $perGiBSecond) * 30 * 86400
}
function Get-RegistryCost($f, [double] $unitPerDay, [double] $perGbMonth, [double] $replUnitPerDay) {
    $included = @{ Basic = 10; Standard = 100; Premium = 500 }[[string] $f.sku] ?? 0
    return $unitPerDay * 30 + [math]::Max(0, [double] $f.storeGiB - $included) * $perGbMonth + [int] $f.replications * $replUnitPerDay * 30
}
function Get-StorageRedundancyName([string] $sku) {
    $r = ($sku -split '_')[-1].ToUpper()
    return @{ RAGRS = 'RA-GRS'; RAGZRS = 'RA-GZRS' }[$r] ?? $r
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
        'idle-container-app' {
            if ($f.dedicated) { return @{ Cost = $null; Note = 'dedicated workload profile, billed per node' } }
            $p = $Pricing.containerApps
            return @{ Cost = Get-ContainerAppIdleCost $f $p.idlePerVcpuSecond $p.idlePerGiBSecond; Note = "idle-rate list price x$($f.minReplicas) replica(s); upper bound, free grant not applied" }
        }
        'log-analytics-workspace' { return @{ Cost = $null; Note = 'GB ingested and retained not exposed by metrics' } }
        { $_ -in 'idle-storage-account', 'hot-blob-unread' } {
            if ($sku -like 'Premium*') { return @{ Cost = $null; Note = 'premium storage is priced by provisioned size' } }
            $p = $Pricing.storagePerGb
            $mult = $p.redundancyMultiplier[(Get-StorageRedundancyName $sku)] ?? 1
            if ($f.wasteType -eq 'hot-blob-unread') { return @{ Cost = $f.usedGiB * ($p.Hot - $p.Cool) * $mult; Note = 'Hot minus Cool list price' } }
            $t = $f.tier ? [string] $f.tier : 'Hot'
            return @{ Cost = $f.usedGiB * ($p[$t] ?? $p.Hot) * $mult; Note = "all capacity at blob $t list price; approximate" }
        }
        'idle-container-registry' {
            $p = $Pricing.containerRegistries
            $unit = $p.unitPerDay[$sku]
            if ($null -eq $unit) { return @{ Cost = $null; Note = "no list price for $sku" } }
            return @{ Cost = Get-RegistryCost $f $unit $p.storagePerGbMonth $p.replicationUnitPerDay; Note = "$sku registry list price incl. storage over the included amount" }
        }
        'oversized-container-registry' {
            $p = $Pricing.containerRegistries
            return @{ Cost = ($p.unitPerDay['Premium'] - $p.unitPerDay['Standard']) * 30; Note = 'Premium minus Standard list price' }
        }
        'idle-openai-deployment' {
            $p = $Pricing.openAI
            if ($f.ptu) {
                $rate = $p.ptuPerHour[$sku]
                if ($null -eq $rate) { return @{ Cost = $null; Note = "no list price for $sku" } }
                return @{ Cost = $rate * $Pricing.hoursPerMonth * $f.capacity; Note = "$($f.capacity) PTU x $sku list price" }
            }
            return @{ Cost = $p.fineTunedHostingPerHour * $Pricing.hoursPerMonth; Note = 'typical fine-tuned hosting rate; varies by model' }
        }
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
        'idle-container-app' { return @(
            "Set minReplicas to 0 so it scales to zero when idle (the first request after idle then has a cold start), or delete the app if it's no longer needed.",
            "az containerapp update --ids $id --min-replicas 0") }
        'log-analytics-workspace' { return @(
            "Check the workspace's Usage and estimated costs page for the real GB and cost. Lower retention to the free period unless a compliance rule needs more (or move old data to the cheaper long-term/archive tier). If nobody queries the data, stop sending it (diagnostic settings, data collection rules) or delete the workspace.",
            "az monitor log-analytics workspace update --ids $id --retention-time 31") }
        'idle-storage-account' {
            if ($f.mounted) { return @(
                "Do NOT delete before confirming what uses it. A Container App in the same resource group mounts an Azure Files volume and this may be its data. If it is, it's not waste. Tag it waste-hunter:ignore=true to stop it being reported.",
                '') }
            return @("Confirm with $who that nothing reads or writes it (apps, Functions, backups, scripts) and that its data isn't needed. Then delete it, or move the data to Cool or Archive if it must be kept.",
                     "az storage account delete --ids $id") }
        'hot-blob-unread' { return @(
            "Move it to the Cool tier: change the account's default tier, or add a lifecycle rule that tiers blobs not accessed for 30 days. Cool has a 30-day minimum and higher read cost, so skip this if reads are about to start.",
            "az storage account update --ids $id --access-tier Cool") }
        'idle-container-registry' {
            if ($f.confidence -eq 'low') { return @(
                'Keep it while the referencing Container App(s) exist. They pull from it when a replica starts. If those apps are retired, delete the registry along with them.',
                '') }
            return @("Confirm with $who that no pipeline or cluster pulls from it, export any images you need, then delete it.",
                     "az acr delete --ids $id") }
        'oversized-container-registry' { return @(
            'Downgrade to Standard if you rely on none of geo-replication, private endpoints, content trust, dedicated data endpoints or connected registries.',
            "az acr update --ids $id --sku Standard") }
        'idle-openai-deployment' { return @(
            "Delete the deployment (re-create it when needed). For PTU, also check whether a reservation covers it before you rely on the saving.",
            "az cognitiveservices account deployment delete -g $($f.resourceGroup) -n $(($f.name -split '/')[0]) --deployment-name $(($f.name -split '/')[-1]) --subscription $($f.subscriptionId)") }
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
# A group's cost for display: unknown costs say so instead of reading as 0.00
function Format-GroupCost($items) {
    $items = @($items)
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
# The headline adds every finding, including low-confidence ones whose advice may be "keep it", so
# show the high-confidence part separately.
$highTotals = Get-Totals @($findings | Where-Object { $_.confidence -eq 'high' })
L "High confidence: **$(Format-Money $highTotals)**. The rest needs a check before acting (see each finding's confidence and reason)."
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
    $gc = $g.Items.Count ? (Format-GroupCost $g.Items) : '-'
    L "| $($TypeInfo[$t]) | $($g.Items.Count) | $gc | $($c.high) | $($c.medium) | $($c.low) | $($excluded[$t] ?? 0) |"
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
if ($CandidateStats.Count) {
    $parts = foreach ($k in $CandidateTypes) { $s = $CandidateStats[$k]; if ($s) {
        $unit = ($k -eq 'idle-openai-deployment') ? 'account(s)' : 'resource(s)'
        "$($TypeInfo[$k]): $($s.checked) $unit checked, $($s.flagged) finding(s)$($s.failed ? ", $($s.failed) failed" : '')$($s.skipped ? ", $($s.skipped) not checked" : '')" } }
    L ''
    L ('Metric checks (queries 08-12; a candidate is only reported when 30 days of metrics confirm it): ' + (@($parts) -join '; ') + '.')
}
$notChecked = ($CandidateStats.Values | ForEach-Object { $_.skipped } | Measure-Object -Sum).Sum
if ($notChecked) { $warnings.Add("$notChecked candidate(s) from queries 08-12 were not checked because of -SkipMetrics. Those waste types need metrics, so they're missing from this report.") }
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
Write-Host "Estimated monthly savings: $(Format-Money $totals), high confidence $(Format-Money $highTotals)  ($($findings.Count) findings, $([int] $exclTotal) excluded)"
foreach ($c in $coverage) { if ($c.Status -ne 'ok') { Write-Host "Tenant $($c.Tenant): $($c.Status)" -ForegroundColor Yellow } }
Write-Host "Report: $mdPath"
Write-Host "CSV:    $csvPath"
