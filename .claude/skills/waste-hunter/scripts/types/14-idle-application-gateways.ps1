# waste-hunter 14 · Application Gateways with no backends
# Waste-type record(s) for queries/14-idle-application-gateways.kql: label, flags and the logic for each step. Loaded by
# Import-WasteTypes (lib/Common.ps1). The script blocks run inside Confirm-Candidate, Get-LivePrice,
# Get-Estimate and Get-Action (lib/WasteTypes.ps1) and use the variables those set up there.

@{
    Name = 'idle-application-gateway'
    Label = 'Application Gateways with no backends'
    Order = 14
    QuickWin = $true   # reversible, or nothing depends on it: listed under Quick wins when high confidence
    LivePrice = {
        $prod = @{ Standard_v2 = 'Application Gateway Standard v2'; WAF_v2 = 'Application Gateway WAF v2'; Basic = 'Application Gateway Basic v2' }[$sku]
        if (-not $prod) { return $null }   # v1 sizes: pricing.json
        $meterSku = ($sku -eq 'Basic') ? 'Basic' : 'Standard'
        $af = "serviceName eq 'Application Gateway' and armRegionName eq '$rg' and productName eq '$prod'"
        $fixed = Get-MeterPrice $af { $_.meterName -eq "$meterSku Fixed Cost" }
        $cu = Get-MeterPrice $af { $_.meterName -eq "$meterSku Capacity Units" }
        if ($null -ne $fixed) { return @{ Cost = ($fixed + [int] ($f.sizeGb ?? 0) * ($cu ?? 0)) * $hours; Note = "$sku fixed + $($f.sizeGb) minimum capacity unit(s) list price, $region" } }
    }
    Estimate = {
        $p = $Pricing.network.applicationGateway[$sku]
        if ($null -eq $p) { return @{ Cost = $null; Note = "no list price for $sku" } }
        $n = [math]::Max(1, [int] ($f.sizeGb ?? 0))
        $c = $p['fixedPerHour'] + $n * $p['perUnitHour']
        return @{ Cost = $c * $Pricing.hoursPerMonth; Note = "$sku list price, $n unit(s)" }
    }
    Action = {
        return @(
            'Stop it to end the hourly charge while keeping its configuration (start it again when backends return), or delete it if it has been retired.',
            "az network application-gateway stop --ids $id")
    }
}
