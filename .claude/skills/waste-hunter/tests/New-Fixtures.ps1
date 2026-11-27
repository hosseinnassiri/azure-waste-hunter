param([string] $Out)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force $Out | Out-Null
$T = '00000000-0000-0000-0000-00000000demo'
$P = '11111111-1111-1111-1111-111111111111'   # demo-prod
$D = '22222222-2222-2222-2222-222222222222'   # demo-dev
$now = [DateTime]::UtcNow
# Every timestamp below is absolute. The runner judges fixture data against this clock, not the
# system clock, so the committed fixtures don't drift a day each day.
Set-Content (Join-Path $Out 'clock.json') (@{ now = $now.ToString('o') } | ConvertTo-Json) -Encoding utf8
function Ago([int] $d) { $now.AddDays(-$d).ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ') }
function Rid($sub, $rg, $prov, $name) { "/subscriptions/$sub/resourceGroups/$rg/providers/$prov/$name" }
function Row($wt, $sub, $rg, $prov, $name, $loc, [hashtable] $x) {
    $r = [ordered]@{ wasteType = $wt; id = (Rid $sub $rg $prov $name); name = $name; type = $prov.ToLower(); tenantId = $T
        subscriptionId = $sub; resourceGroup = $rg.ToLower(); location = $loc; owner = ''; app = ''; env = ''
        createdTime = ''; ageDays = $null; idleDays = $null; idleSource = ''; sku = ''; tier = ''; sizeGb = $null; os = ''; extra = ''
        confidence = 'high'; reason = ''; ignored = 0 }
    foreach ($k in $x.Keys) { $r[$k] = $x[$k] }; $r
}
function Save($name, $obj) { ConvertTo-Json -InputObject @($obj) -Depth 10 | Set-Content (Join-Path $Out $name) -Encoding utf8 }

Set-Content (Join-Path $Out 'account.json') (@{ id = $P; name = 'demo-prod'; tenantId = $T; state = 'Enabled'; environmentName = 'AzureCloud' } | ConvertTo-Json) -Encoding utf8
Save 'accounts.json' @(
    @{ id = $P; name = 'demo-prod'; tenantId = $T; state = 'Enabled'; isDefault = $true },
    @{ id = $D; name = 'demo-dev';  tenantId = $T; state = 'Enabled'; isDefault = $false },
    @{ id = '33333333-3333-3333-3333-333333333333'; name = 'demo-retired'; tenantId = $T; state = 'Disabled'; isDefault = $false })
Save 'coverage-check.json' @(@{ subscriptionId = $P; name = 'demo-prod' }, @{ subscriptionId = $D; name = 'demo-dev' })

$disk = 'Microsoft.Compute/disks'
Save '01-unattached-disks.json' @(
    (Row 'unattached-disk' $P 'rg-sql-prod' $disk 'disk-sql-data-old' 'eastus' @{ owner = 'data-team@example.com'; app = 'billing-db'; env = 'prod'
        createdTime = (Ago 610); ageDays = 610; idleDays = 140; idleSource = 'LastOwnershipUpdateTime'; sku = 'Premium_LRS'; tier = 'P30'; sizeGb = 1024
        reason = 'Unattached for 140 days (LastOwnershipUpdateTime)' }),
    (Row 'unattached-disk' $D 'rg-build' $disk 'disk-temp-build' 'japaneast' @{ owner = 'ci@example.com'; env = 'dev'
        createdTime = (Ago 9); ageDays = 9; idleDays = 3; idleSource = 'LastOwnershipUpdateTime'; sku = 'StandardSSD_LRS'; tier = ''; sizeGb = 128
        confidence = 'low'; reason = 'Unattached for 3 days (LastOwnershipUpdateTime); recently detached, may be mid-redeploy' }),
    (Row 'unattached-disk' $P 'rg-dr' $disk 'asrseeddisk-web01-a1b2c3' 'westeurope' @{ app = 'web'; env = 'prod'
        createdTime = (Ago 200); ageDays = 200; idleDays = 45; idleSource = 'LastOwnershipUpdateTime'; sku = 'Premium_LRS'; tier = 'P15'; sizeGb = 256
        confidence = 'low'; reason = 'Unattached for 45 days (LastOwnershipUpdateTime); looks like an Azure Site Recovery replica/seed disk' }),
    (Row 'unattached-disk' $P 'rg-sql-prod' $disk 'disk-keep-forensics' 'eastus' @{ createdTime = (Ago 300); ageDays = 300; idleDays = 300
        sku = 'Standard_LRS'; sizeGb = 512; reason = 'Unattached for 300 days'; ignored = 1 }))

$nic = 'Microsoft.Network/networkInterfaces'
Save '02-orphaned-nics.json' @(
    (Row 'orphaned-nic' $D 'rg-legacy' $nic 'nic-vm-old01' 'eastus' @{ owner = 'platform@example.com'; env = 'dev'; idleSource = 'unknown (not exposed by Resource Graph)'
        extra = 'holds-public-ip'; reason = 'No VM, private endpoint or private link service attached; still holds a public IP (see unassociated public IPs); has an NSG association' }),
    (Row 'orphaned-nic' $P 'mc_rg-aks_aks-prod_eastus' $nic 'aks-nodepool1-nic-7' 'eastus' @{ idleSource = 'unknown (not exposed by Resource Graph)'; confidence = 'medium'
        reason = 'No VM, private endpoint or private link service attached; lives in a platform-managed resource group, check the owning service first' }))

$pip = 'Microsoft.Network/publicIPAddresses'
Save '03-unassociated-public-ips.json' @(
    (Row 'unassociated-public-ip' $D 'rg-legacy' $pip 'pip-vm-old01' 'eastus' @{ owner = 'platform@example.com'; env = 'dev'; idleSource = 'unknown (not exposed by Resource Graph)'
        sku = 'Standard'; tier = 'Regional'; extra = 'Static'; reason = 'Associated only with an orphaned NIC (no VM) (Standard / Static)' }),
    (Row 'unassociated-public-ip' $P 'rg-web' $pip 'pip-old-lb-frontend' 'brazilsouth' @{ app = 'web'; env = 'prod'; idleSource = 'unknown (not exposed by Resource Graph)'
        sku = 'Standard'; tier = 'Regional'; extra = 'Static'; reason = 'Not associated with any resource (Standard / Static); has a DNS label, releasing it frees the FQDN' }),
    (Row 'unassociated-public-ip' $D 'rg-sandbox' $pip 'pip-test-dyn' 'centralindia' @{ idleSource = 'unknown (not exposed by Resource Graph)'
        sku = 'Basic'; tier = 'Regional'; extra = 'Dynamic'; confidence = 'low'; reason = 'Not associated with any resource (Basic / Dynamic); Basic dynamic and unassociated, so no charge, clutter only' }))

$asp = 'Microsoft.Web/serverFarms'
Save '04-empty-app-service-plans.json' @(
    (Row 'empty-app-service-plan' $P 'rg-api' $asp 'asp-legacy-api' 'eastus' @{ owner = 'api-team@example.com'; app = 'orders-api'; env = 'prod'
        idleSource = 'unknown (not exposed by Resource Graph)'; sku = 'P1v3'; tier = 'PremiumV3'; sizeGb = 2; os = 'Linux'; extra = 'linux'
        reason = 'Plan hosts 0 apps (PremiumV3 P1v3 x2 instance(s))' }),
    (Row 'empty-app-service-plan' $D 'rg-sandbox' $asp 'asp-playground' 'centralus' @{ idleSource = 'unknown (not exposed by Resource Graph)'
        sku = 'F1'; tier = 'Free'; sizeGb = 1; os = 'Windows'; extra = 'app'; confidence = 'low'; reason = 'Plan hosts 0 apps (Free F1 x1 instance(s)); free/consumption tier, no charge while empty' }),
    (Row 'empty-app-service-plan' $P 'rg-reports' $asp 'asp-reports-weu' 'westeurope' @{ owner = 'bi-team@example.com'; app = 'reports'; env = 'prod'
        idleSource = 'unknown (not exposed by Resource Graph)'; sku = 'S1'; tier = 'Standard'; sizeGb = 1; os = 'Windows'; extra = 'app'
        reason = 'Plan hosts 0 apps (Standard S1 x1 instance(s))' }))

$vm = 'Microsoft.Compute/virtualMachines'
$vmBuild = Rid $D 'rg-build' $vm 'vm-build-agent-02'
$vmJump  = Rid $P 'rg-ops' $vm 'vm-win-jumpbox'
Save '05-vms-stopped-not-deallocated.json' @(
    (Row 'vm-stopped-not-deallocated' $D 'rg-build' $vm 'vm-build-agent-02' 'eastus' @{ owner = 'ci@example.com'; app = 'build'; env = 'dev'
        createdTime = (Ago 420); ageDays = 420; idleSource = 'pending (CPU metrics)'; sku = 'Standard_D8s_v5'; tier = 'Regular'; os = 'Linux'
        reason = 'Power state is Stopped (not deallocated), so compute is still billed' }),
    (Row 'vm-stopped-not-deallocated' $P 'rg-ops' $vm 'vm-win-jumpbox' 'canadacentral' @{ owner = 'ops@example.com'; env = 'prod'
        createdTime = (Ago 800); ageDays = 800; idleSource = 'pending (CPU metrics)'; sku = 'Standard_B2ms'; tier = 'Regular'; os = 'Windows'; extra = ''
        reason = 'Power state is Stopped (not deallocated), so compute is still billed' }))

$snap = 'Microsoft.Compute/snapshots'
Save '06-old-snapshots.json' @(
    (Row 'old-snapshot' $P 'rg-sql-prod' $snap 'snap-sql-pre-upgrade-2025' 'australiaeast' @{ owner = 'data-team@example.com'; app = 'billing-db'; env = 'prod'
        createdTime = (Ago 412); ageDays = 412; idleDays = 412; idleSource = 'timeCreated'; sku = 'Standard_LRS'; tier = 'full'; sizeGb = 1024
        reason = 'Snapshot is 412 days old (full); source disk still exists' }),
    (Row 'old-snapshot' $D 'rg-legacy' $snap 'snap-vm-old01-osdisk' 'uksouth' @{ env = 'dev'
        createdTime = (Ago 150); ageDays = 150; idleDays = 150; idleSource = 'timeCreated'; sku = 'Standard_LRS'; tier = 'incremental'; sizeGb = 128
        confidence = 'low'; reason = 'Snapshot is 150 days old (incremental); source disk was deleted, may be the only copy' }))

function Adv($sub, $rg, $impactedId, $name, $type, $impact, $problem, $solution, $savings, [int] $ign = 0) {
    [ordered]@{ wasteType = 'advisor-cost'; id = $impactedId.ToLower(); recommendationId = "$impactedId/providers/Microsoft.Advisor/recommendations/$([guid]::NewGuid())"
        name = $name; type = $type; tenantId = $T; subscriptionId = $sub; resourceGroup = $rg; location = 'eastus'; owner = ''; app = ''; env = ''
        createdTime = ''; ageDays = $null; idleDays = $null; idleSource = "Advisor last updated $(Ago 2)"; sku = 'rec-type-id'; tier = $impact; sizeGb = $null; os = ''
        extra = $solution; monthlySavings = $savings; currency = 'USD'
        confidence = @{ High = 'high'; Medium = 'medium'; Low = 'low' }[$impact]; reason = "Advisor ($impact impact): $problem"; ignored = $ign }
}
Save '07-advisor-cost.json' @(
    (Adv $P 'rg-api' (Rid $P 'rg-api' $asp 'asp-legacy-api') 'asp-legacy-api' 'microsoft.web/serverfarms' 'Medium' 'Unused or empty App Service plan' 'Delete the empty App Service plan' 248.2),
    (Adv $P 'rg-api' (Rid $P 'rg-api' $vm 'vm-api-01') 'vm-api-01' 'microsoft.compute/virtualmachines' 'High' 'Right-size or shutdown underutilized virtual machines' 'Resize Standard_D16s_v5 to Standard_D8s_v5' 280.32),
    (Adv $P '' "/subscriptions/$P" 'demo-prod' 'subscriptions' 'Medium' 'Consider virtual machine reserved instance to save over your on-demand costs' 'Buy a 1-year Dsv5 reservation (East US)' 96.5),
    (Adv $D 'rg-ml' (Rid $D 'rg-ml' $vm 'vm-gpu-train') 'vm-gpu-train' 'microsoft.compute/virtualmachines' 'High' 'Right-size or shutdown underutilized virtual machines' 'Shut down vm-gpu-train' 1520.0 1))

# ---- Metric-confirmed types (queries 08-12): each has cases that must be flagged AND cases that must be dropped
$metrics = [ordered]@{}
# A metrics response: one value per metric; each series is @{ split = '<dim value>' or $null; total = n } or @{ average = n }
function Set-Metric([string] $id, [string] $metric, [string] $agg, [object[]] $series) {
    $ts = foreach ($s in $series) {
        $mv = $s.split ? @(@{ name = @{ value = 'ModelDeploymentName' }; value = $s.split }) : @()
        @{ metadatavalues = $mv; data = @(@{ timeStamp = $now.AddDays(-1).ToString('yyyy-MM-ddT00:00:00Z'); $agg = $s.value }) }
    }
    $script:metrics["$($id.ToLower())|$($metric.ToLower())"] = @{ value = @(@{ name = @{ value = $metric }; timeseries = @($ts) }) }
}
function Set-Metrics([string] $id, [hashtable] $totals) {   # several Total metrics in one call, keyed by the first name
    $vals = foreach ($k in $totals.Keys) { @{ name = @{ value = $k }; timeseries = @(@{ metadatavalues = @(); data = @(@{ timeStamp = $now.AddDays(-1).ToString('yyyy-MM-ddT00:00:00Z'); total = $totals[$k] }) }) } }
    return @{ value = @($vals) }
}

$ca = 'Microsoft.App/containerApps'
function CA($sub, $rg, $name, $loc, [int] $min, [double] $cpu, [string] $mem, [bool] $ingress, [string] $transport, [hashtable] $x = @{}) {
    $r = Row 'idle-container-app' $sub $rg $ca $name $loc (@{ sku = 'Consumption'; tier = "minReplicas $min"; sizeGb = $min; extra = $transport; confidence = 'pending'; idleSource = 'pending (metrics)' } + $x)
    $r.checkInputs = [ordered]@{ minReplicas = $min; cpu = $cpu; memory = @($mem); transport = $transport; hasIngress = $ingress; workloadProfile = 'Consumption' }
    $r
}
$caIdle = CA $P 'rg-orders' 'ca-orders-legacy' 'northeurope' 2 1.0 '2Gi' $true 'Auto' @{ owner = 'orders@example.com'; app = 'orders'; env = 'prod' }
$caBusy = CA $D 'rg-api' 'ca-api-busy' 'eastus' 1 0.5 '1Gi' $true 'Auto'
$caWork = CA $D 'rg-jobs' 'ca-queue-worker' 'westeurope' 1 0.25 '512Mi' $false '' @{ env = 'dev' }
Save '08-idle-container-apps.json' @($caIdle, $caBusy, $caWork)
$metrics["$($caIdle.id.ToLower())|requests"] = Set-Metrics $caIdle.id ([ordered]@{ Requests = 0; RxBytes = 3MB; TxBytes = 2MB })
$metrics["$($caBusy.id.ToLower())|requests"] = Set-Metrics $caBusy.id ([ordered]@{ Requests = 120000; RxBytes = 900MB; TxBytes = 4GB })
$metrics["$($caWork.id.ToLower())|requests"] = Set-Metrics $caWork.id ([ordered]@{ Requests = 0; RxBytes = 1MB; TxBytes = 1MB })

$law = 'Microsoft.OperationalInsights/workspaces'
function LAW($sub, $rg, $name, [int] $ret, [hashtable] $x = @{}) {
    $r = Row 'log-analytics-workspace' $sub $rg $law $name 'eastus' (@{ sku = 'PerGB2018'; tier = "retention ${ret}d"; sizeGb = $ret; createdTime = (Ago 400); ageDays = 400; confidence = 'pending'; idleSource = 'pending (metrics)' } + $x)
    $r.checkInputs = [ordered]@{ retention = $ret; freeRetention = 31; sentinel = $false; capacityReservation = $null }
    $r
}
$lawOld = LAW $P 'rg-security' 'log-security-archive' 365 @{ owner = 'secops@example.com'; env = 'prod' }
$lawOk  = LAW $P 'rg-monitoring' 'log-app-prod' 30
Save '09-log-analytics-workspaces.json' @($lawOld, $lawOk)
$metrics["$($lawOld.id.ToLower())|ingestion volume"] = @{ value = @(
    @{ name = @{ value = 'Ingestion Volume' }; timeseries = @(@{ metadatavalues = @(); data = @(@{ count = 2400000 }) }) },
    @{ name = @{ value = 'Query Count' }; timeseries = @(@{ metadatavalues = @(); data = @(@{ count = $null }) }) }) }
$metrics["$($lawOk.id.ToLower())|ingestion volume"] = @{ value = @(
    @{ name = @{ value = 'Ingestion Volume' }; timeseries = @(@{ metadatavalues = @(); data = @(@{ count = 5000000 }) }) },
    @{ name = @{ value = 'Query Count' }; timeseries = @(@{ metadatavalues = @(); data = @(@{ count = 3100 }) }) }) }

$st = 'Microsoft.Storage/storageAccounts'
function STA($sub, $rg, $name, $loc, $sku, $tier, [object[]] $mounts, [hashtable] $x = @{}) {
    $r = Row 'idle-storage-account' $sub $rg $st $name $loc (@{ sku = $sku; tier = $tier; extra = 'StorageV2'; createdTime = (Ago 500); ageDays = 500; confidence = 'pending'; idleSource = 'pending (metrics)' } + $x)
    $r.checkInputs = [ordered]@{ accessTier = $tier; kind = 'StorageV2'; isHns = $false; fileMountApps = $mounts }
    $r
}
$stIdle  = STA $D 'rg-legacy' 'stlegacyexports' 'eastus' 'Standard_GRS' 'Hot' @() @{ owner = 'platform@example.com'; env = 'dev' }
$stHot   = STA $P 'rg-media' 'stmediaarchive' 'westeurope' 'Standard_LRS' 'Hot' @() @{ app = 'media'; env = 'prod' }
$stNeo   = STA $P 'rg-graph' 'stgraphdata' 'canadacentral' 'Standard_LRS' 'Hot' @(@{ rg = 'rg-graph'; name = 'ca-graphdb' }) @{ app = 'graph'; env = 'prod' }
$stBusy  = STA $P 'rg-web' 'stwebassets' 'eastus' 'Standard_LRS' 'Hot' @()
$stIgn   = STA $D 'rg-legacy' 'stkeepforaudit' 'eastus' 'Standard_LRS' 'Cool' @() @{ ignored = 1 }
Save '10-idle-storage-accounts.json' @($stIdle, $stHot, $stNeo, $stBusy, $stIgn)
foreach ($pair in @(@($stIdle, 0, 250GB), @($stHot, 52000, 2.1TB), @($stNeo, 0, 20GB), @($stBusy, 880000, 40GB))) {
    Set-Metric $pair[0].id 'Transactions' 'total' @(@{ value = $pair[1] })
    Set-Metric $pair[0].id 'UsedCapacity' 'average' @(@{ value = $pair[2] })
}
Set-Metric "$($stHot.id)/blobServices/default" 'BlobCapacity' 'average' @(@{ value = 2TB })
Set-Metric "$($stHot.id)/blobServices/default" 'Transactions' 'total' @()          # 0 GetBlob reads: no series
Set-Metric "$($stBusy.id)/blobServices/default" 'BlobCapacity' 'average' @(@{ value = 30GB })

$acr = 'Microsoft.ContainerRegistry/registries'
function ACR($sub, $rg, $name, $loc, $sku, [string[]] $refs, [int] $repl, [hashtable] $x = @{}) {
    $r = Row 'idle-container-registry' $sub $rg $acr $name $loc (@{ sku = $sku; tier = $sku; extra = "$name.azurecr.io"; createdTime = (Ago 300); ageDays = 300; confidence = 'pending'; idleSource = 'pending (metrics)' } + $x)
    $r.checkInputs = [ordered]@{ referencedBy = @($refs); replications = $repl; privateEndpoints = 0 }
    $r
}
$crIdle = ACR $D 'rg-build' 'crlegacybuild' 'eastus' 'Premium' @() 1 @{ owner = 'ci@example.com'; env = 'dev' }
$crBig  = ACR $P 'rg-platform' 'crplatform' 'eastus' 'Premium' @() 0 @{ owner = 'platform@example.com'; env = 'prod' }
$crRef  = ACR $P 'rg-graph' 'crgraphapps' 'canadacentral' 'Basic' @('ca-graphdb') 0
Save '11-container-registries.json' @($crIdle, $crBig, $crRef)
foreach ($pair in @(@($crIdle, 0, 300GB), @($crBig, 9100, 40GB), @($crRef, 0, 3GB))) {
    Set-Metric $pair[0].id 'TotalPullCount' 'total' @(@{ value = $pair[1] })
    Set-Metric $pair[0].id 'StorageUsed' 'average' @(@{ value = $pair[2] })
}

$oai = 'Microsoft.CognitiveServices/accounts'
$oaiRow = Row 'idle-openai-deployment' $D 'rg-ml' $oai 'oai-research' 'eastus' @{ sku = 'S0'; extra = 'OpenAI'; owner = 'ml@example.com'; app = 'research'; env = 'dev'; confidence = 'pending'; idleSource = 'pending (deployments + metrics)' }
$oaiRow.checkInputs = [ordered]@{ kind = 'OpenAI' }
Save '12-openai-accounts.json' @($oaiRow)
function Dep($name, $sku, [int] $cap, $model, [int] $ageD) { @{ name = $name; sku = @{ name = $sku; capacity = $cap }; properties = @{ model = @{ name = $model; format = 'OpenAI' } }; systemData = @{ createdAt = (Ago $ageD) } } }
@{ 'rg-ml/oai-research' = @(
    (Dep 'gpt-ptu-eval' 'GlobalProvisionedManaged' 15 'gpt-4o' 120),
    (Dep 'gpt-4o-mini-support-ft' 'Standard' 1 'gpt-4o-mini-2024-07-18.ft-3f9a2c' 90),
    (Dep 'gpt-4o-chat' 'GlobalStandard' 50 'gpt-4o' 200),
    (Dep 'gpt-ptu-prod' 'ProvisionedManaged' 100 'gpt-4o' 300)) } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $Out 'deployments.json') -Encoding utf8
