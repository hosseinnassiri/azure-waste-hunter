# waste-hunter 23 · Idle Azure Firewalls (CANDIDATES, confirmed by metrics)
# Waste-type record(s) for queries/23-idle-firewalls.kql: label, flags and the logic for each step. Loaded by
# Import-WasteTypes (lib/Common.ps1). The script blocks run inside Confirm-Candidate, Get-LivePrice,
# Get-Estimate and Get-Action (lib/WasteTypes.ps1) and use the variables those set up there.

@{
    Name = 'idle-firewall'
    Label = 'Idle Azure Firewalls'
    Order = 23
    Candidate = $true
    Check = {
        # Hourly grain: these metrics are published per minute, and 30 days of hours is 720 points
        $m = Get-MetricStats $r.id @('DataProcessed', 'ApplicationRuleHit', 'NetworkRuleHit') 'Total' 'PT1H'
        $bytes = Get-StatSum $m 'DataProcessed'; $hits = (Get-StatSum $m 'ApplicationRuleHit') + (Get-StatSum $m 'NetworkRuleHit')
        if ($hits -gt 0 -or $bytes -ge 1GB) { return @() }
        $conf = ($bytes -lt 100MB) ? 'high' : 'medium'
        $where = [bool] $ci.hub ? ' in a virtual hub' : ''
        $why = "0 application or network rule hits and $(Format-Bytes $bytes) processed in 30 days ($($ci.tier)$where), but the deployment fee bills every hour"
        if ($conf -eq 'medium') { $why += '. Some traffic still flows (DNAT rules have no hit metric), so check what routes through it first' }
        return @(New-FindingFrom $r @{ confidence = $conf; reason = $why; idleDays = 30; idleSource = 'DataProcessed and rule hit metrics, 30 days'
                                       hub = [bool] $ci.hub })
    }
    LivePrice = {
        # Hub firewalls have their own meters ('Standard Secure Virtual Hub', 'Premium Secured Virtual Hub')
        $meterSku = $f.hub ? (@{ Basic = 'Basic Secured Virtual Hub'; Standard = 'Standard Secure Virtual Hub'; Premium = 'Premium Secured Virtual Hub' }[$sku]) : $sku
        if (-not $meterSku) { return $null }
        $p = Get-MeterPrice "serviceName eq 'Azure Firewall' and armRegionName eq '$rg' and skuName eq '$(Get-ODataLiteral $meterSku)'" { $_.meterName -eq "$meterSku Deployment" -and $_.unitOfMeasure -eq '1 Hour' }
        if ($null -ne $p) { return @{ Cost = $p * $hours; Note = "$meterSku deployment list price, $region; capacity units and data processed extra" } }
    }
    Estimate = {
        $rate = $Pricing.network.firewallPerHour[$sku]
        if ($null -eq $rate) { return @{ Cost = $null; Note = "no list price for $sku" } }
        return @{ Cost = $rate * $Pricing.hoursPerMonth; Note = "$sku deployment list price; capacity units and data processed extra" }
    }
    Action = {
        return @(
            ('Check route tables (forced tunneling, hub routing) and any planned spokes that send traffic through it. If it is not needed, delete it, or deallocate it to keep its configuration without the hourly fee (Azure PowerShell: $fw.Deallocate(); Set-AzFirewall $fw).'),
            "az network firewall delete --ids $id")
    }
}
