# waste-hunter 20 · DDoS Network Protection plans that protect nothing
# Waste-type record(s) for queries/20-idle-ddos-protection-plans.kql: label, flags and the logic for each step. Loaded by
# Import-WasteTypes (lib/Common.ps1). The script blocks run inside Confirm-Candidate, Get-LivePrice,
# Get-Estimate and Get-Action (lib/WasteTypes.ps1) and use the variables those set up there.

@{
    Name = 'idle-ddos-protection-plan'
    Label = 'DDoS protection plans protecting nothing'
    Order = 20
    QuickWin = $true   # reversible, or nothing depends on it: listed under Quick wins when high confidence
    LivePrice = {
        $p = Get-MeterPrice "serviceName eq 'Azure DDOS Protection' and armRegionName eq '$rg' and skuName eq 'Network Protection'" { $_.meterName -eq 'Network Protection Plan' -and $_.unitOfMeasure -eq '1 Hour' }
        if ($null -ne $p) { return @{ Cost = $p * $hours; Note = "Network Protection plan list price, $region" } }
    }
    Estimate = { return @{ Cost = $Pricing.network.ddosPlanPerHour * $Pricing.hoursPerMonth; Note = 'Network Protection plan list price' } }
    Action = {
        return @(
            "Confirm with $who that no virtual network is about to be linked, then delete the plan. Free DDoS infrastructure protection stays on. If only a few public IPs need DDoS protection, IP Protection per IP is usually cheaper.",
            "az network ddos-protection delete --ids $id")
    }
}
