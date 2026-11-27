# waste-hunter 06 · Disk snapshots older than 90 days
# Waste-type record(s) for queries/06-old-snapshots.kql: label, flags and the logic for each step. Loaded by
# Import-WasteTypes (lib/Common.ps1). The script blocks run inside Confirm-Candidate, Get-LivePrice,
# Get-Estimate and Get-Action (lib/WasteTypes.ps1) and use the variables those set up there.

@{
    Name = 'old-snapshot'
    Label = 'Disk snapshots older than 90 days'
    Order = 6
    LivePrice = {
        $prod = ($sku -like 'Premium*') ? 'Premium SSD Managed Disks' : 'Standard HDD Managed Disks'
        $it = @(Get-RetailItems "serviceName eq 'Storage' and armRegionName eq '$rg' and productName eq '$prod' and skuName eq 'Snapshots $red'") |
            Where-Object { $_.meterName -eq "$red Snapshots" -and $_.unitOfMeasure -eq '1 GB/Month' } | Select-Object -First 1
        if ($it) { return @{ Cost = [double] $it.retailPrice * [int] $f.sizeGb; Note = "$red snapshot list price, $region; upper bound, provisioned GiB" } }
    }
    Estimate = {
        $perGb = $Pricing.snapshotsPerGb[$sku] ?? $Pricing.snapshotsPerGb.default
        return @{ Cost = $perGb * [int] $f.sizeGb; Note = 'upper bound, provisioned GiB (billed on used GiB)' }
    }
    Action = {
        $pre = ($f.confidence -eq 'low') ? 'The source disk is gone or this is Azure Backup data. Confirm the data is not needed. ' : ''
        return @("${pre}Check whether a retention policy requires it. If not, delete it. If it must be kept, make sure it's incremental on Standard storage.",
                 "az snapshot delete --ids $id")
    }
}
