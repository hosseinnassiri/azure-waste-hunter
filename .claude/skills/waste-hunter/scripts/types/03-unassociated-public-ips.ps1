# waste-hunter 03 · Unassociated public IP addresses
# Waste-type record(s) for queries/03-unassociated-public-ips.kql: label, flags and the logic for each step. Loaded by
# Import-WasteTypes (lib/Common.ps1). The script blocks run inside Confirm-Candidate, Get-LivePrice,
# Get-Estimate and Get-Action (lib/WasteTypes.ps1) and use the variables those set up there.

@{
    Name = 'unassociated-public-ip'
    Label = 'Unassociated public IPs'
    Order = 3
    QuickWin = $true   # reversible, or nothing depends on it: listed under Quick wins when high confidence
    LivePrice = {
        if ($sku -ne 'Standard' -and $f.confidence -eq 'low') { return $null }   # no charge; Get-Estimate says so
        $ipSku = ($f.tier -eq 'Global') ? 'Global' : $sku
        $it = @(Get-RetailItems "serviceName eq 'Virtual Network' and armRegionName eq '$rg' and productName eq 'IP Addresses' and skuName eq '$(Get-ODataLiteral $ipSku)'") |
            Where-Object { $_.meterName -eq "$ipSku IPv4 Static Public IP" -and $_.unitOfMeasure -eq '1 Hour' } | Select-Object -First 1
        if ($it) { return @{ Cost = [double] $it.retailPrice * $hours; Note = "$ipSku static IP list price, $region" } }
    }
    Estimate = {
        if ($sku -eq 'Standard') { return @{ Cost = $Pricing.publicIps.Standard; Note = 'list price' } }
        if ($f.confidence -eq 'low') { return @{ Cost = 0.0; Note = 'no charge' } }
        return @{ Cost = $Pricing.publicIps['Basic|Static']; Note = 'list price' }
    }
    Action = {
        if ($f.confidence -eq 'low') { return @('No charge. Delete to reduce clutter.', "az network public-ip delete --ids $id") }
        return @("Check DNS records and firewall or partner allowlists that reference this IP (a released static IP can't be recovered), then delete it.",
                 "az network public-ip delete --ids $id")
    }
}
