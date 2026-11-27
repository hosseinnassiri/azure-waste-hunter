# waste-hunter 37 · Running VMs that barely use their CPUs (CANDIDATES, confirmed by metrics)
# Waste-type record(s) for queries/37-underused-vms.kql: label, flags and the logic for each step. Loaded by
# Import-WasteTypes (lib/WasteTypes.ps1). The script blocks run inside Confirm-Candidate, Get-LivePrice,
# Get-Estimate and Get-Action (lib/WasteTypes.ps1) and use the variables those set up there.

@{
    Name = 'underused-vm'
    Label = 'Oversized VMs (CPU nearly idle)'
    Order = 37
    Candidate = $true
    PartialSaving = $true        # one size down saves about half, not the whole bill
    CommitmentEligible = $true   # a reservation or savings plan can cover it
    Check = {
        if ($young) { return @() }
        $sh = Get-VmShape ([string] $ci.vmSize)
        if (-not $sh -or $sh.Vcpu -lt 4) { return @() }         # 2 vCPUs rarely has a size below in the same family
        $cpu = (Get-MetricStats $r.id @('Percentage CPU') 'Average' 'PT1H')['Percentage CPU']
        if (-not $cpu -or $cpu.Points -lt 480) { return @() }   # under 20 days of hourly data: not running long enough to judge
        $p95 = Get-Percentile $cpu.Values 95
        if ($p95 -ge 5) { return @() }
        $why = ('CPU averaged under {0:N1}% in 95% of hours over 30 days (busiest hour {1:N1}%) on {2} vCPUs ({3}). Half the vCPUs would likely do; check memory use first, which is not measured here' -f
                $p95, $cpu.Max, $sh.Vcpu, $r.sku)
        return @(New-FindingFrom $r @{ confidence = 'medium'; reason = $why; idleSource = 'Percentage CPU (hourly average), 30 days'; cpuP95 = $p95 })
    }
    LivePrice = {
        $win = $f.os -eq 'Windows' -and $f.extra -ne 'Windows_Server'
        $p = Get-VmHourlyPrice $sku $region $win ($f.tier -eq 'Spot')
        if ($null -ne $p) { return @{ Cost = $p * $hours / 2; Note = "half the $sku $($win ? 'Windows' : 'Linux') list price (one size down), $region" } }
    }
    Estimate = {
        $win = $f.os -eq 'Windows' -and $f.extra -ne 'Windows_Server'
        $p = Get-VmHourlyEstimate $sku $win
        if ($null -eq $p) { return @{ Cost = $null; Note = "unknown size $sku" } }
        return @{ Cost = $p * $Pricing.hoursPerMonth / 2; Note = "half the $sku list price (one size down)" }
    }
    Action = {
        return @(
            "Check memory and disk throughput with $who (the smaller size halves those too), then resize to the next size down in the same family. Resizing restarts the VM.",
            "az vm resize --ids $id --size <next smaller size>")
    }
}
