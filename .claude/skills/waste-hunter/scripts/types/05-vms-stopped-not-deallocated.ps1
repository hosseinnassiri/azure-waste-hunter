# waste-hunter 05 · VMs stopped but not deallocated
# Waste-type record(s) for queries/05-vms-stopped-not-deallocated.kql: label, flags and the logic for each step. Loaded by
# Import-WasteTypes (lib/Common.ps1). The script blocks run inside Confirm-Candidate, Get-LivePrice,
# Get-Estimate and Get-Action (lib/WasteTypes.ps1) and use the variables those set up there.

@{
    Name = 'vm-stopped-not-deallocated'
    Label = 'VMs stopped but not deallocated'
    Order = 5
    QuickWin = $true   # reversible, or nothing depends on it: listed under Quick wins when high confidence
    CommitmentEligible = $true   # a reservation or savings plan can cover it
    LivePrice = {
        $spot = $f.tier -eq 'Spot'
        $win  = $f.os -eq 'Windows' -and $f.extra -ne 'Windows_Server'   # Azure Hybrid Benefit = Linux rate
        $it = @(Get-RetailItems "serviceName eq 'Virtual Machines' and armRegionName eq '$rg' and armSkuName eq '$(Get-ODataLiteral $sku)'") |
            Where-Object { $_.unitOfMeasure -eq '1 Hour' -and ($_.skuName -notlike '*Low Priority*') -and (($_.skuName -like '*Spot*') -eq $spot) -and (($_.productName -like '*Windows*') -eq $win) } |
            Select-Object -First 1
        if ($it) { return @{ Cost = [double] $it.retailPrice * $hours; Note = "$sku $($win ? 'Windows' : 'Linux')$($spot ? ' Spot' : '') list price, $region" } }
    }
    Estimate = {
        if ($sku -notmatch '^(?:Standard|Basic)_([A-Za-z])[A-Za-z]*?(\d+)') { return @{ Cost = $null; Note = "unknown size $sku" } }
        $fam = $Matches[1].ToUpper(); $vcpu = [int] $Matches[2]
        $rate = $Pricing.vms.perVcpuHourByFamily[$fam] ?? $Pricing.vms.defaultPerVcpuHour
        if ($f.os -eq 'Windows' -and $f.extra -ne 'Windows_Server') { $rate += $Pricing.vms.windowsPerVcpuHour }
        $cost = $rate * $vcpu * $Pricing.hoursPerMonth
        if ($f.tier -eq 'Spot') { $cost *= 0.2 }
        return @{ Cost = $cost; Note = "list price ~$vcpu vCPU $fam-family$(($f.tier -eq 'Spot') ? ', Spot' : '')" }
    }
    Action = {
        return @(
            "Deallocate it to stop compute billing (its disks keep billing), or delete it if it's no longer needed. Deallocating releases dynamic public IPs.",
            "az vm deallocate --ids $id")
    }
}