Set-Metric $oaiRow.id 'AzureOpenAIRequests' 'total' @(@{ split = 'gpt-ptu-prod'; value = 910000 }, @{ split = 'gpt-4o-chat'; value = 45000 })

# ---- Phase 3: networking, Bastion, SQL, premium disks on deallocated VMs, empty resource groups
$unk = @{ idleSource = 'unknown (not exposed by Resource Graph)' }
$lbT = 'Microsoft.Network/loadBalancers'
Save '13-idle-load-balancers.json' @(
    (Row 'idle-load-balancer' $P 'rg-web' $lbT 'lb-old-web' 'eastus' (@{ owner = 'web@example.com'; env = 'prod'; sku = 'Standard'; tier = 'Regional'; sizeGb = 3; extra = '1'
        reason = 'No backend pool members and no inbound NAT rule targets (Standard, 3 rule(s), 1 frontend(s)); its frontend public IPs also keep billing' } + $unk)),
    (Row 'idle-load-balancer' $D 'rg-sandbox' $lbT 'lb-empty-scratch' 'eastus' (@{ sku = 'Standard'; tier = 'Regional'; sizeGb = 0; extra = '0'; confidence = 'low'
        reason = 'No backend pool members and no inbound NAT rule targets (Standard, 0 rule(s), 0 frontend(s)); no rules, so the load balancer itself is free (clutter only)' } + $unk)))
