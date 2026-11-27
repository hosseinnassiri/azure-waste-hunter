# Part of Invoke-WasteHunt.ps1 (dot-sourced into its scope, so it shares the runner's variables).
# READ-ONLY: see CLAUDE.md. Functions only; nothing runs when this file is loaded.

function Confirm-Candidate($r) {
    $ci = (Get-Key $r 'checkInputs') ?? @{}
    $young = ($null -ne $r.ageDays -and [int] $r.ageDays -lt $MinAgeDays)
    switch ($r.wasteType) {
        'idle-container-app' {
            $m = Get-MetricStats $r.id @('Requests', 'RxBytes', 'TxBytes') 'Total'
            $req = Get-StatSum $m 'Requests'; $net = (Get-StatSum $m 'RxBytes') + (Get-StatSum $m 'TxBytes')
            if ($req -gt 0 -or $net -gt 100MB) { return @() }
            $http = [bool] $ci.hasIngress -and $ci.transport -ne 'Tcp'
            $dedicated = $ci.workloadProfile -and $ci.workloadProfile -ne 'Consumption'
            $conf = ($http -and -not $dedicated) ? 'high' : 'medium'
            $why = "minReplicas $($ci.minReplicas) keeps replicas running, but there were $([int] $req) requests and $(Format-Bytes $net) of network traffic in 30 days"
            if (-not $http) { $why += '; no HTTP ingress, so this is judged by network traffic only (a quiet background worker looks the same)' }
            if ($dedicated) { $why += "; runs on dedicated workload profile '$($ci.workloadProfile)', billed per node, not per app" }
            return @(New-FindingFrom $r @{ confidence = $conf; reason = $why; idleDays = 30; idleSource = 'Requests/RxBytes/TxBytes metrics, 30 days'
                                           cpu = [double] $ci.cpu; memGiB = (@($ci.memory) | ForEach-Object { ConvertTo-GiB $_ } | Measure-Object -Sum).Sum
                                           minReplicas = [int] $ci.minReplicas; dedicated = $dedicated })
        }
        'log-analytics-workspace' {
            $m = Get-MetricStats $r.id @('Ingestion Volume', 'Query Count') 'Count'
            $records = Get-StatSum $m 'Ingestion Volume'; $queries = Get-StatSum $m 'Query Count'
            $problems = @(); $conf = 'low'
            if ([int] $ci.retention -gt [int] $ci.freeRetention) {
                $sentinelNote = [bool] $ci.sentinel ? ' with Sentinel' : ''
                $problems += "retention is $($ci.retention) days, above the free $($ci.freeRetention) days$sentinelNote"
            }
            if ($records -gt 0 -and $queries -eq 0 -and -not $young) {
                $problems += "$('{0:N0}' -f $records) records ingested in 30 days but 0 queries, including alert queries"
                $conf = 'medium'
            }
            if (-not $problems) { return @() }
            $why = ($problems -join '; ') + '. Cost depends on GB ingested and retained, which platform metrics do not expose (see the workspace''s Usage and estimated costs page).'
            $retentionOnly = $problems.Count -eq 1 -and $problems[0] -like 'retention*'
            if ($retentionOnly) { $why += ' Longer retention may be a compliance requirement.' }
            # Retention only: lowering it saves the retention charge, not the workspace's whole bill
            return @(New-FindingFrom $r @{ confidence = $conf; reason = $why; idleDays = $null; idleSource = 'Ingestion Volume/Query Count metrics, 30 days'
                                           records = $records; queries = $queries; partialSaving = $retentionOnly })
        }
        'idle-storage-account' {
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
        'idle-container-registry' {
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
        'idle-openai-deployment' {
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
        'idle-bastion' {
            # `sessions` only supports 5- and 15-minute grains
            $sessions = Get-StatSum (Get-MetricStats $r.id @('sessions') 'Total' 'PT15M') 'sessions'
            if ($sessions -gt 0) { return @() }
            $why = "0 Bastion sessions in 30 days ($($r.sku), $($ci.scaleUnits) scale unit(s)), billed hourly regardless"
            return @(New-FindingFrom $r @{ confidence = 'high'; reason = $why; idleDays = 30; idleSource = 'sessions metric, 30 days'; scaleUnits = [int] ($ci.scaleUnits ?? 2) })
        }
        'idle-sql-database' {
            if ($young) { return @() }
            $conns = Get-StatSum (Get-MetricStats $r.id @('connection_successful') 'Total') 'connection_successful'
            if ($conns -gt 0) { return @() }
            $size = $ci.vcores ? "$($ci.vcores) vCore(s)" : $r.sku
            $why = "0 successful connections in 30 days ($($r.sku), $size), but compute bills every hour"
            return @(New-FindingFrom $r @{ confidence = 'high'; reason = $why; idleDays = 30; idleSource = 'connection_successful metric, 30 days'
                                           vcores = [int] ($ci.vcores ?? 0); sqlTier = [string] $ci.tier })
        }
        'idle-firewall' {
            # Hourly grain: these metrics are published per minute, and 30 days of hours is 720 points
            $m = Get-MetricStats $r.id @('DataProcessed', 'ApplicationRuleHit', 'NetworkRuleHit') 'Total' 'PT1H'
            $bytes = Get-StatSum $m 'DataProcessed'; $hits = (Get-StatSum $m 'ApplicationRuleHit') + (Get-StatSum $m 'NetworkRuleHit')
            if ($hits -gt 0 -or $bytes -ge 1GB) { return @() }
            $conf = ($bytes -lt 100MB) ? 'high' : 'medium'
            $where = [bool] $ci.hub ? ' in a virtual hub' : ''
            $why = "0 application or network rule hits and $(Format-Bytes $bytes) processed in 30 days ($($ci.tier)$where), but the deployment fee bills every hour"
            if ($conf -eq 'medium') { $why += '. Some traffic still flows (DNAT rules have no hit metric), so check what routes through it first' }
            return @(New-FindingFrom $r @{ confidence = $conf; reason = $why; idleDays = 30; idleSource = 'DataProcessed and rule hit metrics, 30 days'
                                           hub = [bool] $ci.hub })
        }
        'premium-disk-deallocated-vm' {
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
    }
    return @()
}

function Get-LivePrice($f) {
    $region = ([string] $f.location).ToLower()
    if ($script:PriceApiDown -or -not $region -or $region -eq 'global') { return $null }
    $sku = [string] $f.sku; $rg = Get-ODataLiteral $region; $hours = $Pricing.hoursPerMonth
    $red = ($sku -like '*_ZRS') ? 'ZRS' : 'LRS'
    switch ($f.wasteType) {
        'unattached-disk' {
            $prod = @{ Premium = 'Premium SSD Managed Disks'; StandardSSD = 'Standard SSD Managed Disks'; Standard = 'Standard HDD Managed Disks' }[($sku -split '_')[0]]
            $tier = Get-DiskTier $f
            if (-not $prod -or -not $tier) { return $null }
            $m = "$($tier.Name) $red"
            $it = @(Get-RetailItems "serviceName eq 'Storage' and armRegionName eq '$rg' and productName eq '$prod' and skuName eq '$m'") |
                Where-Object { $_.meterName -eq "$m Disk" -and $_.unitOfMeasure -eq '1/Month' } | Select-Object -First 1
            if ($it) { return @{ Cost = [double] $it.retailPrice; Note = "$m list price, $region" } }
        }
        'old-snapshot' {
            $prod = ($sku -like 'Premium*') ? 'Premium SSD Managed Disks' : 'Standard HDD Managed Disks'
            $it = @(Get-RetailItems "serviceName eq 'Storage' and armRegionName eq '$rg' and productName eq '$prod' and skuName eq 'Snapshots $red'") |
                Where-Object { $_.meterName -eq "$red Snapshots" -and $_.unitOfMeasure -eq '1 GB/Month' } | Select-Object -First 1
            if ($it) { return @{ Cost = [double] $it.retailPrice * [int] $f.sizeGb; Note = "$red snapshot list price, $region; upper bound, provisioned GiB" } }
        }
        'unassociated-public-ip' {
            if ($sku -ne 'Standard' -and $f.confidence -eq 'low') { return $null }   # no charge; Get-Estimate says so
            $ipSku = ($f.tier -eq 'Global') ? 'Global' : $sku
            $it = @(Get-RetailItems "serviceName eq 'Virtual Network' and armRegionName eq '$rg' and productName eq 'IP Addresses' and skuName eq '$(Get-ODataLiteral $ipSku)'") |
                Where-Object { $_.meterName -eq "$ipSku IPv4 Static Public IP" -and $_.unitOfMeasure -eq '1 Hour' } | Select-Object -First 1
            if ($it) { return @{ Cost = [double] $it.retailPrice * $hours; Note = "$ipSku static IP list price, $region" } }
        }
        { $_ -in 'empty-app-service-plan', 'stopped-app-service-plan' } {
            if ($sku -in $Pricing.appServicePlans.free -or $f.tier -in $Pricing.appServicePlans.free) { return $null }   # free; Get-Estimate says so
            if ($sku -like 'EP*' -or $sku -like 'WS*') { return $null }   # Elastic Premium / Workflow: vCPU+memory meters
            # The API spells some SKUs with a space ('P1 v3', 'I1 v2') and others without ('P0v3', 'P1mv3')
            $alt = $sku -replace '(\d)(v\d)$', '$1 $2'
            $linux = $f.os -eq 'Linux'
            $it = @(Get-RetailItems "serviceName eq 'Azure App Service' and armRegionName eq '$rg' and (skuName eq '$(Get-ODataLiteral $sku)' or skuName eq '$(Get-ODataLiteral $alt)')") |
                Where-Object { $_.unitOfMeasure -eq '1 Hour' -and (($_.productName -like '* - Linux') -eq $linux) } | Select-Object -First 1
            if ($it) { $n = [math]::Max(1, [int] $f.sizeGb); return @{ Cost = [double] $it.retailPrice * $hours * $n; Note = "$sku $($f.os) list price x$n, $region" } }
        }
        'vm-stopped-not-deallocated' {
            $spot = $f.tier -eq 'Spot'
            $win  = $f.os -eq 'Windows' -and $f.extra -ne 'Windows_Server'   # Azure Hybrid Benefit = Linux rate
            $it = @(Get-RetailItems "serviceName eq 'Virtual Machines' and armRegionName eq '$rg' and armSkuName eq '$(Get-ODataLiteral $sku)'") |
                Where-Object { $_.unitOfMeasure -eq '1 Hour' -and ($_.skuName -notlike '*Low Priority*') -and (($_.skuName -like '*Spot*') -eq $spot) -and (($_.productName -like '*Windows*') -eq $win) } |
                Select-Object -First 1
            if ($it) { return @{ Cost = [double] $it.retailPrice * $hours; Note = "$sku $($win ? 'Windows' : 'Linux')$($spot ? ' Spot' : '') list price, $region" } }
        }
        'idle-container-app' {
            if ($f.dedicated) { return $null }
            $cf = "serviceName eq 'Azure Container Apps' and armRegionName eq '$rg'"
            $pv = Get-MeterPrice $cf { $_.meterName -eq 'Standard vCPU Idle Usage' -and $_.unitOfMeasure -eq '1 Second' }
            $pm = Get-MeterPrice $cf { $_.meterName -eq 'Standard Memory Idle Usage' -and $_.unitOfMeasure -eq '1 GiB Second' }
            if ($null -ne $pv -and $null -ne $pm) { return @{ Cost = Get-ContainerAppIdleCost $f $pv $pm; Note = "idle-rate list price x$($f.minReplicas) replica(s), $region; upper bound, free grant not applied" } }
        }
        { $_ -in 'idle-storage-account', 'hot-blob-unread' } {
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
        { $_ -in 'idle-container-registry', 'oversized-container-registry' } {
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
        'idle-openai-deployment' {
            if (-not $f.ptu) { return $null }   # fine-tuned hosting is priced per model: pricing.json
            $meter = @{ ProvisionedManaged = 'Provisioned Managed Regional Unit'; GlobalProvisionedManaged = 'Provisioned Managed Global Unit'; DataZoneProvisionedManaged = 'Provisioned Managed Data Zone Unit' }[$sku]
            if (-not $meter) { return $null }
            $it = @(Get-RetailItems "serviceName eq 'Foundry Models' and armRegionName eq '$rg' and productName eq 'Azure OpenAI' and meterName eq '$meter'") |
                Where-Object { $_.unitOfMeasure -eq '1/Hour' } | Select-Object -First 1
            if ($it) { return @{ Cost = [double] $it.retailPrice * $hours * $f.capacity; Note = "$($f.capacity) PTU x $meter list price, $region" } }
        }
        'idle-load-balancer' {
            $rules = [int] ($f.sizeGb ?? 0)
            if ($rules -eq 0 -or $sku -notin 'Standard', 'Global') { return $null }
            # Load Balancer and NAT Gateway are priced under armRegionName 'Global' / 'US Gov', not per region
            $lf = "serviceName eq 'Load Balancer' and armRegionName eq '$(Get-PriceZone $region)' and skuName eq '$sku'"
            $inc = Get-MeterPrice $lf { $_.meterName -eq "$sku Included LB Rules and Outbound Rules" }
            $ovr = Get-MeterPrice $lf { $_.meterName -eq "$sku Overage LB Rules and Outbound Rules" }
            if ($null -ne $inc) { return @{ Cost = ($inc + [math]::Max(0, $rules - 5) * ($ovr ?? 0)) * $hours; Note = "$sku rules list price ($rules rule(s))" } }
        }
        'idle-application-gateway' {
            $prod = @{ Standard_v2 = 'Application Gateway Standard v2'; WAF_v2 = 'Application Gateway WAF v2'; Basic = 'Application Gateway Basic v2' }[$sku]
            if (-not $prod) { return $null }   # v1 sizes: pricing.json
            $meterSku = ($sku -eq 'Basic') ? 'Basic' : 'Standard'
            $af = "serviceName eq 'Application Gateway' and armRegionName eq '$rg' and productName eq '$prod'"
            $fixed = Get-MeterPrice $af { $_.meterName -eq "$meterSku Fixed Cost" }
            $cu = Get-MeterPrice $af { $_.meterName -eq "$meterSku Capacity Units" }
            if ($null -ne $fixed) { return @{ Cost = ($fixed + [int] ($f.sizeGb ?? 0) * ($cu ?? 0)) * $hours; Note = "$sku fixed + $($f.sizeGb) minimum capacity unit(s) list price, $region" } }
        }
        'idle-network-gateway' {
            switch ([string] $f.tier) {
                'nat' {
                    $p = Get-MeterPrice "serviceName eq 'NAT Gateway' and armRegionName eq '$(Get-PriceZone $region)' and skuName eq 'Standard'" { $_.meterName -eq 'Standard Gateway' }
                    if ($null -ne $p) { return @{ Cost = $p * $hours; Note = 'NAT gateway list price' } }
                }
                'vpn-gateway' {
                    $p = Get-MeterPrice "serviceName eq 'VPN Gateway' and armRegionName eq '$rg' and skuName eq '$(Get-ODataLiteral $sku)'" { $_.meterName -eq $sku -and $_.unitOfMeasure -eq '1 Hour' }
                    if ($null -ne $p) { return @{ Cost = $p * $hours; Note = "$sku list price, $region" } }
                }
                'er-gateway' {
                    $meter = @{ Standard = 'Standard Gateway'; HighPerformance = 'High Performance Gateway'; UltraPerformance = 'Ultra High Performance Gateway' }[$sku] ?? "$sku Gateway"
                    $p = Get-MeterPrice "serviceName eq 'ExpressRoute' and armRegionName eq '$rg' and meterName eq '$(Get-ODataLiteral $meter)'" { $_.unitOfMeasure -eq '1 Hour' }
                    if ($null -ne $p) { return @{ Cost = $p * $hours; Note = "$meter list price, $region" } }
                }
            }
        }
        'idle-bastion' {
            $bf = "serviceName eq 'Azure Bastion' and armRegionName eq '$rg' and skuName eq '$(Get-ODataLiteral $sku)'"
            $base = Get-MeterPrice $bf { $_.meterName -eq "$sku Gateway" -and $_.unitOfMeasure -eq '1 Hour' }
            $extra = ($sku -ne 'Basic') ? (Get-MeterPrice $bf { $_.meterName -eq "$sku Additional Gateway" -and $_.unitOfMeasure -eq '1 Hour' }) : 0
            if ($null -ne $base) { return @{ Cost = ($base + [math]::Max(0, [int] $f.scaleUnits - 2) * ($extra ?? 0)) * $hours; Note = "$sku Bastion list price, $($f.scaleUnits) scale unit(s), $region" } }
        }
        'idle-ddos-protection-plan' {
            $p = Get-MeterPrice "serviceName eq 'Azure DDOS Protection' and armRegionName eq '$rg' and skuName eq 'Network Protection'" { $_.meterName -eq 'Network Protection Plan' -and $_.unitOfMeasure -eq '1 Hour' }
            if ($null -ne $p) { return @{ Cost = $p * $hours; Note = "Network Protection plan list price, $region" } }
        }
        'idle-firewall' {
            # Hub firewalls have their own meters ('Standard Secure Virtual Hub', 'Premium Secured Virtual Hub')
            $meterSku = $f.hub ? (@{ Basic = 'Basic Secured Virtual Hub'; Standard = 'Standard Secure Virtual Hub'; Premium = 'Premium Secured Virtual Hub' }[$sku]) : $sku
            if (-not $meterSku) { return $null }
            $p = Get-MeterPrice "serviceName eq 'Azure Firewall' and armRegionName eq '$rg' and skuName eq '$(Get-ODataLiteral $meterSku)'" { $_.meterName -eq "$meterSku Deployment" -and $_.unitOfMeasure -eq '1 Hour' }
            if ($null -ne $p) { return @{ Cost = $p * $hours; Note = "$meterSku deployment list price, $region; capacity units and data processed extra" } }
        }
        'premium-disk-deallocated-vm' {
            $tier = Get-DiskTier $f
            if (-not $tier) { return $null }
            $eName = $Pricing.disks['StandardSSD_LRS'].tiers[$tier.Index]
            $p = Get-MeterPrice "serviceName eq 'Storage' and armRegionName eq '$rg' and productName eq 'Premium SSD Managed Disks' and skuName eq '$($tier.Name) $red'" { $_.meterName -eq "$($tier.Name) $red Disk" -and $_.unitOfMeasure -eq '1/Month' }
            $e = Get-MeterPrice "serviceName eq 'Storage' and armRegionName eq '$rg' and productName eq 'Standard SSD Managed Disks' and skuName eq '$eName $red'" { $_.meterName -eq "$eName $red Disk" -and $_.unitOfMeasure -eq '1/Month' }
            if ($null -ne $p -and $null -ne $e) { return @{ Cost = $p - $e; Note = "$($tier.Name) minus $eName $red list price, $region" } }
        }
    }
    return $null
}

function Get-Estimate($f) {
    $sku = [string] $f.sku
    switch ($f.wasteType) {
        'unattached-disk' {
            $tier = Get-DiskTier $f
            if ($tier) {
                $mult = ($sku -like '*_ZRS') ? $Pricing.disks.zrsMultiplier : 1
                return @{ Cost = $tier.Price * $mult; Note = "list price $($tier.Name)" }
            }
            $perGb = $Pricing.disks.perGbFallback[$sku] ?? $Pricing.disks.perGbFallback.default
            return @{ Cost = $perGb * [int] $f.sizeGb; Note = 'list price per GiB, capacity only' }
        }
        'old-snapshot' {
            $perGb = $Pricing.snapshotsPerGb[$sku] ?? $Pricing.snapshotsPerGb.default
            return @{ Cost = $perGb * [int] $f.sizeGb; Note = 'upper bound, provisioned GiB (billed on used GiB)' }
        }
        'unassociated-public-ip' {
            if ($sku -eq 'Standard') { return @{ Cost = $Pricing.publicIps.Standard; Note = 'list price' } }
            if ($f.confidence -eq 'low') { return @{ Cost = 0.0; Note = 'no charge' } }
            return @{ Cost = $Pricing.publicIps['Basic|Static']; Note = 'list price' }
        }
        { $_ -in 'empty-app-service-plan', 'stopped-app-service-plan' } {
            if ($sku -in $Pricing.appServicePlans.free -or $f.tier -in $Pricing.appServicePlans.free) { return @{ Cost = 0.0; Note = 'free tier' } }
            $tbl = $Pricing.appServicePlans[[string] $f.os]
            $price = $tbl ? $tbl[$sku] : $null
            if ($null -eq $price) { return @{ Cost = $null; Note = "no list price for $sku" } }
            $n = [math]::Max(1, [int] $f.sizeGb)
            return @{ Cost = $price * $n; Note = "list price $sku x$n" }
        }
        'vm-stopped-not-deallocated' {
            if ($sku -notmatch '^(?:Standard|Basic)_([A-Za-z])[A-Za-z]*?(\d+)') { return @{ Cost = $null; Note = "unknown size $sku" } }
            $fam = $Matches[1].ToUpper(); $vcpu = [int] $Matches[2]
            $rate = $Pricing.vms.perVcpuHourByFamily[$fam] ?? $Pricing.vms.defaultPerVcpuHour
            if ($f.os -eq 'Windows' -and $f.extra -ne 'Windows_Server') { $rate += $Pricing.vms.windowsPerVcpuHour }
            $cost = $rate * $vcpu * $Pricing.hoursPerMonth
            if ($f.tier -eq 'Spot') { $cost *= 0.2 }
            return @{ Cost = $cost; Note = "list price ~$vcpu vCPU $fam-family$(($f.tier -eq 'Spot') ? ', Spot' : '')" }
        }
        'orphaned-nic' { return @{ Cost = 0.0; Note = 'NICs are free' } }
        'idle-container-app' {
            if ($f.dedicated) { return @{ Cost = $null; Note = 'dedicated workload profile, billed per node' } }
            $p = $Pricing.containerApps
            return @{ Cost = Get-ContainerAppIdleCost $f $p.idlePerVcpuSecond $p.idlePerGiBSecond; Note = "idle-rate list price x$($f.minReplicas) replica(s); upper bound, free grant not applied" }
        }
        'log-analytics-workspace' { return @{ Cost = $null; Note = 'GB ingested and retained not exposed by metrics' } }
        { $_ -in 'idle-storage-account', 'hot-blob-unread' } {
            if ($sku -like 'Premium*') { return @{ Cost = $null; Note = 'premium storage is priced by provisioned size' } }
            $p = $Pricing.storagePerGb
            $mult = $p.redundancyMultiplier[(Get-StorageRedundancyName $sku)] ?? 1
            if ($f.wasteType -eq 'hot-blob-unread') { return @{ Cost = $f.usedGiB * ($p.Hot - $p.Cool) * $mult; Note = 'Hot minus Cool list price' } }
            $t = $f.tier ? [string] $f.tier : 'Hot'
            return @{ Cost = $f.usedGiB * ($p[$t] ?? $p.Hot) * $mult; Note = "all capacity at blob $t list price; approximate" }
        }
        'idle-container-registry' {
            $p = $Pricing.containerRegistries
            $unit = $p.unitPerDay[$sku]
            if ($null -eq $unit) { return @{ Cost = $null; Note = "no list price for $sku" } }
            return @{ Cost = Get-RegistryCost $f $unit $p.storagePerGbMonth $p.replicationUnitPerDay; Note = "$sku registry list price incl. storage over the included amount" }
        }
        'oversized-container-registry' {
            $p = $Pricing.containerRegistries
            return @{ Cost = ($p.unitPerDay['Premium'] - $p.unitPerDay['Standard']) * 30; Note = 'Premium minus Standard list price' }
        }
        'idle-openai-deployment' {
            $p = $Pricing.openAI
            if ($f.ptu) {
                $rate = $p.ptuPerHour[$sku]
                if ($null -eq $rate) { return @{ Cost = $null; Note = "no list price for $sku" } }
                return @{ Cost = $rate * $Pricing.hoursPerMonth * $f.capacity; Note = "$($f.capacity) PTU x $sku list price" }
            }
            return @{ Cost = $p.fineTunedHostingPerHour * $Pricing.hoursPerMonth; Note = 'typical fine-tuned hosting rate; varies by model' }
        }
        'idle-load-balancer' {
            $rules = [int] ($f.sizeGb ?? 0)
            if ($rules -eq 0) { return @{ Cost = 0.0; Note = 'no rules, no charge' } }
            $p = $Pricing.network.loadBalancer
            return @{ Cost = ($p.includedPerHour + [math]::Max(0, $rules - 5) * $p.overagePerRuleHour) * $Pricing.hoursPerMonth; Note = "Standard rules list price ($rules rule(s))" }
        }
        'idle-application-gateway' {
            $p = $Pricing.network.applicationGateway[$sku]
            if ($null -eq $p) { return @{ Cost = $null; Note = "no list price for $sku" } }
            $n = [math]::Max(1, [int] ($f.sizeGb ?? 0))
            $c = $p['fixedPerHour'] + $n * $p['perUnitHour']
            return @{ Cost = $c * $Pricing.hoursPerMonth; Note = "$sku list price, $n unit(s)" }
        }
        'idle-network-gateway' {
            $p = $Pricing.network
            $rate = switch ([string] $f.tier) {
                'nat' { $p.natGatewayPerHour }
                'vpn-gateway' { $p.vpnGatewayPerHour[$sku] }
                'er-gateway' { $p.erGatewayPerHour[$sku] }
                default { $null }
            }
            if ($null -eq $rate) { return @{ Cost = $null; Note = ($f.tier -eq 'er-circuit') ? 'circuit price depends on bandwidth, peering location and plan' : "no list price for $sku" } }
            return @{ Cost = $rate * $Pricing.hoursPerMonth; Note = "$sku list price" }
        }
        'idle-bastion' {
            $p = $Pricing.network.bastionPerHour
            $base = $p[$sku]
            if ($null -eq $base) { return @{ Cost = $null; Note = "no list price for $sku" } }
            $extra = $p["${sku}Additional"] ?? 0
            return @{ Cost = ($base + [math]::Max(0, [int] $f.scaleUnits - 2) * $extra) * $Pricing.hoursPerMonth; Note = "$sku Bastion list price" }
        }
        'idle-sql-database' {
            $p = $Pricing.sqlDatabase
            $dtu = $p.dtuPerMonth[$sku]
            if ($null -ne $dtu) { return @{ Cost = $dtu; Note = "$sku list price, compute only (storage extra)" } }
            $vRate = $p.vcorePerHour[[string] $f.sqlTier]
            if ($null -ne $vRate -and $f.vcores) { return @{ Cost = $vRate * $f.vcores * $Pricing.hoursPerMonth; Note = "$($f.vcores) vCore $($f.sqlTier) list price, compute only (storage extra)" } }
            return @{ Cost = $null; Note = "no list price for $sku" }
        }
        'premium-disk-deallocated-vm' {
            $tier = Get-DiskTier $f
            if (-not $tier) { return @{ Cost = $null; Note = "no tier price for $sku" } }
            $e = $Pricing.disks['StandardSSD_LRS']
            $mult = ($sku -like '*_ZRS') ? $Pricing.disks.zrsMultiplier : 1
            return @{ Cost = ($tier.Price - $e.prices[$tier.Index]) * $mult; Note = "$($tier.Name) minus $($e.tiers[$tier.Index]) list price" }
        }
        'empty-resource-group' { return @{ Cost = 0.0; Note = 'resource groups are free' } }
        'idle-ddos-protection-plan' { return @{ Cost = $Pricing.network.ddosPlanPerHour * $Pricing.hoursPerMonth; Note = 'Network Protection plan list price' } }
        'idle-firewall' {
            $rate = $Pricing.network.firewallPerHour[$sku]
            if ($null -eq $rate) { return @{ Cost = $null; Note = "no list price for $sku" } }
            return @{ Cost = $rate * $Pricing.hoursPerMonth; Note = "$sku deployment list price; capacity units and data processed extra" }
        }
        'orphaned-vm-backup' { return @{ Cost = $null; Note = "backup storage of retained recovery points (and the protected-instance fee while protected); see the vault's Backup items and Cost analysis" } }
    }
    return @{ Cost = $null; Note = '' }
}

function Get-Action($f) {
    $who = $f.owner ? "the owner ($($f.owner))" : 'the resource group owner'
    $id = $f.id
    switch ($f.wasteType) {
        'unattached-disk' { return @(
            "Confirm with $who that the data isn't needed. If unsure, take an incremental snapshot (cheaper per GiB), then delete the disk.",
            "az disk delete --ids $id") }
        'orphaned-nic' { return @(
            "Delete the NIC if nothing will reattach it. This frees its private IP$(($f.extra -eq 'holds-public-ip') ? ' and releases its public IP association' : '').",
            "az network nic delete --ids $id") }
        'unassociated-public-ip' {
            if ($f.confidence -eq 'low') { return @('No charge. Delete to reduce clutter.', "az network public-ip delete --ids $id") }
            return @("Check DNS records and firewall or partner allowlists that reference this IP (a released static IP can't be recovered), then delete it.",
                     "az network public-ip delete --ids $id") }
        'empty-app-service-plan' {
            if ($f.confidence -eq 'low') { return @('No charge while empty. Delete to reduce clutter.', "az appservice plan delete --ids $id") }
            return @("Delete the plan if no deployment is planned. If it's being kept for upcoming work, scale it down to Free or B1 until needed.",
                     "az appservice plan delete --ids $id") }
        'vm-stopped-not-deallocated' { return @(
            "Deallocate it to stop compute billing (its disks keep billing), or delete it if it's no longer needed. Deallocating releases dynamic public IPs.",
            "az vm deallocate --ids $id") }
        'old-snapshot' {
            $pre = ($f.confidence -eq 'low') ? 'The source disk is gone or this is Azure Backup data. Confirm the data is not needed. ' : ''
            return @("${pre}Check whether a retention policy requires it. If not, delete it. If it must be kept, make sure it's incremental on Standard storage.",
                     "az snapshot delete --ids $id") }
        'idle-container-app' { return @(
            "Set minReplicas to 0 so it scales to zero when idle (the first request after idle then has a cold start), or delete the app if it's no longer needed.",
            "az containerapp update --ids $id --min-replicas 0") }
        'log-analytics-workspace' { return @(
            "Check the workspace's Usage and estimated costs page for the real GB and cost. Lower retention to the free period unless a compliance rule needs more (or move old data to the cheaper long-term/archive tier). If nobody queries the data, stop sending it (diagnostic settings, data collection rules) or delete the workspace.",
            "az monitor log-analytics workspace update --ids $id --retention-time 31") }
        'idle-storage-account' {
            if ($f.mounted) { return @(
                "Do NOT delete before confirming what uses it. A Container App in the same resource group mounts an Azure Files volume and this may be its data. If it is, it's not waste. Tag it waste-hunter:ignore=true to stop it being reported.",
                '') }
            return @("Confirm with $who that nothing reads or writes it (apps, Functions, backups, scripts) and that its data isn't needed. Then delete it, or move the data to Cool or Archive if it must be kept.",
                     "az storage account delete --ids $id") }
        'hot-blob-unread' { return @(
            "Move it to the Cool tier: change the account's default tier, or add a lifecycle rule that tiers blobs not accessed for 30 days. Cool has a 30-day minimum and higher read cost, so skip this if reads are about to start.",
            "az storage account update --ids $id --access-tier Cool") }
        'idle-container-registry' {
            if ($f.confidence -eq 'low') { return @(
                'Keep it while the referencing Container App(s) exist. They pull from it when a replica starts. If those apps are retired, delete the registry along with them.',
                '') }
            return @("Confirm with $who that no pipeline or cluster pulls from it, export any images you need, then delete it.",
                     "az acr delete --ids $id") }
        'oversized-container-registry' { return @(
            'Downgrade to Standard if you rely on none of geo-replication, private endpoints, content trust, dedicated data endpoints or connected registries.',
            "az acr update --ids $id --sku Standard") }
        'idle-openai-deployment' { return @(
            "Delete the deployment (re-create it when needed). For PTU, also check whether a reservation covers it before you rely on the saving.",
            "az cognitiveservices account deployment delete -g $($f.resourceGroup) -n $(($f.name -split '/')[0]) --deployment-name $(($f.name -split '/')[-1]) --subscription $($f.subscriptionId)") }
        'idle-load-balancer' {
            if ($f.confidence -eq 'low') { return @('No rules, so no charge. Delete it to reduce clutter.', "az network lb delete --ids $id") }
            return @("Confirm with $who that no deployment is about to add backends, then delete it and release its frontend public IPs if they aren't needed.",
                     "az network lb delete --ids $id") }
        'idle-application-gateway' { return @(
            'Stop it to end the hourly charge while keeping its configuration (start it again when backends return), or delete it if it has been retired.',
            "az network application-gateway stop --ids $id") }
        'idle-network-gateway' {
            switch ([string] $f.tier) {
                'nat' { return @('Delete it, or attach it to the subnets that need outbound access. Release its public IPs if they aren''t needed.', "az network nat gateway delete --ids $id") }
                'er-circuit' { return @('If the circuit will never be provisioned, ask the provider to deprovision it and then delete it. Billing runs from creation, not from provisioning.', "az network express-route delete --ids $id") }
                default { return @("Confirm with $who that it isn't a DR standby or waiting for a connection (re-creating a gateway takes 30-45 minutes), then delete it.", "az network vnet-gateway delete --ids $id") }
            } }
        'idle-bastion' { return @(
            'Delete it and re-create it when needed (it takes about 10 minutes), or move dev/test use to the free Developer SKU.',
            "az network bastion delete --ids $id") }
        'idle-sql-database' { return @(
            "Confirm with $who that nothing connects to it on a schedule longer than 30 days, then export a .bacpac or check backup retention and delete it. If it must stay online, move it to serverless with auto-pause.",
            "az sql db delete --ids $id") }
        'premium-disk-deallocated-vm' { return @(
            'While the VM stays deallocated, switch the disk to Standard SSD and switch it back before starting the VM. If the VM is retired, snapshot what you need and delete the VM and its disks.',
            "az disk update --ids $id --sku StandardSSD_LRS") }
        'empty-resource-group' { return @(
            'Delete it if nothing is about to be deployed there. Check for locks and role assignments others may rely on first.',
            "az group delete --name $($f.name) --subscription $($f.subscriptionId)") }
        'idle-ddos-protection-plan' { return @(
            "Confirm with $who that no virtual network is about to be linked, then delete the plan. Free DDoS infrastructure protection stays on. If only a few public IPs need DDoS protection, IP Protection per IP is usually cheaper.",
            "az network ddos-protection delete --ids $id") }
        'stopped-app-service-plan' {
            if ($f.confidence -eq 'low') { return @('No charge on this tier. Delete the stopped apps and the plan to reduce clutter.', "az appservice plan delete --ids $id") }
            return @("Confirm with $who whether the stopped apps will run again. If they're retired, delete them and then the plan. If they're parked, scale the plan down to B1 or Free while they're stopped (stopping an app doesn't reduce the bill).",
                     "az appservice plan update --ids $id --sku B1") }
        'orphaned-vm-backup' { return @(
            "Do NOT delete before confirming with ${who}: this may be the only copy of the deleted VM's data, kept on purpose. Check retention, legal hold or compliance requirements first. If it's not needed, stop protection and delete the backup data (soft delete keeps it recoverable for 14 more days).",
            "az backup protection disable --ids $id --delete-backup-data true --yes") }
        'idle-firewall' { return @(
            ('Check route tables (forced tunneling, hub routing) and any planned spokes that send traffic through it. If it is not needed, delete it, or deallocate it to keep its configuration without the hourly fee (Azure PowerShell: $fw.Deallocate(); Set-AzFirewall $fw).'),
            "az network firewall delete --ids $id") }
        'advisor-cost' { return @("Advisor suggests: $($f.extra). Review it on the Advisor Cost tab.", '') }
    }
}
