# waste-hunter 40 · Zone-redundant SQL databases and elastic pools in non-production
# Waste-type record(s) for queries/40-nonprod-zone-redundant-sql.kql: label, flags and the logic for each step. Loaded by
# Import-WasteTypes (lib/WasteTypes.ps1). The script blocks run inside Confirm-Candidate, Get-LivePrice,
# Get-Estimate and Get-Action (lib/WasteTypes.ps1) and use the variables those set up there.

@{
    Name = 'nonprod-zone-redundant-sql'
    Label = 'Zone-redundant SQL in non-production'
    Order = 40
    PartialSaving = $true        # the saving is the zone-redundancy add-on, never the database's whole bill
    CommitmentEligible = $true   # a "vCore ZR" reservation can cover the add-on
    LivePrice = {
        # Provisioned Gen5 only: the add-on is one meter per vCore-hour. Serverless bills it for the vCores
        # used, which inventory can't tell; other hardware falls back to the Gen5 rate in pricing.json.
        if ($f.tier -eq 'serverless' -or $sku -notmatch '_Gen5') { return $null }
        $p = Get-MeterPrice "serviceName eq 'SQL Database' and armRegionName eq '$rg' and productName eq 'SQL Database Single/Elastic Pool General Purpose - Compute Gen5' and skuName eq '1 vCore Zone Redundancy'" { $_.meterName -eq 'Zone Redundancy vCore' -and $_.unitOfMeasure -eq '1 Hour' }
        if ($null -ne $p) { return @{ Cost = $p * [int] $f.sizeGb * $hours; Note = "$($f.sizeGb) vCore(s) x zone-redundancy add-on list price, $region; storage premium not included" } }
    }
    Estimate = {
        if ($f.tier -eq 'serverless') { return @{ Cost = $null; Note = 'serverless: the add-on bills only for the vCores used' } }
        $rate = $Pricing.sqlDatabase.zoneRedundancyPerVcoreHour
        $hw = ($sku -match '_Gen5') ? '' : ' (Gen5 rate; other hardware may differ)'
        return @{ Cost = $rate * [int] $f.sizeGb * $Pricing.hoursPerMonth; Note = "$($f.sizeGb) vCore(s) x zone-redundancy add-on list price$hw; storage premium not included" }
    }
    Action = {
        $cmd = ($f.extra -eq 'elastic pool') ? "az sql elastic-pool update --ids $id --zone-redundant false" : "az sql db update --ids $id --zone-redundant false"
        return @(
            "Confirm with $who that this non-production $($f.extra) doesn't need to survive a zone outage, then turn zone redundancy off. It's an online change with a brief disconnect, and the data isn't touched.",
            $cmd)
    }
}
