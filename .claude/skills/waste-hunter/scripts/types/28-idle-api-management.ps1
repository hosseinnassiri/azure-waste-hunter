# waste-hunter 28 · Idle API Management instances (CANDIDATES, confirmed by metrics)
# Waste-type record(s) for queries/28-idle-api-management.kql: label, flags and the logic for each step. Loaded by
# Import-WasteTypes (lib/WasteTypes.ps1). The script blocks run inside Confirm-Candidate, Get-LivePrice,
# Get-Estimate and Get-Action (lib/WasteTypes.ps1) and use the variables those set up there.

@{
    Name = 'idle-api-management'
    Label = 'Idle API Management instances'
    Order = 28
    Candidate = $true
    Check = {
        if ($young) { return @() }
        $reqs = Get-StatSum (Get-MetricStats $r.id @('Requests') 'Total') 'Requests'
        if ($reqs -gt 0) { return @() }
        $extra = ([int] $ci.regions -gt 1) ? " in $($ci.regions) regions" : ''
        $why = "0 gateway requests in 30 days ($($r.sku), $($ci.units) unit(s)$extra), but every unit bills hourly"
        return @(New-FindingFrom $r @{ confidence = 'high'; reason = $why; idleDays = 30; idleSource = 'Requests metric, 30 days'
                                       units = [int] ($ci.units ?? 1); regions = [int] ($ci.regions ?? 1) })
    }
    LivePrice = {
        $meterSku = @{ BasicV2 = 'Basic v2'; StandardV2 = 'Standard v2'; PremiumV2 = 'Premium v2' }[$sku] ?? $sku
        $p = Get-MeterPrice "serviceName eq 'API Management' and armRegionName eq '$rg' and skuName eq '$(Get-ODataLiteral $meterSku)'" { $_.meterName -eq "$meterSku Unit" -and $_.unitOfMeasure -eq '1 Hour' }
        # Extra regions are Premium only and bill a unit each; counted at the primary region's rate
        if ($null -ne $p) { return @{ Cost = $p * $f.units * $f.regions * $hours; Note = "$meterSku x$($f.units) unit(s)$(($f.regions -gt 1) ? " x$($f.regions) regions" : '') list price, $region" } }
    }
    Estimate = {
        $rate = Get-Key $Pricing.apiManagement.perUnitHour $sku
        if ($null -eq $rate) { return @{ Cost = $null; Note = "no list price for $sku" } }
        return @{ Cost = $rate * $f.units * $f.regions * $Pricing.hoursPerMonth; Note = "$sku x$($f.units) unit(s)$(($f.regions -gt 1) ? " x$($f.regions) regions" : '') list price" }
    }
    Action = {
        return @(
            "Confirm with $who that nothing calls it (and that the APIs aren't only defined here), back up the configuration if needed, then delete it. A dev/test copy can move to the Consumption tier, which bills per call.",
            "az apim delete --name $($f.name) --resource-group $($f.resourceGroup)")
    }
}
