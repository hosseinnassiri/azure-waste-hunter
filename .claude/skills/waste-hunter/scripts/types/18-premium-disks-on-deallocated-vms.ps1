# waste-hunter 18 · Premium disks on VMs deallocated for weeks (CANDIDATES, confirmed by metrics)
# Waste-type record(s) for queries/18-premium-disks-on-deallocated-vms.kql: label, flags and the logic for each step. Loaded by
# Import-WasteTypes (lib/Common.ps1). The script blocks run inside Confirm-Candidate, Get-LivePrice,
# Get-Estimate and Get-Action (lib/WasteTypes.ps1) and use the variables those set up there.

@{
    Name = 'premium-disk-deallocated-vm'
    Label = 'Premium disks on long-deallocated VMs'
    Order = 18
    Candidate = $true
    PartialSaving = $true   # the saving is a price difference, never the whole bill
    CommitmentEligible = $true   # a reservation or savings plan can cover it
    Check = {
        $vmId = [string] $ci.vmId
        if (-not $vmId) { return @() }
        $act = Get-LastCpuActivity $vmId
        $off = $act.Last ? [int] [math]::Floor(($Now - $act.Last).TotalDays) : $act.Window
        if ($off -lt 30) { return @() }
        $offTxt = $act.Last ? "$off days (last CPU activity $($act.Last.ToString('yyyy-MM-dd')))" : "$($act.Window)+ days (no CPU data)"
        $vmName = ($vmId -split '/')[-1]
        $why = "Premium SSD attached to VM $vmName, which has been deallocated for $offTxt. The disk still bills at its full Premium tier"
        return @(New-FindingFrom $r @{ confidence = ($off -ge 60) ? 'high' : 'medium'; reason = $why
                                       idleDays = $off; idleSource = $act.Last ? 'VM last CPU datapoint' : "no VM CPU data in $($act.Window) days ($($act.Window)+)" })
    }
    LivePrice = {
        $tier = Get-DiskTier $f
        if (-not $tier) { return $null }
        $eName = $Pricing.disks['StandardSSD_LRS'].tiers[$tier.Index]
        $p = Get-MeterPrice "serviceName eq 'Storage' and armRegionName eq '$rg' and productName eq 'Premium SSD Managed Disks' and skuName eq '$($tier.Name) $red'" { $_.meterName -eq "$($tier.Name) $red Disk" -and $_.unitOfMeasure -eq '1/Month' }
        $e = Get-MeterPrice "serviceName eq 'Storage' and armRegionName eq '$rg' and productName eq 'Standard SSD Managed Disks' and skuName eq '$eName $red'" { $_.meterName -eq "$eName $red Disk" -and $_.unitOfMeasure -eq '1/Month' }
        if ($null -ne $p -and $null -ne $e) { return @{ Cost = $p - $e; Note = "$($tier.Name) minus $eName $red list price, $region" } }
    }
    Estimate = {
        $tier = Get-DiskTier $f
        if (-not $tier) { return @{ Cost = $null; Note = "no tier price for $sku" } }
        $e = $Pricing.disks['StandardSSD_LRS']
        $mult = ($sku -like '*_ZRS') ? $Pricing.disks.zrsMultiplier : 1
        return @{ Cost = ($tier.Price - $e.prices[$tier.Index]) * $mult; Note = "$($tier.Name) minus $($e.tiers[$tier.Index]) list price" }
    }
    Action = {
        return @(
            'While the VM stays deallocated, switch the disk to Standard SSD and switch it back before starting the VM. If the VM is retired, snapshot what you need and delete the VM and its disks.',
            "az disk update --ids $id --sku StandardSSD_LRS")
    }
}
