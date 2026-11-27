# waste-hunter 35 · Azure Hybrid Benefit not applied
# Waste-type record(s) for queries/35-hybrid-benefit-not-applied.kql: label, flags and the logic for each step. Loaded by
# Import-WasteTypes (lib/WasteTypes.ps1). The script blocks run inside Confirm-Candidate, Get-LivePrice,
# Get-Estimate and Get-Action (lib/WasteTypes.ps1) and use the variables those set up there.

@{
    Name = 'hybrid-benefit-not-applied'
    Label = 'Azure Hybrid Benefit not applied (if you own licences)'
    Order = 35
    PartialSaving = $true   # the saving is the licence part of the price, never the whole bill
    LivePrice = {
        # Windows: the Windows price minus the Linux price of the same size. SQL: pricing.json.
        if ($f.tier -ne 'windows-vm') { return $null }
        $win = Get-VmHourlyPrice $sku $region $true; $lin = Get-VmHourlyPrice $sku $region $false
        if ($null -ne $win -and $null -ne $lin -and $win -gt $lin) { return @{ Cost = ($win - $lin) * $hours; Note = "$sku Windows minus Linux list price, $region" } }
    }
    Estimate = {
        $lic = $Pricing.licensing.sqlPerVcoreHour
        switch ([string] $f.tier) {
            'windows-vm' {
                $sh = Get-VmShape $sku
                if (-not $sh) { return @{ Cost = $null; Note = "unknown size $sku" } }
                return @{ Cost = $Pricing.vms.windowsPerVcpuHour * $sh.Vcpu * $Pricing.hoursPerMonth; Note = "Windows licence part of the $sku list price" }
            }
            'sql-vm' {
                $sh = Get-VmShape $sku; $rate = Get-Key $lic ([string] $f.os)
                if (-not $sh -or $null -eq $rate) { return @{ Cost = $null; Note = "unknown size $sku" } }
                return @{ Cost = $rate * [math]::Max(4, $sh.Vcpu) * $Pricing.hoursPerMonth; Note = "SQL $($f.os) licence part, $([math]::Max(4, $sh.Vcpu)) vCPU (4 minimum)" }
            }
            default {
                $rate = Get-Key $lic ([string] $f.os)
                if ($null -eq $rate -or -not $f.sizeGb) { return @{ Cost = $null; Note = "no licence price for $($f.os)" } }
                return @{ Cost = $rate * [int] $f.sizeGb * $Pricing.hoursPerMonth; Note = "SQL licence part of $($f.sizeGb) vCore $($f.os)" }
            }
        }
    }
    Action = {
        $cmd = switch ([string] $f.tier) {
            'windows-vm' { "az vm update --ids $id --license-type Windows_Server" }
            'sql-vm' { "az sql vm update --ids $id --license-type AHUB" }
            'sql-mi' { "az sql mi update --ids $id --license-type BasePrice" }
            'sql-pool' { "az sql elastic-pool update --ids $id --license-type BasePrice" }
            default { "az sql db update --ids $id --license-type BasePrice" }
        }
        return @("Check with your licensing team whether you own eligible $(($f.tier -eq 'windows-vm') ? 'Windows Server' : 'SQL Server') licences with Software Assurance that aren't already assigned. If you do, turn on Azure Hybrid Benefit; if you don't, there's nothing to save, so exclude this finding.", $cmd)
    }
}
