# waste-hunter 01 · Unattached managed disks
# Waste-type record(s) for queries/01-unattached-disks.kql: label, flags and the logic for each step. Loaded by
# Import-WasteTypes (lib/Common.ps1). The script blocks run inside Confirm-Candidate, Get-LivePrice,
# Get-Estimate and Get-Action (lib/WasteTypes.ps1) and use the variables those set up there.

@{
    Name = 'unattached-disk'
    Label = 'Unattached managed disks'
    Order = 1
    CommitmentEligible = $true   # a reservation or savings plan can cover it
    LivePrice = {
        $prod = @{ Premium = 'Premium SSD Managed Disks'; StandardSSD = 'Standard SSD Managed Disks'; Standard = 'Standard HDD Managed Disks' }[($sku -split '_')[0]]
        $tier = Get-DiskTier $f
        if (-not $prod -or -not $tier) { return $null }
        $m = "$($tier.Name) $red"
        $it = @(Get-RetailItems "serviceName eq 'Storage' and armRegionName eq '$rg' and productName eq '$prod' and skuName eq '$m'") |
            Where-Object { $_.meterName -eq "$m Disk" -and $_.unitOfMeasure -eq '1/Month' } | Select-Object -First 1
        if ($it) { return @{ Cost = [double] $it.retailPrice; Note = "$m list price, $region" } }
    }
    Estimate = {
        $tier = Get-DiskTier $f
        if ($tier) {
            $mult = ($sku -like '*_ZRS') ? $Pricing.disks.zrsMultiplier : 1
            return @{ Cost = $tier.Price * $mult; Note = "list price $($tier.Name)" }
        }
        $perGb = $Pricing.disks.perGbFallback[$sku] ?? $Pricing.disks.perGbFallback.default
        return @{ Cost = $perGb * [int] $f.sizeGb; Note = 'list price per GiB, capacity only' }
    }
    Action = {
        return @(
            "Confirm with $who that the data isn't needed. If unsure, take an incremental snapshot (cheaper per GiB), then delete the disk.",
            "az disk delete --ids $id")
    }
}