Save '14-idle-application-gateways.json' @(
    (Row 'idle-application-gateway' $P 'rg-web' 'Microsoft.Network/applicationGateways' 'agw-legacy-portal' 'westeurope' (@{ owner = 'web@example.com'; env = 'prod'
        sku = 'WAF_v2'; tier = 'WAF_v2'; sizeGb = 2; extra = 'Running'; reason = 'Every backend pool is empty (WAF_v2, min capacity 2)' } + $unk)))
Save '15-idle-network-gateways.json' @(
    (Row 'idle-network-gateway' $D 'rg-net-dev' 'Microsoft.Network/natGateways' 'nat-dev-unused' 'eastus' (@{ env = 'dev'; sku = 'Standard'; tier = 'nat'; sizeGb = 0
        reason = 'NAT gateway is attached to no subnet; its public IPs keep billing too' } + $unk)),
    (Row 'idle-network-gateway' $P 'rg-net' 'Microsoft.Network/virtualNetworkGateways' 'vpngw-old-branch' 'eastus' (@{ owner = 'netops@example.com'; env = 'prod'; sku = 'VpnGw2'; tier = 'vpn-gateway'; sizeGb = 0
        confidence = 'medium'; reason = 'VPN gateway (VpnGw2) has no site-to-site or VNet-to-VNet connections and no point-to-site configuration' } + $unk)),
    (Row 'idle-network-gateway' $P 'rg-net' 'Microsoft.Network/expressRouteCircuits' 'erc-pending-dc2' 'eastus' (@{ owner = 'netops@example.com'; sku = 'Standard_MeteredData'; tier = 'er-circuit'; sizeGb = 0; extra = '1000 Mbps'
        reason = 'ExpressRoute circuit (Standard_MeteredData) is billed but the provider state is NotProvisioned' } + $unk)))

