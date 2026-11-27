# waste-hunter 32 · Front Door and Traffic Manager profiles with no endpoints
# Waste-type record(s) for queries/32-empty-edge-profiles.kql: label, flags and the logic for each step. Loaded by
# Import-WasteTypes (lib/WasteTypes.ps1). The script blocks run inside Confirm-Candidate, Get-LivePrice,
# Get-Estimate and Get-Action (lib/WasteTypes.ps1) and use the variables those set up there.

@{
    Name = 'empty-edge-profile'
    Label = 'Front Door and Traffic Manager profiles with no endpoints'
    Order = 32
    QuickWin = $true   # no endpoint, so nothing is served through it
    # Front Door base fees are priced per billing zone, not per region, so pricing.json is used
    Estimate = {
        if ($f.tier -eq 'traffic-manager') { return @{ Cost = 0; Note = 'no endpoints, DNS queries only' } }
        $fee = Get-Key $Pricing.network.frontDoorBasePerMonth $sku
        if ($null -eq $fee) { return @{ Cost = $null; Note = "no list price for $sku" } }
        return @{ Cost = $fee; Note = "$sku monthly base fee" }
    }
    Action = {
        if ($f.tier -eq 'traffic-manager') { return @('Delete it if no DNS name points at it (check CNAME records first).', "az network traffic-manager profile delete --ids $id") }
        return @("Confirm with $who that no endpoint is about to be added, then delete the profile. Custom domains and WAF policies attached to it go with it.", "az afd profile delete --ids $id")
    }
}
