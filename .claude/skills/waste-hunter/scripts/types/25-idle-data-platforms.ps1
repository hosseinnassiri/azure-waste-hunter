# waste-hunter 25 · Data platforms left running (CANDIDATES, confirmed by metrics)
# Waste-type record(s) for queries/25-idle-data-platforms.kql: label, flags and the logic for each step. Loaded by
# Import-WasteTypes (lib/WasteTypes.ps1). The script blocks run inside Confirm-Candidate, Get-LivePrice,
# Get-Estimate and Get-Action (lib/WasteTypes.ps1) and use the variables those set up there.

@{
    Name = 'idle-data-platform'
    Label = 'Idle Fabric, Power BI Embedded, Synapse and Data Explorer compute'
    Order = 25
    Candidate = $true
    CommitmentEligible = $true   # Fabric, Synapse and Data Explorer have reservations
    QuickWin = $true             # pausing or stopping keeps the data and can be undone
    Check = {
        if ($young) { return @() }
        switch ([string] $ci.platform) {
            'fabric' {
                # No Azure Monitor usage metric for Fabric capacities (usage is in the Capacity Metrics app)
                $why = "Fabric capacity $($r.sku) is Active and bills every hour whether or not workloads run. Azure Monitor has no usage metric for Fabric, so usage isn't verified here: check the Fabric Capacity Metrics app"
                return @(New-FindingFrom $r @{ confidence = 'low'; reason = $why; idleSource = 'not measurable (no Azure Monitor metric for Fabric)'; platform = 'fabric' })
            }
            'powerbi' {
                # cpu_metric exists for Gen2 capacities only. No data means Gen1 or no activity at all,
                # which can't be told apart, so that case is low confidence.
                $cpu = (Get-MetricStats $r.id @('cpu_metric') 'Average' 'PT1H')['cpu_metric']
                if (-not $cpu -or -not $cpu.Points) {
                    $why = "Power BI Embedded capacity $($r.sku) is running and bills every hour, but reports no CPU data (a Gen1 capacity, or no activity at all), so usage isn't verified here: check the Fabric Capacity Metrics app"
                    return @(New-FindingFrom $r @{ confidence = 'low'; reason = $why; idleSource = 'no CPU data (cpu_metric, Gen2 only)'; platform = 'powerbi' })
                }
                if ($cpu.Max -ge 1) { return @() }
                $why = ('Power BI Embedded capacity {0} averaged under {1:N1}% CPU in its busiest hour over 30 days, but bills every hour until it''s paused' -f $r.sku, [math]::Max(0.1, $cpu.Max))
                if ($cpu.Max -eq 0) { $why = "Power BI Embedded capacity $($r.sku) used 0% CPU in every hour over 30 days, but bills every hour until it's paused" }
                return @(New-FindingFrom $r @{ confidence = ($cpu.Max -eq 0) ? 'high' : 'medium'; reason = $why; idleDays = 30; idleSource = 'cpu_metric (hourly average), 30 days'; platform = 'powerbi' })
            }
            'synapse' {
                $m = Get-MetricStats $r.id @('Connections', 'ActiveQueries') 'Total'
                $conns = Get-StatSum $m 'Connections'; $queries = Get-StatSum $m 'ActiveQueries'
                if ($conns -gt 0 -or $queries -gt 0) { return @() }
                $why = "Dedicated SQL pool $($r.sku) is Online with 0 connections and 0 queries in 30 days, but compute bills every hour until it's paused"
                return @(New-FindingFrom $r @{ confidence = 'high'; reason = $why; idleDays = 30; idleSource = 'Connections and ActiveQueries metrics, 30 days'; platform = 'synapse' })
            }
            'kusto' {
                $ingest = Get-StatSum (Get-MetricStats $r.id @('IngestionVolumeInMB') 'Total') 'IngestionVolumeInMB'
                $queries = Get-StatSum (Get-MetricStats $r.id @('QueryResult') 'Count') 'QueryResult'
                if ($queries -gt 0) { return @() }
                $n = [int] ($ci.instances ?? 1)
                if ($ingest -gt 0) {
                    $why = ('Data Explorer cluster ({0} x {1}) ingested {2:N0} MB but answered 0 queries in 30 days: data goes in and nobody reads it' -f $n, $r.sku, $ingest)
                    return @(New-FindingFrom $r @{ confidence = 'medium'; reason = $why; idleDays = 30; idleSource = 'QueryResult and IngestionVolumeInMB metrics, 30 days'; platform = 'kusto'; instances = $n })
                }
                $why = "Data Explorer cluster ($n x $($r.sku)) had 0 queries and no ingestion in 30 days, but its VMs bill every hour until it's stopped"
                return @(New-FindingFrom $r @{ confidence = 'high'; reason = $why; idleDays = 30; idleSource = 'QueryResult and IngestionVolumeInMB metrics, 30 days'; platform = 'kusto'; instances = $n })
            }
        }
        return @()
    }
    LivePrice = {
        if ($f.platform -eq 'powerbi') {
            $p = Get-MeterPrice "serviceName eq 'Power BI Embedded' and armRegionName eq '$rg' and skuName eq '$(Get-ODataLiteral $sku)'" { $_.meterName -eq "$sku Node" -and $_.unitOfMeasure -eq '1 Hour' }
            if ($null -ne $p) { return @{ Cost = $p * $hours; Note = "$sku Power BI Embedded list price, $region" } }
        }
        if ($f.platform -eq 'synapse') {
            $p = Get-MeterPrice "serviceName eq 'Azure Synapse Analytics' and armRegionName eq '$rg' and productName eq 'Azure Synapse Analytics Dedicated SQL Pool' and skuName eq '$(Get-ODataLiteral $sku)'" { $_.meterName -eq '100 DWUs' -and $_.unitOfMeasure -eq '1/Hour' }
            if ($null -ne $p) { return @{ Cost = $p * $hours; Note = "$sku dedicated SQL pool list price, $region" } }
        }
        if ($f.platform -eq 'kusto' -and $sku -match '(Standard_[A-Za-z0-9_]+)') {
            $vmSize = $Matches[1]; $sh = Get-VmShape $vmSize
            $vm = Get-VmHourlyPrice $vmSize $region $false
            $markup = Get-MeterPrice "serviceName eq 'Azure Data Explorer' and armRegionName eq '$rg'" { $_.meterName -eq 'Standard Engine Cluster Markup' -and $_.unitOfMeasure -eq '1 Hour' }
            if ($sh -and $null -ne $vm -and $null -ne $markup) { return @{ Cost = ($vm + $markup * $sh.Vcpu) * $f.instances * $hours; Note = "$($f.instances) x $vmSize VM plus engine markup list price, $region" } }
        }
        return $null    # Fabric: pricing.json (capacity units x rate)
    }
    Estimate = {
        $p = $Pricing.dataPlatforms
        switch ([string] $f.platform) {
            'fabric' {
                if ($sku -notmatch '^F(\d+)$') { return @{ Cost = $null; Note = "unknown Fabric SKU $sku" } }
                return @{ Cost = [int] $Matches[1] * $p.fabricPerCuHour * $Pricing.hoursPerMonth; Note = "$sku capacity units x pay-as-you-go list price" }
            }
            'powerbi' {
                $rate = Get-Key $p.powerBiEmbeddedPerHour $sku
                if ($null -eq $rate) { return @{ Cost = $null; Note = "no list price for $sku" } }
                return @{ Cost = $rate * $Pricing.hoursPerMonth; Note = "$sku Power BI Embedded list price" }
            }
            'synapse' {
                if ($sku -notmatch '^DW(\d+)c$') { return @{ Cost = $null; Note = "unknown pool size $sku" } }
                return @{ Cost = [int] $Matches[1] / 100 * $p.synapsePer100DwuHour * $Pricing.hoursPerMonth; Note = "$sku dedicated SQL pool list price" }
            }
            'kusto' {
                $vmSize = ($sku -match '(Standard_[A-Za-z0-9_]+)') ? $Matches[1] : $sku
                $vm = Get-VmHourlyEstimate $vmSize $false; $sh = Get-VmShape $vmSize
                if ($null -eq $vm) { return @{ Cost = $null; Note = "unknown cluster size $sku" } }
                return @{ Cost = ($vm + $p.dataExplorerMarkupPerVcpuHour * $sh.Vcpu) * $f.instances * $Pricing.hoursPerMonth; Note = "$($f.instances) x $vmSize VM plus engine markup list price" }
            }
        }
        return @{ Cost = $null; Note = 'unknown platform' }
    }
    Action = {
        switch ([string] $f.platform) {
            'fabric' { return @("Check the Fabric Capacity Metrics app with $who. If the capacity is idle outside working hours, pause it then (a schedule or a pipeline can do it); if it's unused, delete it.", "az fabric capacity suspend --resource-group $($f.resourceGroup) --capacity-name $($f.name)") }
            'powerbi' { return @("Check the capacity's usage with $who (the Fabric Capacity Metrics app). Pause it when nobody views embedded reports (nights, weekends), or delete it if the embedding app is retired. Paused capacities don't bill.", "az powerbi embedded-capacity pause --name $($f.name) --resource-group $($f.resourceGroup)") }
            'synapse' { return @('Pause the pool: storage keeps billing, compute stops, and it resumes in minutes. Delete it if nothing needs the data.', "az synapse sql pool pause --name $(($f.name -split '/')[-1]) --workspace-name $(($f.name -split '/')[0]) --resource-group $($f.resourceGroup)") }
            default { return @("Stop the cluster (data is kept and it can be started again), or confirm with $who that nothing reads it and delete it.", "az kusto cluster stop --name $($f.name) --resource-group $($f.resourceGroup)") }
        }
    }
}
