# waste-hunter 12 · Azure OpenAI / AI Services deployments that bill while idle (CANDIDATES)
# Waste-type record(s) for queries/12-openai-accounts.kql: label, flags and the logic for each step. Loaded by
# Import-WasteTypes (lib/Common.ps1). The script blocks run inside Confirm-Candidate, Get-LivePrice,
# Get-Estimate and Get-Action (lib/WasteTypes.ps1) and use the variables those set up there.

@{
    Name = 'idle-openai-deployment'
    Label = 'Idle Azure OpenAI deployments that bill hourly'
    Order = 12
    Candidate = $true
    CommitmentEligible = $true   # a reservation or savings plan can cover it
    Check = {
        $deps = @(Invoke-AzRead @('cognitiveservices', 'account', 'deployment', 'list', '-g', $r.resourceGroup, '-n', $r.name, '--subscription', $r.subscriptionId))
        # Only names, SKU and model are read from each deployment, never anything else
        $info = foreach ($d in $deps) {
            if (-not $d) { continue }
            $skuN = [string] (Get-Key (Get-Key $d 'sku') 'name')
            $model = [string] (Get-Key (Get-Key (Get-Key $d 'properties') 'model') 'name')
            [pscustomobject] @{ Name = [string] (Get-Key $d 'name'); Sku = $skuN; Model = $model
                Capacity = [int] ((Get-Key (Get-Key $d 'sku') 'capacity') ?? 0)
                Created = [string] (Get-Key (Get-Key $d 'systemData') 'createdAt')
                Ptu = $skuN -like '*Provisioned*'; FineTuned = $model -match '\.ft-|^ft:' }
        }
        $billable = @($info | Where-Object { $_.Ptu -or $_.FineTuned })
        if (-not $billable) { return @() }
        $m = Get-MetricStats $r.id @('AzureOpenAIRequests') 'Total' -Filter "ModelDeploymentName eq '*'"
        $byDep = $m['AzureOpenAIRequests'] ? $m['AzureOpenAIRequests'].BySplit : @{}
        $out = @()
        foreach ($d in $billable) {
            $reqs = [double] ($byDep[$d.Name] ?? 0)
            if ($reqs -gt 0) { continue }
            $ageD = $d.Created ? [int] ($Now - [DateTimeOffset]::Parse($d.Created, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime).TotalDays : $null
            $billing = $d.Ptu ? "$($d.Capacity) PTU of $($d.Sku)" : 'fine-tuned model hosting'
            $conf = ($null -ne $ageD -and $ageD -lt $MinAgeDays) ? 'medium' : 'high'
            $why = "Deployment '$($d.Name)' (model $($d.Model)) bills hourly for $billing but had 0 requests in 30 days"
            if ($d.Ptu) { $why += '. If a PTU reservation covers it, the commitment is already paid, but the capacity is still unused' }
            if ($conf -eq 'medium') { $why += "; created $ageD day(s) ago" }
            $out += New-FindingFrom $r @{ id = "$($r.id)/deployments/$($d.Name)"; name = "$($r.name)/$($d.Name)"; type = 'microsoft.cognitiveservices/accounts/deployments'
                sku = $d.Sku; tier = $d.Ptu ? 'provisioned' : 'fine-tuned'; sizeGb = $d.Capacity; extra = $d.Model
                createdTime = $d.Created; ageDays = $ageD; idleDays = [math]::Min(30, ($ageD ?? 30)); idleSource = 'AzureOpenAIRequests by deployment, 30 days'
                confidence = $conf; reason = $why; ptu = $d.Ptu; capacity = $d.Capacity }
        }
        return $out
    }
    LivePrice = {
        if (-not $f.ptu) { return $null }   # fine-tuned hosting is priced per model: pricing.json
        $meter = @{ ProvisionedManaged = 'Provisioned Managed Regional Unit'; GlobalProvisionedManaged = 'Provisioned Managed Global Unit'; DataZoneProvisionedManaged = 'Provisioned Managed Data Zone Unit' }[$sku]
        if (-not $meter) { return $null }
        $it = @(Get-RetailItems "serviceName eq 'Foundry Models' and armRegionName eq '$rg' and productName eq 'Azure OpenAI' and meterName eq '$meter'") |
            Where-Object { $_.unitOfMeasure -eq '1/Hour' } | Select-Object -First 1
        if ($it) { return @{ Cost = [double] $it.retailPrice * $hours * $f.capacity; Note = "$($f.capacity) PTU x $meter list price, $region" } }
    }
    Estimate = {
        $p = $Pricing.openAI
        if ($f.ptu) {
            $rate = $p.ptuPerHour[$sku]
            if ($null -eq $rate) { return @{ Cost = $null; Note = "no list price for $sku" } }
            return @{ Cost = $rate * $Pricing.hoursPerMonth * $f.capacity; Note = "$($f.capacity) PTU x $sku list price" }
        }
        return @{ Cost = $p.fineTunedHostingPerHour * $Pricing.hoursPerMonth; Note = 'typical fine-tuned hosting rate; varies by model' }
    }
    Action = {
        return @(
            "Delete the deployment (re-create it when needed). For PTU, also check whether a reservation covers it before you rely on the saving.",
            "az cognitiveservices account deployment delete -g $($f.resourceGroup) -n $(($f.name -split '/')[0]) --deployment-name $(($f.name -split '/')[-1]) --subscription $($f.subscriptionId)")
    }
}
