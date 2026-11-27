# waste-hunter 31 · Public IP prefixes with no addresses in use
# Waste-type record(s) for queries/31-unused-public-ip-prefixes.kql: label, flags and the logic for each step. Loaded by
# Import-WasteTypes (lib/WasteTypes.ps1). The script blocks run inside Confirm-Candidate, Get-LivePrice,
# Get-Estimate and Get-Action (lib/WasteTypes.ps1) and use the variables those set up there.

@{
    Name = 'unused-public-ip-prefix'
    Label = 'Unused public IP prefixes'
    Order = 31
    LivePrice = {
        $meter = ($sku -eq 'Global') ? 'Global Static Public IP' : 'Standard Static IP Addresses'
        $skuName = ($sku -eq 'Global') ? 'Global' : 'Standard'
        $p = Get-MeterPrice "serviceName eq 'Virtual Network' and armRegionName eq '$rg' and productName eq 'Public IP Prefix' and skuName eq '$skuName'" { $_.meterName -eq $meter -and $_.unitOfMeasure -eq '1 Hour' }
        if ($null -ne $p) { return @{ Cost = $p * [int] $f.sizeGb * $hours; Note = "$($f.sizeGb) address(es) x prefix list price, $region" } }
    }
    Estimate = {
        $rate = ($sku -eq 'Global') ? $Pricing.network.ipPrefixPerIpHour.Global : $Pricing.network.ipPrefixPerIpHour.Standard
        return @{ Cost = $rate * [int] $f.sizeGb * $Pricing.hoursPerMonth; Note = "$($f.sizeGb) address(es) x prefix list price" }
    }
    Action = {
        return @(
            "Ask $who whether these addresses are on a partner or firewall allowlist. Deleting the prefix releases them for good and you won't get the same range back. If nobody needs them, delete it.",
            "az network public-ip prefix delete --ids $id")
    }
}
