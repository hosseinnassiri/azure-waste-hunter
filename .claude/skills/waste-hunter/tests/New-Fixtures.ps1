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

Set-Content (Join-Path $Out 'account.json') (@{ id = $P; name = 'demo-prod'; tenantId = $T; state = 'Enabled' } | ConvertTo-Json) -Encoding utf8
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
    (Row 'unattached-disk' $D 'rg-build' $disk 'disk-temp-build' 'eastus' @{ owner = 'ci@example.com'; env = 'dev'
        createdTime = (Ago 9); ageDays = 9; idleDays = 3; idleSource = 'LastOwnershipUpdateTime'; sku = 'StandardSSD_LRS'; tier = ''; sizeGb = 128
        confidence = 'low'; reason = 'Unattached for 3 days (LastOwnershipUpdateTime); recently detached, may be mid-redeploy' }),
    (Row 'unattached-disk' $P 'rg-dr' $disk 'asrseeddisk-web01-a1b2c3' 'westus2' @{ app = 'web'; env = 'prod'
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
    (Row 'unassociated-public-ip' $P 'rg-web' $pip 'pip-old-lb-frontend' 'eastus' @{ app = 'web'; env = 'prod'; idleSource = 'unknown (not exposed by Resource Graph)'
        sku = 'Standard'; tier = 'Regional'; extra = 'Static'; reason = 'Not associated with any resource (Standard / Static); has a DNS label, releasing it frees the FQDN' }),
    (Row 'unassociated-public-ip' $D 'rg-sandbox' $pip 'pip-test-dyn' 'centralus' @{ idleSource = 'unknown (not exposed by Resource Graph)'
        sku = 'Basic'; tier = 'Regional'; extra = 'Dynamic'; confidence = 'low'; reason = 'Not associated with any resource (Basic / Dynamic); Basic dynamic and unassociated, so no charge, clutter only' }))

$asp = 'Microsoft.Web/serverFarms'
Save '04-empty-app-service-plans.json' @(
    (Row 'empty-app-service-plan' $P 'rg-api' $asp 'asp-legacy-api' 'eastus' @{ owner = 'api-team@example.com'; app = 'orders-api'; env = 'prod'
        idleSource = 'unknown (not exposed by Resource Graph)'; sku = 'P1v3'; tier = 'PremiumV3'; sizeGb = 2; os = 'Linux'; extra = 'linux'
        reason = 'Plan hosts 0 apps (PremiumV3 P1v3 x2 instance(s))' }),
    (Row 'empty-app-service-plan' $D 'rg-sandbox' $asp 'asp-playground' 'centralus' @{ idleSource = 'unknown (not exposed by Resource Graph)'
        sku = 'F1'; tier = 'Free'; sizeGb = 1; os = 'Windows'; extra = 'app'; confidence = 'low'; reason = 'Plan hosts 0 apps (Free F1 x1 instance(s)); free/consumption tier, no charge while empty' }))

$vm = 'Microsoft.Compute/virtualMachines'
$vmBuild = Rid $D 'rg-build' $vm 'vm-build-agent-02'
$vmJump  = Rid $P 'rg-ops' $vm 'vm-win-jumpbox'
Save '05-vms-stopped-not-deallocated.json' @(
    (Row 'vm-stopped-not-deallocated' $D 'rg-build' $vm 'vm-build-agent-02' 'eastus' @{ owner = 'ci@example.com'; app = 'build'; env = 'dev'
        createdTime = (Ago 420); ageDays = 420; idleSource = 'pending (CPU metrics)'; sku = 'Standard_D8s_v5'; tier = 'Regular'; os = 'Linux'
        reason = 'Power state is Stopped (not deallocated), so compute is still billed' }),
    (Row 'vm-stopped-not-deallocated' $P 'rg-ops' $vm 'vm-win-jumpbox' 'eastus' @{ owner = 'ops@example.com'; env = 'prod'
        createdTime = (Ago 800); ageDays = 800; idleSource = 'pending (CPU metrics)'; sku = 'Standard_B2ms'; tier = 'Regular'; os = 'Windows'; extra = ''
        reason = 'Power state is Stopped (not deallocated), so compute is still billed' }))

$snap = 'Microsoft.Compute/snapshots'
Save '06-old-snapshots.json' @(
    (Row 'old-snapshot' $P 'rg-sql-prod' $snap 'snap-sql-pre-upgrade-2025' 'eastus' @{ owner = 'data-team@example.com'; app = 'billing-db'; env = 'prod'
        createdTime = (Ago 412); ageDays = 412; idleDays = 412; idleSource = 'timeCreated'; sku = 'Standard_LRS'; tier = 'full'; sizeGb = 1024
        reason = 'Snapshot is 412 days old (full); source disk still exists' }),
    (Row 'old-snapshot' $D 'rg-legacy' $snap 'snap-vm-old01-osdisk' 'eastus' @{ env = 'dev'
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

# CPU metrics: build agent last ran 47 days ago (so the 2nd 30-day window has data); jumpbox has none
$pts = @(for ($i = 60; $i -ge 47; $i--) { @{ timeStamp = $now.AddDays(-$i).ToString('yyyy-MM-ddT00:00:00Z'); maximum = 35.5 } })
@{ $vmBuild.ToLower() = @{ value = @(@{ timeseries = @(@{ data = $pts }) }) } } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $Out 'metrics.json') -Encoding utf8

# Billed usage: 30 days for the build agent and the SQL disk, in demo-prod / demo-dev
$usage = foreach ($i in 1..30) {
    @{ instanceId = $vmBuild; pretaxCost = 9.216; currency = 'USD'; usageStart = $now.AddDays(-$i).ToString('yyyy-MM-ddT00:00:00Z') }
    @{ instanceId = (Rid $P 'rg-sql-prod' $disk 'disk-sql-data-old'); pretaxCost = 4.506; currency = 'USD'; usageStart = $now.AddDays(-$i).ToString('yyyy-MM-ddT00:00:00Z') }
}
Save 'consumption.json' @($usage)
Write-Host "fixtures written to $Out"
