# waste-hunter 15 · Idle NAT, VPN and ExpressRoute gateways, and unprovisioned ExpressRoute circuits
# Waste-type record(s) for queries/15-idle-network-gateways.kql: label, flags and the logic for each step. Loaded by
# Import-WasteTypes (lib/Common.ps1). The script blocks run inside Confirm-Candidate, Get-LivePrice,
# Get-Estimate and Get-Action (lib/WasteTypes.ps1) and use the variables those set up there.

@{
    Name = 'idle-network-gateway'
    Label = 'Idle NAT, VPN and ExpressRoute gateways and circuits'
    Order = 15
    LivePrice = {
        switch ([string] $f.tier) {
            'nat' {
                $p = Get-MeterPrice "serviceName eq 'NAT Gateway' and armRegionName eq '$(Get-PriceZone $region)' and skuName eq 'Standard'" { $_.meterName -eq 'Standard Gateway' }
                if ($null -ne $p) { return @{ Cost = $p * $hours; Note = 'NAT gateway list price' } }
            }
            'vpn-gateway' {
                $p = Get-MeterPrice "serviceName eq 'VPN Gateway' and armRegionName eq '$rg' and skuName eq '$(Get-ODataLiteral $sku)'" { $_.meterName -eq $sku -and $_.unitOfMeasure -eq '1 Hour' }
                if ($null -ne $p) { return @{ Cost = $p * $hours; Note = "$sku list price, $region" } }
            }
            'er-gateway' {
                $meter = @{ Standard = 'Standard Gateway'; HighPerformance = 'High Performance Gateway'; UltraPerformance = 'Ultra High Performance Gateway' }[$sku] ?? "$sku Gateway"
                $p = Get-MeterPrice "serviceName eq 'ExpressRoute' and armRegionName eq '$rg' and meterName eq '$(Get-ODataLiteral $meter)'" { $_.unitOfMeasure -eq '1 Hour' }
                if ($null -ne $p) { return @{ Cost = $p * $hours; Note = "$meter list price, $region" } }
            }
        }
    }
    Estimate = {
        $p = $Pricing.network
        $rate = switch ([string] $f.tier) {
            'nat' { $p.natGatewayPerHour }
            'vpn-gateway' { $p.vpnGatewayPerHour[$sku] }
            'er-gateway' { $p.erGatewayPerHour[$sku] }
            default { $null }
        }
        if ($null -eq $rate) { return @{ Cost = $null; Note = ($f.tier -eq 'er-circuit') ? 'circuit price depends on bandwidth, peering location and plan' : "no list price for $sku" } }
        return @{ Cost = $rate * $Pricing.hoursPerMonth; Note = "$sku list price" }
    }
    Action = {
        switch ([string] $f.tier) {
            'nat' { return @('Delete it, or attach it to the subnets that need outbound access. Release its public IPs if they aren''t needed.', "az network nat gateway delete --ids $id") }
            'er-circuit' { return @('If the circuit will never be provisioned, ask the provider to deprovision it and then delete it. Billing runs from creation, not from provisioning.', "az network express-route delete --ids $id") }
            default { return @("Confirm with $who that it isn't a DR standby or waiting for a connection (re-creating a gateway takes 30-45 minutes), then delete it.", "az network vnet-gateway delete --ids $id") }
        }
    }
}
