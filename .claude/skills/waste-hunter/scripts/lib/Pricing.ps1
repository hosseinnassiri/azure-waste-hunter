# Part of Invoke-WasteHunt.ps1 (dot-sourced into its scope, so it shares the runner's variables).
# READ-ONLY: see CLAUDE.md. Functions only; nothing runs when this file is loaded.

function Get-ODataLiteral([object] $s) { ([string] $s) -replace "'", "''" }

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

function Get-DiskTier($f) {
    $t = $Pricing.disks[([string] $f.sku) -replace '_ZRS$', '_LRS']
    if (-not ($t -is [System.Collections.IDictionary] -and $t.ContainsKey('tiers'))) { return $null }
    $i = [array]::IndexOf($t.tiers, [string] $f.tier)
    if ($i -lt 0) {
        $sizes = $Pricing.disks.tierSizesGb; $i = $sizes.Count - 1
        for ($j = 0; $j -lt $sizes.Count; $j++) { if ([int] $f.sizeGb -le $sizes[$j]) { $i = $j; break } }
    }
    return @{ Name = $t.tiers[$i]; Price = $t.prices[$i]; Index = $i }
}

function Get-PriceZone([string] $region) { return ($region -like 'usgov*') ? 'US Gov' : 'Global' }

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
