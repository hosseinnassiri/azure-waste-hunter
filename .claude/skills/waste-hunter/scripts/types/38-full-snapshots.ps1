# waste-hunter 38 · Full disk snapshots that could be incremental
# Waste-type record(s) for queries/38-full-snapshots.kql: label, flags and the logic for each step. Loaded by
# Import-WasteTypes (lib/WasteTypes.ps1). The script blocks run inside Confirm-Candidate, Get-LivePrice,
# Get-Estimate and Get-Action (lib/WasteTypes.ps1) and use the variables those set up there.
# Saving, per snapshot (upper bounds: snapshots bill on used GiB, Resource Graph shows provisioned):
#   premium  Premium snapshot rate minus Standard rate (incremental is always Standard)
#   series   the whole Standard price (as an increment it would hold only changed data)

@{
    Name = 'full-snapshot'
    Label = 'Full snapshots that could be incremental'
    Order = 38
    PartialSaving = $true   # the snapshot is kept, as incremental: a price difference, not its whole bill
    LivePrice = {
        $snap = { param($prod) Get-MeterPrice "serviceName eq 'Storage' and armRegionName eq '$rg' and productName eq '$prod' and skuName eq 'Snapshots $red'" { $_.meterName -eq "$red Snapshots" -and $_.unitOfMeasure -eq '1 GB/Month' } }
        $std = & $snap 'Standard HDD Managed Disks'
        if ($null -eq $std) { return $null }
        if ($f.tier -eq 'premium') {
            $prem = & $snap 'Premium SSD Managed Disks'
            if ($null -ne $prem) { return @{ Cost = ($prem - $std) * [int] $f.sizeGb; Note = "Premium minus Standard $red snapshot list price, $region; upper bound, provisioned GiB" } }
            return $null
        }
        return @{ Cost = $std * [int] $f.sizeGb; Note = "Standard $red snapshot list price, $region; upper bound, an increment holds only changed data" }
    }
    Estimate = {
        $p = $Pricing.snapshotsPerGb
        $std = ($sku -like '*_ZRS') ? $p.Standard_ZRS : $p.Standard_LRS
        if ($f.tier -eq 'premium') { return @{ Cost = ($p.Premium_LRS - $p.Standard_LRS) * [int] $f.sizeGb; Note = 'Premium minus Standard snapshot list price; upper bound, provisioned GiB' } }
        return @{ Cost = $std * [int] $f.sizeGb; Note = 'Standard snapshot list price; upper bound, an increment holds only changed data' }
    }
    Action = {
        return @(
            "Take future snapshots of this disk as incremental (in a script or pipeline: --incremental true). Once an incremental snapshot covers the same point in time, check with $who whether this full one is still needed and delete it.",
            "az snapshot create --resource-group $($f.resourceGroup) --name <name>-incr --source $($f.extra) --incremental true")
    }
}
