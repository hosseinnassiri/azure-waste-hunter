# waste-hunter 13 · Load balancers with no backends
# Waste-type record(s) for queries/13-idle-load-balancers.kql: label, flags and the logic for each step. Loaded by
# Import-WasteTypes (lib/Common.ps1). The script blocks run inside Confirm-Candidate, Get-LivePrice,
# Get-Estimate and Get-Action (lib/WasteTypes.ps1) and use the variables those set up there.

@{
    Name = 'idle-load-balancer'
    Label = 'Load balancers with no backends'
    Order = 13
    QuickWin = $true   # reversible, or nothing depends on it: listed under Quick wins when high confidence
    LivePrice = {
        $rules = [int] ($f.sizeGb ?? 0)
        if ($rules -eq 0 -or $sku -notin 'Standard', 'Global') { return $null }
        # Load Balancer and NAT Gateway are priced under armRegionName 'Global' / 'US Gov', not per region
        $lf = "serviceName eq 'Load Balancer' and armRegionName eq '$(Get-PriceZone $region)' and skuName eq '$sku'"
        $inc = Get-MeterPrice $lf { $_.meterName -eq "$sku Included LB Rules and Outbound Rules" }
        $ovr = Get-MeterPrice $lf { $_.meterName -eq "$sku Overage LB Rules and Outbound Rules" }
        if ($null -ne $inc) { return @{ Cost = ($inc + [math]::Max(0, $rules - 5) * ($ovr ?? 0)) * $hours; Note = "$sku rules list price ($rules rule(s))" } }
    }
    Estimate = {
        $rules = [int] ($f.sizeGb ?? 0)
        if ($rules -eq 0) { return @{ Cost = 0.0; Note = 'no rules, no charge' } }
        $p = $Pricing.network.loadBalancer
        return @{ Cost = ($p.includedPerHour + [math]::Max(0, $rules - 5) * $p.overagePerRuleHour) * $Pricing.hoursPerMonth; Note = "Standard rules list price ($rules rule(s))" }
    }
    Action = {
        if ($f.confidence -eq 'low') { return @('No rules, so no charge. Delete it to reduce clutter.', "az network lb delete --ids $id") }
        return @("Confirm with $who that no deployment is about to add backends, then delete it and release its frontend public IPs if they aren't needed.",
                 "az network lb delete --ids $id")
    }
}
