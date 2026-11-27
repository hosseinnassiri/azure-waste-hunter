# waste-hunter 26 · Idle Redis caches: Azure Cache for Redis and Azure Managed Redis (CANDIDATES, confirmed by metrics)
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
        # Both resource types publish connectedclients (Maximum)
        $clients = (Get-MetricStats $r.id @('connectedclients') 'Maximum' 'PT1H')['connectedclients']
        $peak = ($clients -and $null -ne $clients.Max) ? [double] $clients.Max : 0.0
        if ($peak -gt 0) { return @() }
        $units = [int] ($ci.units ?? 1)
        $kind = [bool] $ci.managed ? 'Azure Managed Redis' : 'Azure Cache for Redis'
        $what = switch -Wildcard ([string] $ci.tier) {
            'Enterprise*' { "$units capacity unit(s)" }
            default { [bool] $ci.managed ? (($units -gt 1) ? 'high availability, 2 instances' : '1 instance, no high availability') : (($units -gt 1) ? "$units shards" : '') }
        }
        $why = "No client connected at any point in 30 days ($kind $($ci.tier) $($r.sku)$($what ? ", $what" : '')), but the cache bills every hour"
        return @(New-FindingFrom $r @{ confidence = 'high'; reason = $why; idleDays = 30; idleSource = 'connectedclients metric (hourly maximum), 30 days'
                                       units = $units; managed = [bool] $ci.managed })
    }
    LivePrice = {
        # Price-list product and meter per tier: classic caches bill per cache (x shards), Managed Redis
        # per instance, legacy Enterprise per capacity unit
        $product = @{ Balanced = 'Azure Managed Redis - Balanced'; MemoryOptimized = 'Azure Managed Redis - Memory Optimized'
                      ComputeOptimized = 'Azure Managed Redis - Compute Optimized'; FlashOptimized = 'Azure Managed Redis - Flash Optimized'
                      Enterprise = 'Azure Redis Cache Enterprise'; EnterpriseFlash = 'Azure Redis Cache Enterprise Flash' }[[string] $f.tier] ?? "Azure Redis Cache $($f.tier)"
        $meter = ($f.managed -and $f.tier -notlike 'Enterprise*') ? "$sku Cache Instance" : "$sku Cache"
        $p = Get-MeterPrice "serviceName eq 'Redis Cache' and armRegionName eq '$rg' and productName eq '$(Get-ODataLiteral $product)' and skuName eq '$(Get-ODataLiteral $sku)'" { $_.meterName -eq $meter -and $_.unitOfMeasure -eq '1 Hour' }
        if ($null -ne $p) { return @{ Cost = $p * $f.units * $hours; Note = "$($f.tier) $sku list price$(($f.units -gt 1) ? " x$($f.units)" : ''), $region" } }
    }
    Estimate = {
        $rate = Get-Key (Get-Key $Pricing.redisCache ([string] $f.tier)) $sku
        if ($null -eq $rate) { return @{ Cost = $null; Note = "no list price for $($f.tier) $sku" } }
        return @{ Cost = $rate * $f.units * $Pricing.hoursPerMonth; Note = "$($f.tier) $sku list price$(($f.units -gt 1) ? " x$($f.units)" : '')" }
    }
    Action = {
        $cmd = $f.managed ? "az redisenterprise delete --ids $id" : "az redis delete --ids $id"
        $tip = ($f.managed -and $f.units -eq 2) ? ' If a dev/test copy must stay, turning off high availability halves its price.' : ''
        return @(
            "Confirm with $who that no app uses it (a connection string may sit in an app that's switched off), export the data if it matters, then delete it.$tip",
            $cmd)
    }
}