$basT = 'Microsoft.Network/bastionHosts'
$basDev  = Row 'idle-bastion' $D 'rg-net-dev' $basT 'bas-dev' 'eastus' @{ env = 'dev'; sku = 'Standard'; sizeGb = 2; confidence = 'pending'; idleSource = 'pending (metrics)' }
$basProd = Row 'idle-bastion' $P 'rg-net' $basT 'bas-prod' 'eastus' @{ env = 'prod'; sku = 'Basic'; sizeGb = 2; confidence = 'pending'; idleSource = 'pending (metrics)' }
foreach ($b in $basDev, $basProd) { $b.checkInputs = [ordered]@{ scaleUnits = 2 } }
Save '16-idle-bastion-hosts.json' @($basDev, $basProd)
Set-Metric $basDev.id 'sessions' 'total' @()                          # 0 sessions: no series
Set-Metric $basProd.id 'sessions' 'total' @(@{ value = 40 })

$sqlT = 'Microsoft.Sql/servers/databases'
function SQLDB($sub, $rg, $server, $db, $sku, $tierName, [int] $vc, [hashtable] $x = @{}) {
    $r = Row 'idle-sql-database' $sub $rg 'Microsoft.Sql/servers' "$server/databases/$db" 'eastus' (@{ sku = $sku; tier = $tierName; sizeGb = $vc; createdTime = (Ago 400); ageDays = 400; confidence = 'pending'; idleSource = 'pending (metrics)' } + $x)
    $r.name = "$server/$db"; $r.type = 'microsoft.sql/servers/databases'
    $r.checkInputs = [ordered]@{ vcores = $vc; tier = $tierName }
    $r
}
$sqlIdle = SQLDB $P 'rg-data' 'sql-legacy' 'reporting-old' 'S3' 'Standard' 100 @{ owner = 'data-team@example.com'; app = 'reporting'; env = 'prod' }
$sqlBusy = SQLDB $P 'rg-data' 'sql-app' 'orders' 'GP_Gen5' 'GeneralPurpose' 2
Save '17-idle-sql-databases.json' @($sqlIdle, $sqlBusy)
Set-Metric $sqlIdle.id 'connection_successful' 'total' @()
Set-Metric $sqlBusy.id 'connection_successful' 'total' @(@{ value = 5200 })

$vmRetired = Rid $D 'rg-legacy' $vm 'vm-retired-app'
$vmWeekend = Rid $D 'rg-build' $vm 'vm-weekend-batch'
function PDisk($name, $vmIdArg, $tierName, [int] $gb) {
    $r = Row 'premium-disk-deallocated-vm' $D (($vmIdArg -split '/')[4]) $disk $name 'eastus' @{ env = 'dev'; sku = 'Premium_LRS'; tier = $tierName; sizeGb = $gb; os = 'Linux'; extra = $vmIdArg
        createdTime = (Ago 500); ageDays = 500; confidence = 'pending'; idleSource = 'pending (VM CPU metrics)' }
    $r.checkInputs = [ordered]@{ vmId = $vmIdArg }
    $r
}
Save '18-premium-disks-on-deallocated-vms.json' @((PDisk 'vm-retired-app_OsDisk' $vmRetired 'P30' 1024), (PDisk 'vm-weekend-batch_data' $vmWeekend 'P10' 128))
# vm-retired-app: no CPU data at all (90+ days off). vm-weekend-batch: ran 10 days ago, so dropped.
$metrics[$vmWeekend.ToLower()] = @{ value = @(@{ timeseries = @(@{ data = @(@{ timeStamp = $now.AddDays(-10).ToString('yyyy-MM-ddT00:00:00Z'); maximum = 61.0 }) }) }) }

$rgRow = Row 'empty-resource-group' $D 'rg-old-poc' 'x' 'x' 'eastus' (@{ env = 'dev'; confidence = 'medium'; reason = 'Resource group contains no resources indexed by Resource Graph' } + $unk)
$rgRow.id = "/subscriptions/$D/resourceGroups/rg-old-poc"; $rgRow.name = 'rg-old-poc'; $rgRow.type = 'microsoft.resources/subscriptions/resourcegroups'
Save '19-empty-resource-groups.json' @($rgRow)

# ---- Phase 4: DDoS plans, all-stopped App Service plans, backups of deleted VMs, idle firewalls
Save '20-idle-ddos-protection-plans.json' @(
    (Row 'idle-ddos-protection-plan' $P 'rg-net' 'Microsoft.Network/ddosProtectionPlans' 'ddos-legacy-plan' 'eastus' (@{ owner = 'netops@example.com'; env = 'prod'
        sku = 'Network Protection'; sizeGb = 0; reason = 'DDoS Network Protection plan protects no virtual networks or public IPs, but bills its fixed monthly fee' } + $unk)))
Save '21-app-service-plans-all-apps-stopped.json' @(
    (Row 'stopped-app-service-plan' $P 'rg-intranet' $asp 'asp-intranet-old' 'eastus' (@{ owner = 'web@example.com'; app = 'intranet'; env = 'prod'
        sku = 'P1v3'; tier = 'PremiumV3'; sizeGb = 1; os = 'Windows'; extra = '2'
        reason = 'All 2 app(s) on this plan are stopped (app-intranet, app-intranet-api), but the plan bills per instance (PremiumV3 P1v3 x1)' } + $unk)),
    (Row 'stopped-app-service-plan' $D 'rg-sandbox' $asp 'asp-free-stopped' 'eastus' (@{ sku = 'F1'; tier = 'Free'; sizeGb = 1; os = 'Linux'; extra = '1'; confidence = 'low'
        reason = 'All 1 app(s) on this plan are stopped (app-demo), but the plan bills per instance (Free F1 x1); free/consumption tier, no charge' } + $unk)))
$bkName = 'rsv-dev/backupFabrics/Azure/protectionContainers/IaasVMContainer;iaasvmcontainerv2;rg-legacy;vm-old01/protectedItems/VM;iaasvmcontainerv2;rg-legacy;vm-old01'
$bk = Row 'orphaned-vm-backup' $D 'rg-backup' 'Microsoft.RecoveryServices/vaults' $bkName 'eastus' @{ owner = 'platform@example.com'; env = 'dev'
    idleSource = "last backup $(Ago 75)"; sku = 'VM'; tier = 'ProtectionStopped'; extra = (Rid $D 'rg-legacy' $vm 'vm-old01').ToLower(); confidence = 'low'
    reason = 'Backups of VM vm-old01, which no longer exists (protection state ProtectionStopped). Retained recovery points keep billing backup storage' }
