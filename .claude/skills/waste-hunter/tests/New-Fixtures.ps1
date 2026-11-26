param([string] $Out)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force $Out | Out-Null
$T = '00000000-0000-0000-0000-00000000demo'
$P = '11111111-1111-1111-1111-111111111111'   # demo-prod
$D = '22222222-2222-2222-2222-222222222222'   # demo-dev
$now = [DateTime]::UtcNow
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

# CPU metrics: build agent last ran 47 days ago (so the 2nd 30-day window has data); jumpbox has none
$pts = @(for ($i = 60; $i -ge 47; $i--) { @{ timeStamp = $now.AddDays(-$i).ToString('yyyy-MM-ddT00:00:00Z'); maximum = 35.5 } })
$metrics[$vmBuild.ToLower()] = @{ value = @(@{ timeseries = @(@{ data = $pts }) }) }
$metrics | ConvertTo-Json -Depth 12 | Set-Content (Join-Path $Out 'metrics.json') -Encoding utf8

# Billed usage: 30 days for the build agent and the SQL disk, in demo-prod / demo-dev
$usage = foreach ($i in 1..30) {
    @{ instanceId = $vmBuild; pretaxCost = 9.216; currency = 'USD'; usageStart = $now.AddDays(-$i).ToString('yyyy-MM-ddT00:00:00Z') }
    @{ instanceId = (Rid $P 'rg-sql-prod' $disk 'disk-sql-data-old'); pretaxCost = 4.506; currency = 'USD'; usageStart = $now.AddDays(-$i).ToString('yyyy-MM-ddT00:00:00Z') }
}
Save 'consumption.json' @($usage)
Write-Host "fixtures written to $Out"
