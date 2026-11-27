# waste-hunter 24 · Over-provisioned Cosmos DB throughput (CANDIDATES, confirmed by metrics)
# Waste-type record(s) for queries/24-overprovisioned-cosmos-db.kql: label, flags and the logic for each step. Loaded by
# Import-WasteTypes (lib/WasteTypes.ps1). The script blocks run inside Confirm-Candidate, Get-LivePrice,
# Get-Estimate and Get-Action (lib/WasteTypes.ps1) and use the variables those set up there.

@{
    Name = 'overprovisioned-cosmos-db'
    Label = 'Over-provisioned Cosmos DB throughput'
    Order = 24
    Candidate = $true
    PartialSaving = $true        # lowering RU/s saves part of the bill; storage keeps billing
    CommitmentEligible = $true   # Cosmos DB reserved capacity can cover it
    QuickWin = $true             # throughput can be raised again at any time
    Check = {
        # RU/s set on each database (shared throughput) and container, as the hourly maximum per scope
        $tp = (Get-MetricStats $r.id @('ProvisionedThroughput') 'Maximum' 'PT1H' -Filter "DatabaseName eq '*' and CollectionName eq '*'")['ProvisionedThroughput']
        $scopes = $tp ? @($tp.MaxBySplit.Keys) : @()
        $prov = $tp ? [double] (($tp.MaxBySplit.Values | Measure-Object -Sum).Sum ?? 0) : 0
        if ($prov -le 0) { return @() }          # nothing provisioned (or no data)
        $nru = (Get-MetricStats $r.id @('NormalizedRUConsumption') 'Maximum' 'PT1H')['NormalizedRUConsumption']
        $peak = ($nru -and $null -ne $nru.Max) ? [double] $nru.Max : 0.0
        if ($peak -ge 10) { return @() }
        # Keep twice the peak, at least 400 RU/s per database or container (the manual minimum)
        $target = [math]::Max(400 * [math]::Max(1, $scopes.Count), [math]::Ceiling($prov * $peak / 100 * 2 / 100) * 100)
        $free = [bool] $ci.freeTier ? $Pricing.cosmosDb.freeTierRu : 0
        $cut = [math]::Max(0, $prov - $free) - [math]::Max(0, $target - $free)   # billable RU/s removed
        if ($cut -lt 400) { return @() }
        $regions = [int] ($ci.regions ?? 1)
        $why = ('{0:N0} RU/s provisioned across {1} database/container scope(s){2}, but the busiest partition peaked at {3:N1}% of it in 30 days (hourly maximum). About {4:N0} RU/s would still leave twice the peak' -f
                $prov, $scopes.Count, (($regions -gt 1) ? " in $regions regions" : ''), $peak, $target)
        if ($peak -eq 0) { $why = ('{0:N0} RU/s provisioned across {1} database/container scope(s), and no request units were consumed in 30 days' -f $prov, $scopes.Count) }
        if ($ci.multiWrite) { $why += '. Multi-region writes bill more per RU/s, so the saving is higher than shown' }
        $why += '. With autoscale, lower the autoscale maximum instead'
        return @(New-FindingFrom $r @{ confidence = ($peak -eq 0) ? 'high' : 'medium'; reason = $why; idleDays = ($peak -eq 0) ? 30 : $null
                                       idleSource = 'ProvisionedThroughput and NormalizedRUConsumption metrics, 30 days'
                                       ruCut = $cut; ruTarget = $target; regions = $regions })
    }
    LivePrice = {
        $p = Get-MeterPrice "serviceName eq 'Azure Cosmos DB' and armRegionName eq '$rg' and skuName eq 'RUs'" { $_.meterName -eq '100 RU/s' -and $_.unitOfMeasure -eq '1/Hour' }
        if ($null -ne $p) { return @{ Cost = $f.ruCut / 100 * $p * $hours * $f.regions; Note = ('{0:N0} RU/s fewer x {1} region(s), manual throughput list price, {2}' -f $f.ruCut, $f.regions, $region) } }
    }
    Estimate = {
        return @{ Cost = $f.ruCut / 100 * $Pricing.cosmosDb.per100RuHour * $Pricing.hoursPerMonth * $f.regions; Note = ('{0:N0} RU/s fewer x {1} region(s), manual throughput list price' -f $f.ruCut, $f.regions) }
    }
    Action = {
        return @(
            ('Lower the provisioned throughput (or the autoscale maximum) to about {0:N0} RU/s in total, then watch for throttled (429) requests. If traffic stays this low, serverless may cost less still.' -f $f.ruTarget),
            "az cosmosdb sql database throughput update -a $($f.name) -g $($f.resourceGroup) -n <database> --throughput <RU/s>   (or: az cosmosdb sql container throughput update ...)")
    }
}