$bk.name = 'rsv-dev/vm-old01'; $bk.type = 'microsoft.recoveryservices/vaults/backupfabrics/protectioncontainers/protecteditems'
# A SQL Server database that ran on vm-old01, backed up as a workload item
$bkDbName = 'rsv-dev/backupFabrics/Azure/protectionContainers/VMAppContainer;compute;rg-legacy;vm-old01/protectedItems/SQLDataBase;mssqlserver;billing'
$bkDb = Row 'orphaned-workload-backup' $D 'rg-backup' 'Microsoft.RecoveryServices/vaults' $bkDbName 'eastus' @{ owner = 'platform@example.com'; env = 'dev'
    idleSource = "last backup $(Ago 75)"; sku = 'SQLDataBase'; tier = 'ProtectionStopped'; extra = (Rid $D 'rg-legacy' $vm 'vm-old01').ToLower(); confidence = 'low'
    reason = 'Backups of SQL Server database billing from VM vm-old01, which no longer exists (protection state ProtectionStopped). Retained recovery points keep billing backup storage' }
$bkDb.name = 'rsv-dev/vm-old01/billing'; $bkDb.type = 'microsoft.recoveryservices/vaults/backupfabrics/protectioncontainers/protecteditems'
Save '22-orphaned-vm-backups.json' @($bk, $bkDb)
$fwT = 'Microsoft.Network/azureFirewalls'
function FwRow($sub, $rg, $name, $tierName, [bool] $hub, [hashtable] $x = @{}) {
    $r = Row 'idle-firewall' $sub $rg $fwT $name 'eastus' (@{ sku = $tierName; tier = ($hub ? 'hub' : 'vnet'); confidence = 'pending'; idleSource = 'pending (metrics)' } + $x)
    $r.checkInputs = [ordered]@{ tier = $tierName; hub = $hub }
    $r
}
$fwIdle = FwRow $P 'rg-net' 'fw-hub-legacy' 'Premium' $false @{ owner = 'netops@example.com'; env = 'prod' }
$fwDnat = FwRow $D 'rg-net-dev' 'fw-dev-dnat' 'Standard' $false @{ env = 'dev' }
$fwBusy = FwRow $P 'rg-net' 'fw-prod-egress' 'Standard' $false @{ owner = 'netops@example.com'; env = 'prod' }
Save '23-idle-firewalls.json' @($fwIdle, $fwDnat, $fwBusy)
$metrics["$($fwIdle.id.ToLower())|dataprocessed"] = Set-Metrics $fwIdle.id ([ordered]@{ DataProcessed = 0; ApplicationRuleHit = 0; NetworkRuleHit = 0 })
$metrics["$($fwDnat.id.ToLower())|dataprocessed"] = Set-Metrics $fwDnat.id ([ordered]@{ DataProcessed = 300MB; ApplicationRuleHit = 0; NetworkRuleHit = 0 })   # flagged, medium
$metrics["$($fwBusy.id.ToLower())|dataprocessed"] = Set-Metrics $fwBusy.id ([ordered]@{ DataProcessed = 800GB; ApplicationRuleHit = 1200000; NetworkRuleHit = 54000 })   # dropped

# Full snapshots that could be incremental (rows as query 38 returns them; the newest of a series and
# old snapshots are filtered in KQL)
Save '38-full-snapshots.json' @(
    (Row 'full-snapshot' $P 'rg-sql-prod' $snap 'snap-sql-daily-premium' 'eastus' @{ owner = 'data-team@example.com'; app = 'billing-db'; env = 'prod'
        createdTime = (Ago 20); ageDays = 20; idleSource = 'timeCreated'; sku = 'Premium_LRS'; tier = 'premium'; sizeGb = 512; extra = (Rid $P 'rg-sql-prod' $disk 'disk-sql-data').ToLower()
        confidence = 'medium'; reason = 'Full snapshot on Premium storage (Premium_LRS). An incremental snapshot is stored at the Standard rate and holds only changed data' }),
    (Row 'full-snapshot' $D 'rg-build' $snap 'snap-build-weekly-03' 'eastus' @{ env = 'dev'
        createdTime = (Ago 40); ageDays = 40; idleSource = 'timeCreated'; sku = 'Standard_LRS'; tier = 'series'; sizeGb = 256; extra = (Rid $D 'rg-build' $disk 'disk-build-cache').ToLower()
        confidence = 'low'; reason = 'One of 4 full snapshots of the same disk in 90 days. As incremental snapshots, all but the newest would store only what changed' }))

# ---- Phase 5: Cosmos DB, data platforms, Redis, messaging, API Management, ML clusters, private
# endpoints, IP prefixes, edge profiles, non-prod VMs, reservations, Hybrid Benefit, geo-redundant
# non-prod storage, oversized VMs. Each candidate type has cases it must flag and cases it must drop.
# An hourly time series: dims = @('DimName', 'value', ...), one datapoint per value, ending at $now
function Ts([object[]] $dims, [string] $agg, [double[]] $values) {
    $mv = @(for ($i = 0; $i -lt $dims.Count; $i += 2) { @{ name = @{ value = $dims[$i] }; value = $dims[$i + 1] } })
    $start = $now.AddHours(-$values.Count)
    @{ metadatavalues = $mv; data = @(for ($i = 0; $i -lt $values.Count; $i++) { @{ timeStamp = $start.AddHours($i).ToString('yyyy-MM-ddTHH:00:00Z'); $agg = $values[$i] } }) }
}
function MetricResp([System.Collections.IDictionary] $byMetric) { @{ value = @(foreach ($k in $byMetric.Keys) { @{ name = @{ value = $k }; timeseries = @($byMetric[$k]) } }) } }
function Hours([int] $n, [double] $lo, [double] $hi) { @(for ($i = 0; $i -lt $n; $i++) { $lo + ($hi - $lo) * (($i * 7) % 20) / 19 }) }
function Cand($wt, $sub, $rg, $prov, $name, $loc, [hashtable] $x, [System.Collections.IDictionary] $ci) {
    $h = @{ confidence = 'pending'; idleSource = 'pending (metrics)' }; foreach ($k in $x.Keys) { $h[$k] = $x[$k] }
    $r = Row $wt $sub $rg $prov $name $loc $h
    $r.checkInputs = $ci
    $r
}

