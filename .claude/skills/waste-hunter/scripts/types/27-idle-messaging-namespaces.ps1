# waste-hunter 27 · Idle Service Bus and Event Hubs namespaces (CANDIDATES, confirmed by metrics)
# Waste-type record(s) for queries/27-idle-messaging-namespaces.kql: label, flags and the logic for each step. Loaded by
# Import-WasteTypes (lib/WasteTypes.ps1). The script blocks run inside Confirm-Candidate, Get-LivePrice,
# Get-Estimate and Get-Action (lib/WasteTypes.ps1) and use the variables those set up there.

@{
    Name = 'idle-messaging-namespace'
    Label = 'Idle Service Bus and Event Hubs namespaces'
    Order = 27
    Candidate = $true
    Check = {
        if ($young) { return @() }
        $m = Get-MetricStats $r.id @('IncomingMessages', 'OutgoingMessages') 'Total'
        $in = Get-StatSum $m 'IncomingMessages'; $out = Get-StatSum $m 'OutgoingMessages'
        if ($in -gt 0 -or $out -gt 0) { return @() }
        $unit = ($ci.service -eq 'Service Bus') ? (($r.sku -eq 'Standard') ? 'base unit' : 'messaging unit(s)') : (($r.sku -eq 'Premium') ? 'processing unit(s)' : 'throughput unit(s)')
        $bills = ($ci.service -eq 'Service Bus' -and $r.sku -eq 'Standard') ? 'the base unit bills every hour' : 'each unit bills every hour'
        $why = "0 incoming and 0 outgoing messages in 30 days ($($ci.service) $($r.sku), $($ci.units) $unit), but $bills"
        return @(New-FindingFrom $r @{ confidence = 'high'; reason = $why; idleDays = 30; idleSource = 'IncomingMessages and OutgoingMessages metrics, 30 days'
                                       units = [int] ($ci.units ?? 1); service = [string] $ci.service })
    }
    LivePrice = {
        if ($f.service -eq 'Service Bus') {
            # Standard: the hourly base-unit meter (there's also a 1/Month one; operations are billed on top)
            $meter = ($sku -eq 'Standard') ? 'Standard Base Unit' : 'Premium Messaging Unit'
            $p = Get-MeterPrice "serviceName eq 'Service Bus' and armRegionName eq '$rg' and skuName eq '$(Get-ODataLiteral $sku)'" { $_.meterName -eq $meter -and $_.unitOfMeasure -eq '1/Hour' }
        }
        else {
            $meter = ($sku -eq 'Premium') ? 'Premium Processing Unit' : "$sku Throughput Unit"
            $p = Get-MeterPrice "serviceName eq 'Event Hubs' and armRegionName eq '$rg' and skuName eq '$(Get-ODataLiteral $sku)'" { $_.meterName -eq $meter -and $_.unitOfMeasure -eq '1 Hour' }
        }
        if ($null -ne $p) { return @{ Cost = $p * $f.units * $hours; Note = "$($f.service) $sku x$($f.units) unit(s) list price, $region; operations extra" } }
    }
    Estimate = {
        $p = $Pricing.messaging
        $rate = ($f.service -eq 'Service Bus') ? (($sku -eq 'Standard') ? $p.serviceBusStandardBasePerHour : $p.serviceBusPremiumPerMuHour) : (Get-Key $p.eventHubsPerUnitHour $sku)
        if ($null -eq $rate) { return @{ Cost = $null; Note = "no list price for $($f.service) $sku" } }
        return @{ Cost = $rate * $f.units * $Pricing.hoursPerMonth; Note = "$($f.service) $sku x$($f.units) unit(s) list price; operations extra" }
    }
    Action = {
        $cmd = ($f.service -eq 'Service Bus') ? "az servicebus namespace delete --ids $id" : "az eventhubs namespace delete --ids $id"
        $keep = ($f.service -eq 'Service Bus' -and $f.sku -eq 'Standard') ? '' : " If it must stay, scale it down to the fewest units$(($f.service -eq 'Event Hubs' -and $f.sku -ne 'Basic') ? ' or a lower tier' : '')."
        return @(
            "Confirm with $who that no producer or consumer still points at it (a disabled app or a DR pairing), then delete it.$keep",
            $cmd)
    }
}
