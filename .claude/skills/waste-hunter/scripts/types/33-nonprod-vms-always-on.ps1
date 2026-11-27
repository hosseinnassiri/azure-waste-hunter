# waste-hunter 33 · Non-production VMs running around the clock
# Waste-type record(s) for queries/33-nonprod-vms-always-on.kql: label, flags and the logic for each step. Loaded by
# Import-WasteTypes (lib/WasteTypes.ps1). The script blocks run inside Confirm-Candidate, Get-LivePrice,
# Get-Estimate and Get-Action (lib/WasteTypes.ps1) and use the variables those set up there.

@{
    Name = 'nonprod-vm-always-on'
    Label = 'Non-production VMs with no shutdown schedule'
    Order = 33
    PartialSaving = $true        # a schedule saves the off hours, not the whole bill
    CommitmentEligible = $true   # a reservation covering it makes off hours worth nothing
    QuickWin = $true             # a schedule is easy to change or remove
    LivePrice = {
        $win = $f.os -eq 'Windows' -and $f.extra -ne 'Windows_Server'
        $p = Get-VmHourlyPrice $sku $region $win ($f.tier -eq 'Spot')
        $off = $Pricing.schedules.offHoursFraction
        if ($null -ne $p) { return @{ Cost = $p * $hours * $off; Note = ('{0} {1} list price x {2:P0} of the week off (running 07:00-19:00 on weekdays only), {3}' -f $sku, ($win ? 'Windows' : 'Linux'), $off, $region) } }
    }
    Estimate = {
        $win = $f.os -eq 'Windows' -and $f.extra -ne 'Windows_Server'
        $p = Get-VmHourlyEstimate $sku $win
        if ($null -eq $p) { return @{ Cost = $null; Note = "unknown size $sku" } }
        $off = $Pricing.schedules.offHoursFraction
        return @{ Cost = $p * $Pricing.hoursPerMonth * $off; Note = ('{0} list price x {1:P0} of the week off (running 07:00-19:00 on weekdays only)' -f $sku, $off) }
    }
    Action = {
        return @(
            "Agree working hours with $who and add an auto-shutdown schedule (or Start/Stop VMs v2 for start and stop). Shutdown deallocates, so compute stops billing; disks keep billing.",
            "az vm auto-shutdown --ids $id --time 1900")
    }
}
