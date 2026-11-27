# waste-hunter 08 · Idle Container Apps that keep replicas running (CANDIDATES, confirmed by metrics)
# Waste-type record(s) for queries/08-idle-container-apps.kql: label, flags and the logic for each step. Loaded by
# Import-WasteTypes (lib/Common.ps1). The script blocks run inside Confirm-Candidate, Get-LivePrice,
# Get-Estimate and Get-Action (lib/WasteTypes.ps1) and use the variables those set up there.

@{
    Name = 'idle-container-app'
    Label = 'Idle Container Apps with always-on replicas'
    Order = 8
    Candidate = $true
    Check = {
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
    LivePrice = {
        if ($f.dedicated) { return $null }
        $cf = "serviceName eq 'Azure Container Apps' and armRegionName eq '$rg'"
        $pv = Get-MeterPrice $cf { $_.meterName -eq 'Standard vCPU Idle Usage' -and $_.unitOfMeasure -eq '1 Second' }
        $pm = Get-MeterPrice $cf { $_.meterName -eq 'Standard Memory Idle Usage' -and $_.unitOfMeasure -eq '1 GiB Second' }
        if ($null -ne $pv -and $null -ne $pm) { return @{ Cost = Get-ContainerAppIdleCost $f $pv $pm; Note = "idle-rate list price x$($f.minReplicas) replica(s), $region; upper bound, free grant not applied" } }
    }
    Estimate = {
        if ($f.dedicated) { return @{ Cost = $null; Note = 'dedicated workload profile, billed per node' } }
        $p = $Pricing.containerApps
        return @{ Cost = Get-ContainerAppIdleCost $f $p.idlePerVcpuSecond $p.idlePerGiBSecond; Note = "idle-rate list price x$($f.minReplicas) replica(s); upper bound, free grant not applied" }
    }
    Action = {
        return @(
            "Set minReplicas to 0 so it scales to zero when idle (the first request after idle then has a cold start), or delete the app if it's no longer needed.",
            "az containerapp update --ids $id --min-replicas 0")
    }
}