$cdb = 'Microsoft.DocumentDB/databaseAccounts'
$cosOld  = Cand 'overprovisioned-cosmos-db' $P 'rg-orders' $cdb 'cosmos-orders-legacy' 'eastus' @{ owner = 'orders@example.com'; app = 'orders'; env = 'prod'; sku = 'Standard'; tier = 'GlobalDocumentDB'; sizeGb = 1 } ([ordered]@{ regions = 1; freeTier = $false; multiWrite = $false })
$cosDev  = Cand 'overprovisioned-cosmos-db' $D 'rg-api' $cdb 'cosmos-dev-idle' 'eastus' @{ env = 'dev'; sku = 'Standard'; tier = 'GlobalDocumentDB'; sizeGb = 2 } ([ordered]@{ regions = 2; freeTier = $false; multiWrite = $false })
$cosBusy = Cand 'overprovisioned-cosmos-db' $P 'rg-api' $cdb 'cosmos-busy' 'eastus' @{ sku = 'Standard'; sizeGb = 1 } ([ordered]@{ regions = 1; freeTier = $false; multiWrite = $false })
$cosFree = Cand 'overprovisioned-cosmos-db' $D 'rg-sandbox' $cdb 'cosmos-free' 'eastus' @{ sku = 'Standard'; sizeGb = 1; extra = 'free tier' } ([ordered]@{ regions = 1; freeTier = $true; multiWrite = $false })
Save '24-overprovisioned-cosmos-db.json' @($cosOld, $cosDev, $cosBusy, $cosFree)
$tpKey = { param($r) "$($r.id.ToLower())|provisionedthroughput" }; $nruKey = { param($r) "$($r.id.ToLower())|normalizedruconsumption" }
$metrics[(& $tpKey $cosOld)]  = MetricResp ([ordered]@{ ProvisionedThroughput = @((Ts @('DatabaseName', 'orders', 'CollectionName', 'items') 'maximum' @(2000)), (Ts @('DatabaseName', 'orders', 'CollectionName', 'history') 'maximum' @(2000))) })
$metrics[(& $nruKey $cosOld)] = MetricResp ([ordered]@{ NormalizedRUConsumption = @(Ts @() 'maximum' @(1, 3, 2)) })     # peak 3%: flagged, medium
$metrics[(& $tpKey $cosDev)]  = MetricResp ([ordered]@{ ProvisionedThroughput = @(Ts @('DatabaseName', 'app', 'CollectionName', '__Empty') 'maximum' @(1000)) })
$metrics[(& $nruKey $cosDev)] = MetricResp ([ordered]@{ NormalizedRUConsumption = @(Ts @() 'maximum' @(0, 0)) })          # nothing consumed: flagged, high
$metrics[(& $tpKey $cosBusy)] = MetricResp ([ordered]@{ ProvisionedThroughput = @(Ts @('DatabaseName', 'api', 'CollectionName', 'events') 'maximum' @(10000)) })
$metrics[(& $nruKey $cosBusy)] = MetricResp ([ordered]@{ NormalizedRUConsumption = @(Ts @() 'maximum' @(40, 65)) })       # dropped
$metrics[(& $tpKey $cosFree)] = MetricResp ([ordered]@{ ProvisionedThroughput = @(Ts @('DatabaseName', 'try', 'CollectionName', 'c') 'maximum' @(1000)) })
$metrics[(& $nruKey $cosFree)] = MetricResp ([ordered]@{ NormalizedRUConsumption = @(Ts @() 'maximum' @(0)) })            # all within the free 1000 RU/s: dropped

$fab = Cand 'idle-data-platform' $P 'rg-bi' 'Microsoft.Fabric/capacities' 'fab-analytics' 'eastus' @{ owner = 'bi-team@example.com'; env = 'prod'; sku = 'F64'; tier = 'fabric'; sizeGb = $null; extra = 'Active' } ([ordered]@{ platform = 'fabric'; instances = $null })
function SynPool($name, [hashtable] $x) {
    $r = Cand 'idle-data-platform' $P 'rg-data' 'Microsoft.Synapse/workspaces' "syn-ws/sqlPools/$name" 'eastus' (@{ sku = 'DW500c'; tier = 'synapse'; extra = 'Online'; createdTime = (Ago 300); ageDays = 300 } + $x) ([ordered]@{ platform = 'synapse'; instances = $null })
    $r.name = "syn-ws/$name"; $r.type = 'microsoft.synapse/workspaces/sqlpools'; $r
}
$synIdle = SynPool 'dw-legacy' @{ owner = 'data-team@example.com'; env = 'prod' }
$synBusy = SynPool 'dw-prod' @{}
$adx     = Cand 'idle-data-platform' $D 'rg-telemetry' 'Microsoft.Kusto/clusters' 'adx-telemetry' 'eastus' @{ env = 'dev'; sku = 'Standard_E8ads_v5'; tier = 'kusto'; sizeGb = 2; extra = 'Running' } ([ordered]@{ platform = 'kusto'; instances = 2 })
$adxBusy = Cand 'idle-data-platform' $P 'rg-telemetry' 'Microsoft.Kusto/clusters' 'adx-busy' 'eastus' @{ sku = 'Standard_E8ads_v5'; tier = 'kusto'; sizeGb = 2; extra = 'Running' } ([ordered]@{ platform = 'kusto'; instances = 2 })
# Power BI Embedded: pbi-reports idle (0% CPU), pbi-portal busy (dropped), pbi-legacy no CPU data (Gen1: low)
$pbiT = 'Microsoft.PowerBIDedicated/capacities'
function Pbi($name, $sku, [hashtable] $x = @{}) { Cand 'idle-data-platform' $P 'rg-bi' $pbiT $name 'eastus' (@{ sku = $sku; tier = 'powerbi'; extra = 'Succeeded' } + $x) ([ordered]@{ platform = 'powerbi'; instances = $null }) }
$pbiIdle = Pbi 'pbi-reports' 'A2' @{ owner = 'bi-team@example.com'; env = 'prod' }
$pbiBusy = Pbi 'pbi-portal' 'A1'
$pbiOld  = Pbi 'pbi-legacy' 'A1'
Save '25-idle-data-platforms.json' @($fab, $synIdle, $synBusy, $adx, $adxBusy, $pbiIdle, $pbiBusy, $pbiOld)
$metrics["$($pbiIdle.id.ToLower())|cpu_metric"] = MetricResp ([ordered]@{ cpu_metric = @(Ts @() 'average' (Hours 480 0 0)) })
$metrics["$($pbiBusy.id.ToLower())|cpu_metric"] = MetricResp ([ordered]@{ cpu_metric = @(Ts @() 'average' (Hours 480 5 40)) })
$metrics["$($synIdle.id.ToLower())|connections"] = Set-Metrics $synIdle.id ([ordered]@{ Connections = 0; ActiveQueries = 0 })
$metrics["$($synBusy.id.ToLower())|connections"] = Set-Metrics $synBusy.id ([ordered]@{ Connections = 300; ActiveQueries = 1200 })
Set-Metric $adx.id 'IngestionVolumeInMB' 'total' @(@{ value = 5000 })       # ingests, never queried: medium
Set-Metric $adx.id 'QueryResult' 'count' @()
Set-Metric $adxBusy.id 'IngestionVolumeInMB' 'total' @(@{ value = 900 })
Set-Metric $adxBusy.id 'QueryResult' 'count' @(@{ value = 4500 })

$redisT = 'Microsoft.Cache/Redis'
$rdsOld  = Cand 'idle-redis-cache' $D 'rg-web-dev' $redisT 'redis-session-old' 'eastus' @{ env = 'dev'; sku = 'C1'; tier = 'Standard'; sizeGb = 1; extra = '6.0' } ([ordered]@{ units = 1; tier = 'Standard'; managed = $false })
$rdsProd = Cand 'idle-redis-cache' $P 'rg-web' $redisT 'redis-prod' 'eastus' @{ env = 'prod'; sku = 'P1'; tier = 'Premium'; sizeGb = 1; extra = '6.0' } ([ordered]@{ units = 1; tier = 'Premium'; managed = $false })
# Azure Managed Redis: billed per instance, 2 with high availability
$amrT = 'Microsoft.Cache/redisEnterprise'
$amrOld  = Cand 'idle-redis-cache' $P 'rg-web' $amrT 'amr-sessions-legacy' 'eastus' @{ owner = 'web@example.com'; env = 'prod'; sku = 'B5'; tier = 'Balanced'; sizeGb = 2 } ([ordered]@{ units = 2; tier = 'Balanced'; managed = $true })
$amrBusy = Cand 'idle-redis-cache' $P 'rg-web' $amrT 'amr-catalog' 'eastus' @{ env = 'prod'; sku = 'M20'; tier = 'MemoryOptimized'; sizeGb = 2 } ([ordered]@{ units = 2; tier = 'MemoryOptimized'; managed = $true })
Save '26-idle-redis-caches.json' @($rdsOld, $rdsProd, $amrOld, $amrBusy)
Set-Metric $amrOld.id 'connectedclients' 'maximum' @()
Set-Metric $amrBusy.id 'connectedclients' 'maximum' @(@{ value = 140 })
Set-Metric $rdsOld.id 'connectedclients' 'maximum' @()                     # no client ever: no series
Set-Metric $rdsProd.id 'connectedclients' 'maximum' @(@{ value = 25 })

