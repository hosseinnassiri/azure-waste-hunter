# waste-hunter 11 · Container registries: idle, or Premium without Premium features (CANDIDATES)
# Waste-type record(s) for queries/11-container-registries.kql: label, flags and the logic for each step. Loaded by
# Import-WasteTypes (lib/Common.ps1). The script blocks run inside Confirm-Candidate, Get-LivePrice,
# Get-Estimate and Get-Action (lib/WasteTypes.ps1) and use the variables those set up there.

# Logic shared by the records below (idle-container-registry and oversized-container-registry)
$SharedBodies = @{
    LivePrice = {
        $items = @(Get-RetailItems "serviceName eq 'Container Registry' and armRegionName eq '$rg'")
        $unit = @{}
        foreach ($s in 'Basic', 'Standard', 'Premium') {
            $it = $items | Where-Object { $_.meterName -eq "$s Registry Unit" -and $_.unitOfMeasure -eq '1/Day' } | Select-Object -First 1
            if ($it) { $unit[$s] = [double] $it.retailPrice }
        }
        $stor = $items | Where-Object { $_.meterName -eq 'Data Stored' -and $_.skuName -eq $sku -and $_.unitOfMeasure -eq '1 GB/Month' } | Select-Object -First 1
        $repl = $items | Where-Object { $_.meterName -eq 'Premium Registry Replication Unit' -and $_.unitOfMeasure -eq '1/Day' } | Select-Object -First 1
        if ($f.wasteType -eq 'oversized-container-registry') {
            if ($unit['Premium'] -and $unit['Standard']) { return @{ Cost = ($unit['Premium'] - $unit['Standard']) * 30; Note = "Premium minus Standard list price, $region" } }
        }
        elseif ($unit[$sku]) {
            $c = Get-RegistryCost $f $unit[$sku] ($stor ? [double] $stor.retailPrice : 0.1) ($repl ? [double] $repl.retailPrice : 0)
            return @{ Cost = $c; Note = "$sku registry list price incl. storage over the included amount, $region" }
        }
    }
}

@{
    Name = 'idle-container-registry'
    Label = 'Idle container registries'
    Order = 11
    Candidate = $true
    Check = {
        if ($young) { return @() }
        $pulls = Get-StatSum (Get-MetricStats $r.id @('TotalPullCount') 'Total') 'TotalPullCount'
        $storeGiB = (Get-StatLast (Get-MetricStats $r.id @('StorageUsed') 'Average' 'PT1H' 2) 'StorageUsed') / 1GB
        $refs = @($ci.referencedBy | Where-Object { $_ })
        $repl = [int] ($ci.replications ?? 0)
        if ($pulls -eq 0) {
            $conf = $refs ? 'low' : 'high'
            $why = "0 image pulls by any client in 30 days; $('{0:N1}' -f $storeGiB) GiB stored"
            if ($repl) { $why += "; $repl geo-replication(s), each billed" }
            if ($refs) { $why += "; still referenced by Container App(s) $($refs -join ', '). Scale-to-zero apps only pull when a replica starts, so deleting it would break the next scale-up." }
            return @(New-FindingFrom $r @{ confidence = $conf; reason = $why; idleDays = 30; idleSource = 'TotalPullCount metric, 30 days'
                                           sizeGb = [math]::Round($storeGiB, 1); storeGiB = $storeGiB; replications = $repl })
        }
        if ($r.sku -eq 'Premium' -and $repl -eq 0 -and [int] ($ci.privateEndpoints ?? 0) -eq 0 -and $storeGiB -le 100) {
            $why = "Premium registry with no geo-replications, no private endpoints and $('{0:N1}' -f $storeGiB) GiB stored, which fits Standard's 100 GiB included storage. Check for other Premium-only features (content trust, dedicated data endpoints, connected registries) first"
            return @(New-FindingFrom $r @{ wasteType = 'oversized-container-registry'; confidence = 'medium'; reason = $why
                                           idleDays = $null; idleSource = "$([int] $pulls) pulls in 30 days (in use)"; sizeGb = [math]::Round($storeGiB, 1); storeGiB = $storeGiB })
        }
        return @()
    }
    LivePrice = $SharedBodies.LivePrice
    Estimate = {
        $p = $Pricing.containerRegistries
        $unit = $p.unitPerDay[$sku]
        if ($null -eq $unit) { return @{ Cost = $null; Note = "no list price for $sku" } }
        return @{ Cost = Get-RegistryCost $f $unit $p.storagePerGbMonth $p.replicationUnitPerDay; Note = "$sku registry list price incl. storage over the included amount" }
    }
    Action = {
        if ($f.confidence -eq 'low') { return @(
            'Keep it while the referencing Container App(s) exist. They pull from it when a replica starts. If those apps are retired, delete the registry along with them.',
            '') }
        return @("Confirm with $who that no pipeline or cluster pulls from it, export any images you need, then delete it.",
                 "az acr delete --ids $id")
    }
}

@{
    Name = 'oversized-container-registry'
    Label = 'Premium container registries not using Premium'
    Order = 11.5
    Parent = 'idle-container-registry'   # emitted by the parent's check
    PartialSaving = $true   # the saving is a price difference, never the whole bill
    LivePrice = $SharedBodies.LivePrice
    Estimate = {
        $p = $Pricing.containerRegistries
        return @{ Cost = ($p.unitPerDay['Premium'] - $p.unitPerDay['Standard']) * 30; Note = 'Premium minus Standard list price' }
    }
    Action = {
        return @(
            'Downgrade to Standard if you rely on none of geo-replication, private endpoints, content trust, dedicated data endpoints or connected registries.',
            "az acr update --ids $id --sku Standard")
    }
}
