# waste-hunter 04 · Empty App Service plans (no apps)
# Waste-type record(s) for queries/04-empty-app-service-plans.kql: label, flags and the logic for each step. Loaded by
# Import-WasteTypes (lib/Common.ps1). The script blocks run inside Confirm-Candidate, Get-LivePrice,
# Get-Estimate and Get-Action (lib/WasteTypes.ps1) and use the variables those set up there.

# Logic shared by the records below (empty-app-service-plan and stopped-app-service-plan)
$SharedBodies = @{
    LivePrice = {
        if ($sku -in $Pricing.appServicePlans.free -or $f.tier -in $Pricing.appServicePlans.free) { return $null }   # free; Get-Estimate says so
        if ($sku -like 'EP*' -or $sku -like 'WS*') { return $null }   # Elastic Premium / Workflow: vCPU+memory meters
        # The API spells some SKUs with a space ('P1 v3', 'I1 v2') and others without ('P0v3', 'P1mv3')
        $alt = $sku -replace '(\d)(v\d)$', '$1 $2'
        $linux = $f.os -eq 'Linux'
        $it = @(Get-RetailItems "serviceName eq 'Azure App Service' and armRegionName eq '$rg' and (skuName eq '$(Get-ODataLiteral $sku)' or skuName eq '$(Get-ODataLiteral $alt)')") |
            Where-Object { $_.unitOfMeasure -eq '1 Hour' -and (($_.productName -like '* - Linux') -eq $linux) } | Select-Object -First 1
        if ($it) { $n = [math]::Max(1, [int] $f.sizeGb); return @{ Cost = [double] $it.retailPrice * $hours * $n; Note = "$sku $($f.os) list price x$n, $region" } }
    }
    Estimate = {
        if ($sku -in $Pricing.appServicePlans.free -or $f.tier -in $Pricing.appServicePlans.free) { return @{ Cost = 0.0; Note = 'free tier' } }
        $tbl = $Pricing.appServicePlans[[string] $f.os]
        $price = $tbl ? $tbl[$sku] : $null
        if ($null -eq $price) { return @{ Cost = $null; Note = "no list price for $sku" } }
        $n = [math]::Max(1, [int] $f.sizeGb)
        return @{ Cost = $price * $n; Note = "list price $sku x$n" }
    }
}

@{
    Name = 'empty-app-service-plan'
    Label = 'Empty App Service plans'
    Order = 4
    CommitmentEligible = $true   # a reservation or savings plan can cover it
    LivePrice = $SharedBodies.LivePrice
    Estimate = $SharedBodies.Estimate
    Action = {
        if ($f.confidence -eq 'low') { return @('No charge while empty. Delete to reduce clutter.', "az appservice plan delete --ids $id") }
        return @("Delete the plan if no deployment is planned. If it's being kept for upcoming work, scale it down to Free or B1 until needed.",
                 "az appservice plan delete --ids $id")
    }
}