$sb = Cand 'idle-messaging-namespace' $P 'rg-orders' 'Microsoft.ServiceBus/namespaces' 'sb-legacy-orders' 'eastus' @{ owner = 'orders@example.com'; env = 'prod'; sku = 'Premium'; tier = 'Service Bus'; sizeGb = 1; createdTime = (Ago 700); ageDays = 700 } ([ordered]@{ units = 1; service = 'Service Bus' })
$evhBusy = Cand 'idle-messaging-namespace' $P 'rg-telemetry' 'Microsoft.EventHub/namespaces' 'evh-telemetry' 'eastus' @{ sku = 'Standard'; tier = 'Event Hubs'; sizeGb = 2; createdTime = (Ago 400); ageDays = 400 } ([ordered]@{ units = 2; service = 'Event Hubs' })
$evhDev  = Cand 'idle-messaging-namespace' $D 'rg-sandbox' 'Microsoft.EventHub/namespaces' 'evh-dev-unused' 'eastus' @{ env = 'dev'; sku = 'Basic'; tier = 'Event Hubs'; sizeGb = 1; createdTime = (Ago 200); ageDays = 200 } ([ordered]@{ units = 1; service = 'Event Hubs' })
Save '27-idle-messaging-namespaces.json' @($sb, $evhBusy, $evhDev)
$metrics["$($sb.id.ToLower())|incomingmessages"] = Set-Metrics $sb.id ([ordered]@{ IncomingMessages = 0; OutgoingMessages = 0 })
$metrics["$($evhBusy.id.ToLower())|incomingmessages"] = Set-Metrics $evhBusy.id ([ordered]@{ IncomingMessages = 1000000; OutgoingMessages = 990000 })
$metrics["$($evhDev.id.ToLower())|incomingmessages"] = Set-Metrics $evhDev.id ([ordered]@{ IncomingMessages = 0; OutgoingMessages = 0 })

$apimT = 'Microsoft.ApiManagement/service'
$apimOld  = Cand 'idle-api-management' $P 'rg-api' $apimT 'apim-legacy' 'eastus' @{ owner = 'api-team@example.com'; env = 'prod'; sku = 'Developer'; tier = '1 region(s)'; sizeGb = 1; createdTime = (Ago 500); ageDays = 500 } ([ordered]@{ units = 1; regions = 1 })
$apimProd = Cand 'idle-api-management' $P 'rg-api' $apimT 'apim-prod' 'eastus' @{ env = 'prod'; sku = 'Premium'; tier = '1 region(s)'; sizeGb = 1; createdTime = (Ago 500); ageDays = 500 } ([ordered]@{ units = 1; regions = 1 })
Save '28-idle-api-management.json' @($apimOld, $apimProd)
Set-Metric $apimOld.id 'Requests' 'total' @()
Set-Metric $apimProd.id 'Requests' 'total' @(@{ value = 5000000 })

$mlw = Cand 'idle-ml-compute' $D 'rg-ml' 'Microsoft.MachineLearningServices/workspaces' 'mlw-research' 'eastus' @{ owner = 'ml@example.com'; env = 'dev'; sku = 'Basic'; tier = 'Default' } ([ordered]@{ kind = 'Default' })
Save '29-idle-ml-compute-clusters.json' @($mlw)
# cpu-cluster: 2 idle nodes every hour, never ran a job (high). batch-cluster: 1 idle node always, runs
# jobs (medium). gpu-train: scales to 0 between jobs (dropped).
$metrics["$($mlw.id.ToLower())|idle nodes"] = MetricResp ([ordered]@{
    'Idle Nodes' = @((Ts @('ClusterName', 'cpu-cluster') 'minimum' (Hours 480 2 2)), (Ts @('ClusterName', 'batch-cluster') 'minimum' (Hours 480 1 3)), (Ts @('ClusterName', 'gpu-train') 'minimum' (Hours 480 0 1)))
    'Idle Cores' = @((Ts @('ClusterName', 'cpu-cluster') 'minimum' (Hours 480 8 8)), (Ts @('ClusterName', 'batch-cluster') 'minimum' (Hours 480 4 12)), (Ts @('ClusterName', 'gpu-train') 'minimum' (Hours 480 0 6))) })
$metrics["$($mlw.id.ToLower())|active nodes"] = MetricResp ([ordered]@{ 'Active Nodes' = @((Ts @('ClusterName', 'cpu-cluster') 'maximum' @(0)), (Ts @('ClusterName', 'batch-cluster') 'maximum' @(6)), (Ts @('ClusterName', 'gpu-train') 'maximum' @(4))) })

$peT = 'Microsoft.Network/privateEndpoints'
Save '30-orphaned-private-endpoints.json' @(
    (Row 'orphaned-private-endpoint' $D 'rg-legacy' $peT 'pe-st-deleted' 'eastus' (@{ env = 'dev'; tier = 'Disconnected'; extra = (Rid $D 'rg-legacy' $st 'stdeleted01')
        reason = 'Connection to stdeleted01 is Disconnected (the target was deleted or dropped the connection), so no traffic flows, but the endpoint bills hourly' } + $unk)),
    (Row 'orphaned-private-endpoint' $P 'rg-data' $peT 'pe-sql-rejected' 'eastus' (@{ env = 'prod'; tier = 'Rejected'; extra = (Rid $P 'rg-partner' 'Microsoft.Sql/servers' 'sql-partner'); confidence = 'medium'
        reason = 'Connection to sql-partner was Rejected by the owner of the target, so no traffic flows, but the endpoint bills hourly' } + $unk)))
Save '31-unused-public-ip-prefixes.json' @(
    (Row 'unused-public-ip-prefix' $P 'rg-net' 'Microsoft.Network/publicIPPrefixes' 'ippre-legacy' 'eastus' (@{ owner = 'netops@example.com'; env = 'prod'; sku = 'Regional'; tier = '/28'; sizeGb = 16; extra = '20.10.30.0/28'
        confidence = 'medium'; reason = 'Prefix 20.10.30.0/28 (16 addresses) has no public IP, NAT gateway or load balancer using it, but every address bills hourly' } + $unk)))
Save '32-empty-edge-profiles.json' @(
    (Row 'empty-edge-profile' $P 'rg-web' 'Microsoft.Cdn/profiles' 'afd-old-site' 'global' (@{ owner = 'web@example.com'; env = 'prod'; sku = 'Standard_AzureFrontDoor'; tier = 'front-door'; sizeGb = 0
        reason = 'Standard_AzureFrontDoor profile has no endpoints, but bills its monthly base fee' } + $unk)),
    (Row 'empty-edge-profile' $D 'rg-sandbox' 'Microsoft.Network/trafficManagerProfiles' 'tm-unused' 'global' (@{ sku = 'Traffic Manager'; tier = 'traffic-manager'; sizeGb = 0; confidence = 'low'
        reason = 'Traffic Manager profile has no endpoints. It bills only DNS queries, so it is nearly free (clutter only)' } + $unk)))
Save '33-nonprod-vms-always-on.json' @(
    (Row 'nonprod-vm-always-on' $D 'rg-api' $vm 'vm-dev-api' 'eastus' @{ owner = 'api-team@example.com'; env = 'dev'; createdTime = (Ago 250); ageDays = 250; idleSource = 'not applicable (running)'
        sku = 'Standard_D4s_v5'; tier = 'Regular'; os = 'Linux'; confidence = 'medium'
        reason = 'Tagged env=dev and running with no auto-shutdown schedule, so it bills around the clock. Schedulers other than auto-shutdown (Automation, Start/Stop VMs v2, pipelines) are not visible here' }))
Save '35-hybrid-benefit-not-applied.json' @(
    (Row 'hybrid-benefit-not-applied' $P 'rg-erp' $vm 'vm-win-app01' 'eastus' @{ owner = 'erp@example.com'; env = 'prod'; idleSource = 'not applicable (in use)'; sku = 'Standard_D4s_v5'; tier = 'windows-vm'; os = 'Windows'
        confidence = 'low'; reason = 'Windows VM pays for the Windows Server licence by the hour (Azure Hybrid Benefit is off). This is a saving only if you own eligible licences with Software Assurance or subscriptions' }),
    ((Row 'hybrid-benefit-not-applied' $P 'rg-erp' 'Microsoft.Sql/servers' 'sqlsrv-erp/databases/erp' 'eastus' @{ owner = 'erp@example.com'; env = 'prod'; idleSource = 'not applicable (in use)'; sku = 'GP_Gen5'; tier = 'sql-db'; sizeGb = 8; os = 'GeneralPurpose'
        confidence = 'low'; reason = 'SQL GeneralPurpose pays for the SQL Server licence by the hour (LicenseIncluded). This is a saving only if you own eligible licences with Software Assurance or subscriptions' }) | ForEach-Object { $_.name = 'sqlsrv-erp/erp'; $_.type = 'microsoft.sql/servers/databases'; $_ }))
