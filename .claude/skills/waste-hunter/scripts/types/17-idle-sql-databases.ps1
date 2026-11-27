# waste-hunter 17 · Idle Azure SQL databases (CANDIDATES, confirmed by metrics)
# Waste-type record(s) for queries/17-idle-sql-databases.kql: label, flags and the logic for each step. Loaded by
# Import-WasteTypes (lib/Common.ps1). The script blocks run inside Confirm-Candidate, Get-LivePrice,
# Get-Estimate and Get-Action (lib/WasteTypes.ps1) and use the variables those set up there.

@{
    Name = 'idle-sql-database'
    Label = 'Idle SQL databases'
    Order = 17
    Candidate = $true
    CommitmentEligible = $true   # a reservation or savings plan can cover it
    Check = {
        if ($young) { return @() }
        $conns = Get-StatSum (Get-MetricStats $r.id @('connection_successful') 'Total') 'connection_successful'
        if ($conns -gt 0) { return @() }
        $size = $ci.vcores ? "$($ci.vcores) vCore(s)" : $r.sku
        $why = "0 successful connections in 30 days ($($r.sku), $size), but compute bills every hour"
        return @(New-FindingFrom $r @{ confidence = 'high'; reason = $why; idleDays = 30; idleSource = 'connection_successful metric, 30 days'
                                       vcores = [int] ($ci.vcores ?? 0); sqlTier = [string] $ci.tier })
    }
    Estimate = {
        $p = $Pricing.sqlDatabase
        $dtu = $p.dtuPerMonth[$sku]
        if ($null -ne $dtu) { return @{ Cost = $dtu; Note = "$sku list price, compute only (storage extra)" } }
        $vRate = $p.vcorePerHour[[string] $f.sqlTier]
        if ($null -ne $vRate -and $f.vcores) { return @{ Cost = $vRate * $f.vcores * $Pricing.hoursPerMonth; Note = "$($f.vcores) vCore $($f.sqlTier) list price, compute only (storage extra)" } }
        return @{ Cost = $null; Note = "no list price for $sku" }
    }
    Action = {
        return @(
            "Confirm with $who that nothing connects to it on a schedule longer than 30 days, then export a .bacpac or check backup retention and delete it. If it must stay online, move it to serverless with auto-pause.",
            "az sql db delete --ids $id")
    }
}
