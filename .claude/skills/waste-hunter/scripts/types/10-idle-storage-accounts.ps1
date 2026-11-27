# waste-hunter 10 · Storage accounts: idle, or Hot-tier blobs nobody reads (CANDIDATES)
# Waste-type record(s) for queries/10-idle-storage-accounts.kql: label, flags and the logic for each step. Loaded by
# Import-WasteTypes (lib/Common.ps1). The script blocks run inside Confirm-Candidate, Get-LivePrice,
# Get-Estimate and Get-Action (lib/WasteTypes.ps1) and use the variables those set up there.

# Logic shared by the records below (idle-storage-account and hot-blob-unread)
$SharedBodies = @{
    LivePrice = {
        if ($sku -like 'Premium*') { return $null }
        $redName = Get-StorageRedundancyName $sku
        $items = @(Get-RetailItems "serviceName eq 'Storage' and armRegionName eq '$rg' and productName eq 'General Block Blob v2' and (meterName eq 'Hot $redName Data Stored' or meterName eq 'Cool $redName Data Stored' or meterName eq 'Cold $redName Data Stored')")
        $price = @{}
        foreach ($t in 'Hot', 'Cool', 'Cold') {
            $it = $items | Where-Object { $_.meterName -eq "$t $redName Data Stored" -and $_.unitOfMeasure -eq '1 GB/Month' } | Sort-Object { [double] $_.tierMinimumUnits } | Select-Object -First 1
            if ($it) { $price[$t] = [double] $it.retailPrice }
        }
        if ($f.wasteType -eq 'hot-blob-unread') {
            if ($price['Hot'] -and $price['Cool']) { return @{ Cost = $f.usedGiB * ($price['Hot'] - $price['Cool']); Note = "Hot minus Cool $redName list price, $region" } }
        }
        else {
            $t = $f.tier ? [string] $f.tier : 'Hot'
            if ($price[$t]) { return @{ Cost = $f.usedGiB * $price[$t]; Note = "all capacity at blob $t $redName list price, $region; approximate" } }
        }
    }
    Estimate = {
        if ($sku -like 'Premium*') { return @{ Cost = $null; Note = 'premium storage is priced by provisioned size' } }
        $p = $Pricing.storagePerGb
        $mult = $p.redundancyMultiplier[(Get-StorageRedundancyName $sku)] ?? 1
        if ($f.wasteType -eq 'hot-blob-unread') { return @{ Cost = $f.usedGiB * ($p.Hot - $p.Cool) * $mult; Note = 'Hot minus Cool list price' } }
        $t = $f.tier ? [string] $f.tier : 'Hot'
        return @{ Cost = $f.usedGiB * ($p[$t] ?? $p.Hot) * $mult; Note = "all capacity at blob $t list price; approximate" }
    }
}

@{
    Name = 'idle-storage-account'
    Label = 'Idle storage accounts'
    Order = 10
    Candidate = $true
    Check = {
        if ($young) { return @() }
        $tx = Get-StatSum (Get-MetricStats $r.id @('Transactions') 'Total') 'Transactions'
        $usedBytes = Get-StatLast (Get-MetricStats $r.id @('UsedCapacity') 'Average' 'PT1H' 2) 'UsedCapacity'
        $mounts = @($ci.fileMountApps | Where-Object { $_ })
        $sameRg = @($mounts | Where-Object { $_.rg -eq ([string] $r.resourceGroup).ToLower() } | ForEach-Object { $_.name })
        $tierName = [string] $ci.accessTier
        if ($tx -eq 0) {
            $conf = ($tierName -in 'Cool', 'Cold', 'Archive') ? 'medium' : 'high'
            $why = "0 transactions on any service (blob, file, queue, table) in 30 days; $(Format-Bytes $usedBytes) stored"
            if ($conf -eq 'medium') { $why += "; $tierName tier, so this may be intentional cold storage" }
            if ($sameRg) { $conf = 'low'; $why += "; Container App(s) in the same resource group mount an Azure Files volume ($($sameRg -join ', ')). This account may be their data store, idle only because the app is scaled to zero." }
            elseif ($mounts) { $conf = ($conf -eq 'high') ? 'medium' : 'low'; $why += "; Container Apps in this subscription mount Azure Files volumes ($(@($mounts | ForEach-Object { $_.name }) -join ', ')). Check that none use this account." }
            return @(New-FindingFrom $r @{ confidence = $conf; reason = $why; idleDays = 30; idleSource = 'Transactions metric, 30 days'
                                           sizeGb = [math]::Round($usedBytes / 1GB, 2); usedGiB = $usedBytes / 1GB; mounted = [bool] $sameRg })
        }
        if ($tierName -eq 'Hot' -and $ci.kind -ne 'FileStorage') {
            $blobId = "$($r.id)/blobServices/default"
            $blobGiB = (Get-StatLast (Get-MetricStats $blobId @('BlobCapacity') 'Average' 'PT1H' 2) 'BlobCapacity') / 1GB
            if ($blobGiB -lt 100) { return @() }
            $reads = Get-StatSum (Get-MetricStats $blobId @('Transactions') 'Total' -Filter "ApiName eq 'GetBlob'") 'Transactions'
            if ($reads -gt 0) { return @() }
            $why = "$('{0:N0}' -f $blobGiB) GiB of blob data on the Hot tier with 0 GetBlob reads in 30 days. Cool stores it for less (reads cost more, and there's a 30-day minimum)"
            return @(New-FindingFrom $r @{ wasteType = 'hot-blob-unread'; confidence = 'medium'; reason = $why; idleDays = 30; idleSource = 'GetBlob transactions, 30 days'
                                           sizeGb = [math]::Round($blobGiB, 1); usedGiB = $blobGiB })
        }
        return @()
    }
    LivePrice = $SharedBodies.LivePrice
    Estimate = $SharedBodies.Estimate
    Action = {
        if ($f.mounted) { return @(
            "Do NOT delete before confirming what uses it. A Container App in the same resource group mounts an Azure Files volume and this may be its data. If it is, it's not waste. Tag it waste-hunter:ignore=true to stop it being reported.",
            '') }
        return @("Confirm with $who that nothing reads or writes it (apps, Functions, backups, scripts) and that its data isn't needed. Then delete it, or move the data to Cool or Archive if it must be kept.",
                 "az storage account delete --ids $id")
    }
}

@{
    Name = 'hot-blob-unread'
    Label = 'Hot-tier blob data nobody reads'
    Order = 10.5
    Parent = 'idle-storage-account'   # emitted by the parent's check
    PartialSaving = $true   # the saving is a price difference, never the whole bill
    LivePrice = $SharedBodies.LivePrice
    Estimate = $SharedBodies.Estimate
    Action = {
        return @(
            "Move it to the Cool tier: change the account's default tier, or add a lifecycle rule that tiers blobs not accessed for 30 days. Cool has a 30-day minimum and higher read cost, so skip this if reads are about to start.",
            "az storage account update --ids $id --access-tier Cool")
    }
}