$stDevLogs = Cand 'nonprod-geo-redundant-storage' $D 'rg-build' $st 'stdevlogs' 'eastus' @{ env = 'dev'; sku = 'Standard_RAGRS'; tier = 'Hot'; extra = 'StorageV2'; createdTime = (Ago 400); ageDays = 400; idleSource = 'not applicable (in use)' } ([ordered]@{ accessTier = 'Hot' })
$stDevTiny = Cand 'nonprod-geo-redundant-storage' $D 'rg-build' $st 'stdevtiny' 'eastus' @{ env = 'dev'; sku = 'Standard_GRS'; tier = 'Hot'; extra = 'StorageV2'; createdTime = (Ago 400); ageDays = 400; idleSource = 'not applicable (in use)' } ([ordered]@{ accessTier = 'Hot' })
Save '36-nonprod-geo-redundant-storage.json' @($stDevLogs, $stDevTiny)
Set-Metric $stDevLogs.id 'UsedCapacity' 'average' @(@{ value = 500GB })
Set-Metric $stDevTiny.id 'UsedCapacity' 'average' @(@{ value = 2GB })    # under 10 GiB: dropped
# vm-api-01 also has an Advisor right-size recommendation, which merges into this finding
function BigVm($sub, $rg, $name, $size, [hashtable] $x = @{}) {
    Cand 'underused-vm' $sub $rg $vm $name 'eastus' (@{ sku = $size; tier = 'Regular'; os = 'Linux'; createdTime = (Ago 600); ageDays = 600; idleSource = 'pending (CPU metrics)' } + $x) ([ordered]@{ vmSize = $size })
}
$vmOver  = BigVm $P 'rg-api' 'vm-api-01' 'Standard_D16s_v5' @{ owner = 'api-team@example.com'; app = 'orders-api'; env = 'prod' }
$vmBusy  = BigVm $P 'rg-api' 'vm-api-02' 'Standard_D8s_v5'
$vmSmall = BigVm $P 'rg-api' 'vm-api-tiny' 'Standard_D2s_v5'      # 2 vCPUs: never judged
$vmMem   = BigVm $P 'rg-api' 'vm-cache-01' 'Standard_E8s_v5'      # CPU idle, but memory-bound: dropped
$vmNoMem = BigVm $D 'rg-build' 'vm-batch-old' 'Standard_D4s_v5' @{ env = 'dev' }   # CPU idle, no memory metric: medium
Save '37-underused-vms.json' @($vmOver, $vmBusy, $vmSmall, $vmMem, $vmNoMem)
# vm-api-01: memory 65-80% available (at most 35% used), so it fits in half: high
$metrics["$($vmOver.id.ToLower())|percentage cpu"] = MetricResp ([ordered]@{ 'Percentage CPU' = @(Ts @() 'average' (Hours 480 0.5 3.5)); 'Available Memory Percentage' = @(Ts @() 'average' (Hours 480 65 80)) })
$metrics["$($vmMem.id.ToLower())|percentage cpu"] = MetricResp ([ordered]@{ 'Percentage CPU' = @(Ts @() 'average' (Hours 480 0.5 2)); 'Available Memory Percentage' = @(Ts @() 'average' (Hours 480 25 45)) })
$metrics["$($vmNoMem.id.ToLower())|percentage cpu"] = MetricResp ([ordered]@{ 'Percentage CPU' = @(Ts @() 'average' (Hours 480 0.5 2)) })
$metrics["$($vmBusy.id.ToLower())|percentage cpu"] = MetricResp ([ordered]@{ 'Percentage CPU' = @(Ts @() 'average' (Hours 480 20 60)) })

# Reservations: one order, found through a usage record's additionalProperties. Fields as in the CLI's schema. r1 used 30% of its hours
# (flagged, high); r2 used 96% (dropped).
$resOrder = 'aaaaaaaa-1111-2222-3333-444444444444'
$resIds = 'bbbbbbbb-1111-2222-3333-444444444444', 'cccccccc-1111-2222-3333-444444444444'
$resDays = foreach ($i in 1..30) {
    @{ reservationOrderId = $resOrder; reservationId = "/providers/microsoft.capacity/reservationorders/$resOrder/reservations/$($resIds[0])"; skuName = 'Standard_D4s_v5'
       usageDate = $now.AddDays(-$i).ToString('yyyy-MM-dd'); reservedHours = 96; usedHours = 28.8; avgUtilizationPercentage = 30 }
    @{ reservationOrderId = $resOrder; reservationId = "/providers/microsoft.capacity/reservationorders/$resOrder/reservations/$($resIds[1])"; skuName = 'Standard_E8s_v5'
       usageDate = $now.AddDays(-$i).ToString('yyyy-MM-dd'); reservedHours = 24; usedHours = 23; avgUtilizationPercentage = 95.83 }
}
@{ $resOrder = @($resDays) } | ConvertTo-Json -Depth 6 -Compress | Set-Content (Join-Path $Out 'reservations.json') -Encoding utf8

# Exclusions health: the IDs Resource Graph finds when asked whether excluded resources still exist
# (app-portal exists but no query returns it, so an exclusion for it matches nothing)
Save 'exclusion-check.json' @(@{ id = (Rid $P 'rg-web' 'Microsoft.Web/sites' 'app-portal').ToLower() })

# Resource group owner tags: the fallback owner for findings whose resource has no owner tag
Save 'rg-owners.json' @(
    @{ subscriptionId = $D; resourceGroup = 'rg-legacy'; owner = 'legacy-team@example.com' },
    @{ subscriptionId = $P; resourceGroup = 'rg-web'; owner = 'web@example.com' },
    @{ subscriptionId = $D; resourceGroup = 'rg-sandbox'; owner = 'sandbox@example.com' })

# CPU metrics: build agent last ran 47 days ago (so the 2nd 30-day window has data); jumpbox has none
$pts = @(for ($i = 60; $i -ge 47; $i--) { @{ timeStamp = $now.AddDays(-$i).ToString('yyyy-MM-ddT00:00:00Z'); maximum = 35.5 } })
$metrics[$vmBuild.ToLower()] = @{ value = @(@{ timeseries = @(@{ data = $pts }) }) }
$metrics | ConvertTo-Json -Depth 12 -Compress | Set-Content (Join-Path $Out 'metrics.json') -Encoding utf8

# Billed usage: 30 days for the build agent and the SQL disk, in demo-prod / demo-dev
$usage = foreach ($i in 1..30) {
    @{ instanceId = $vmBuild; pretaxCost = 9.216; currency = 'USD'; usageStart = $now.AddDays(-$i).ToString('yyyy-MM-ddT00:00:00Z') }
    @{ instanceId = (Rid $P 'rg-sql-prod' $disk 'disk-sql-data-old'); pretaxCost = 4.506; currency = 'USD'; usageStart = $now.AddDays(-$i).ToString('yyyy-MM-ddT00:00:00Z') }
}
# Reserved-instance usage names its reservation order in additionalProperties (a JSON string): that's how the scan finds orders
$usage = @($usage) + @{ instanceId = $vmBuild; pretaxCost = 0; currency = 'USD'; usageStart = $now.AddDays(-1).ToString('yyyy-MM-ddT00:00:00Z')
                        additionalProperties = "{""ReservationOrderId"":""$resOrder"",""ReservationId"":""$($resIds[0])"",""ConsumedQuantity"":24}" }
Save 'consumption.json' @($usage)
Write-Host "fixtures written to $Out"
