# waste-hunter 16 · Idle Azure Bastion hosts (CANDIDATES, confirmed by metrics)
# Waste-type record(s) for queries/16-idle-bastion-hosts.kql: label, flags and the logic for each step. Loaded by
# Import-WasteTypes (lib/Common.ps1). The script blocks run inside Confirm-Candidate, Get-LivePrice,
# Get-Estimate and Get-Action (lib/WasteTypes.ps1) and use the variables those set up there.

@{
    Name = 'idle-bastion'
    Label = 'Idle Bastion hosts'
    Order = 16
    QuickWin = $true   # reversible, or nothing depends on it: listed under Quick wins when high confidence
    Candidate = $true
    Check = {
        # `sessions` only supports 5- and 15-minute grains
        $sessions = Get-StatSum (Get-MetricStats $r.id @('sessions') 'Total' 'PT15M') 'sessions'
        if ($sessions -gt 0) { return @() }
        $why = "0 Bastion sessions in 30 days ($($r.sku), $($ci.scaleUnits) scale unit(s)), billed hourly regardless"
        return @(New-FindingFrom $r @{ confidence = 'high'; reason = $why; idleDays = 30; idleSource = 'sessions metric, 30 days'; scaleUnits = [int] ($ci.scaleUnits ?? 2) })
    }
    LivePrice = {
        $bf = "serviceName eq 'Azure Bastion' and armRegionName eq '$rg' and skuName eq '$(Get-ODataLiteral $sku)'"
        $base = Get-MeterPrice $bf { $_.meterName -eq "$sku Gateway" -and $_.unitOfMeasure -eq '1 Hour' }
        $extra = ($sku -ne 'Basic') ? (Get-MeterPrice $bf { $_.meterName -eq "$sku Additional Gateway" -and $_.unitOfMeasure -eq '1 Hour' }) : 0
        if ($null -ne $base) { return @{ Cost = ($base + [math]::Max(0, [int] $f.scaleUnits - 2) * ($extra ?? 0)) * $hours; Note = "$sku Bastion list price, $($f.scaleUnits) scale unit(s), $region" } }
    }
    Estimate = {
        $p = $Pricing.network.bastionPerHour
        $base = $p[$sku]
        if ($null -eq $base) { return @{ Cost = $null; Note = "no list price for $sku" } }
        $extra = $p["${sku}Additional"] ?? 0
        return @{ Cost = ($base + [math]::Max(0, [int] $f.scaleUnits - 2) * $extra) * $Pricing.hoursPerMonth; Note = "$sku Bastion list price" }
    }
    Action = {
        return @(
            'Delete it and re-create it when needed (it takes about 10 minutes), or move dev/test use to the free Developer SKU.',
            "az network bastion delete --ids $id")
    }
}
