# waste-hunter 26 · Idle Azure Cache for Redis (CANDIDATES, confirmed by metrics)
# Waste-type record(s) for queries/26-idle-redis-caches.kql: label, flags and the logic for each step. Loaded by
# Import-WasteTypes (lib/WasteTypes.ps1). The script blocks run inside Confirm-Candidate, Get-LivePrice,
# Get-Estimate and Get-Action (lib/WasteTypes.ps1) and use the variables those set up there.

@{
    Name = 'idle-redis-cache'
    Label = 'Idle Redis caches'
    Order = 26
    Candidate = $true
    CommitmentEligible = $true   # Redis reserved capacity can cover it
    Check = {
        $clients = (Get-MetricStats $r.id @('connectedclients') 'Maximum' 'PT1H')['connectedclients']
        $peak = ($clients -and $null -ne $clients.Max) ? [double] $clients.Max : 0.0
        if ($peak -gt 0) { return @() }
        $shardTxt = ([int] $ci.shards -gt 1) ? ", $($ci.shards) shards" : ''
        $why = "No client connected at any point in 30 days ($($ci.tier) $($r.sku)$shardTxt), but the cache bills every hour"
        return @(New-FindingFrom $r @{ confidence = 'high'; reason = $why; idleDays = 30; idleSource = 'connectedclients metric (hourly maximum), 30 days'; shards = [int] ($ci.shards ?? 1) })
    }
    LivePrice = {
        $p = Get-MeterPrice "serviceName eq 'Redis Cache' and armRegionName eq '$rg' and productName eq 'Azure Redis Cache $(Get-ODataLiteral $f.tier)' and skuName eq '$(Get-ODataLiteral $sku)'" { $_.meterName -eq "$sku Cache" -and $_.unitOfMeasure -eq '1 Hour' }
        if ($null -ne $p) { return @{ Cost = $p * $f.shards * $hours; Note = "$($f.tier) $sku list price$(($f.shards -gt 1) ? " x$($f.shards) shards" : ''), $region" } }
    }
    Estimate = {
        $rate = Get-Key (Get-Key $Pricing.redisCache ([string] $f.tier)) $sku
        if ($null -eq $rate) { return @{ Cost = $null; Note = "no list price for $($f.tier) $sku" } }
        return @{ Cost = $rate * $f.shards * $Pricing.hoursPerMonth; Note = "$($f.tier) $sku list price$(($f.shards -gt 1) ? " x$($f.shards) shards" : '')" }
    }
    Action = {
        return @(
            "Confirm with $who that no app uses it (a connection string may sit in an app that's switched off), export the data if it matters (Premium can export to storage), then delete it.",
            "az redis delete --ids $id")
    }
}
