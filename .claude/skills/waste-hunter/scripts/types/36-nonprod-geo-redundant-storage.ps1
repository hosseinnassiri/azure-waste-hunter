# waste-hunter 36 · Geo-redundant storage in non-production (CANDIDATES, confirmed by metrics)
# Waste-type record(s) for queries/36-nonprod-geo-redundant-storage.kql: label, flags and the logic for each step. Loaded by
# Import-WasteTypes (lib/WasteTypes.ps1). The script blocks run inside Confirm-Candidate, Get-LivePrice,
# Get-Estimate and Get-Action (lib/WasteTypes.ps1) and use the variables those set up there.

@{
    Name = 'nonprod-geo-redundant-storage'
    Label = 'Geo-redundant storage in non-production'
    Order = 36
    Candidate = $true
    PartialSaving = $true   # the saving is the redundancy price difference
    Check = {
        # Capacity metrics only take hourly grains; the last value is the current size
        $bytes = Get-StatLast (Get-MetricStats $r.id @('UsedCapacity') 'Average' 'PT1H') 'UsedCapacity'
        $gib = $bytes / 1GB
        if ($gib -lt 10) { return @() }
        $red = Get-StorageRedundancyName $r.sku
        $to = ($red -like '*GZRS') ? 'ZRS' : 'LRS'
        $why = ('Tagged env={0} but stores {1:N0} GiB as {2}, which keeps a second copy in another region. {3} keeps the data in one region ({4}) at a lower price per GB' -f
                $r.env, $gib, $red, $to, (($to -eq 'ZRS') ? 'across zones' : 'three copies'))
        return @(New-FindingFrom $r @{ confidence = 'medium'; reason = $why; sizeGb = [int] [math]::Round($gib); usedGiB = $gib; fromRed = $red; toRed = $to })
    }
    # Blob prices per GB depend on tier, redundancy and region; pricing.json gives the difference
    Estimate = {
        $s = $Pricing.storagePerGb
        $perGb = Get-Key $s ([string] $f.tier); if ($null -eq $perGb) { $perGb = $s.Hot }
        $m = $s.redundancyMultiplier
        $diff = (Get-Key $m $f.fromRed) - (Get-Key $m $f.toRed)
        return @{ Cost = $f.usedGiB * $perGb * $diff; Note = ('{0:N0} GiB {1} minus {2} ({3} tier) list price; geo-replication traffic not included' -f $f.usedGiB, $f.fromRed, $f.toRed, ($f.tier ? $f.tier : 'Hot')) }
    }
    Action = {
        return @(
            "Confirm with $who that this data doesn't need a copy in a second region (a dev or test copy rarely does), then change the redundancy. GRS to LRS and GZRS to ZRS take effect at once; the secondary copy is removed.",
            "az storage account update --ids $id --sku Standard_$($f.toRed)")
    }
}
