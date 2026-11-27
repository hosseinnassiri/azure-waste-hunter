# waste-hunter 29 · Azure Machine Learning compute clusters that never scale to zero (CANDIDATES, confirmed by metrics)
# Waste-type record(s) for queries/29-idle-ml-compute-clusters.kql: label, flags and the logic for each step. Loaded by
# Import-WasteTypes (lib/WasteTypes.ps1). The script blocks run inside Confirm-Candidate, Get-LivePrice,
# Get-Estimate and Get-Action (lib/WasteTypes.ps1) and use the variables those set up there.

@{
    Name = 'idle-ml-compute'
    Label = 'ML compute clusters that never scale to zero'
    Order = 29
    Candidate = $true
    PartialSaving = $true        # setting min nodes to 0 saves the always-idle nodes, not the cluster
    QuickWin = $true             # the minimum node count can be raised again at any time
    Check = {
        # Hourly minimum per cluster: at least one idle node in every hour means it never reached zero
        $idle = Get-MetricStats $r.id @('Idle Nodes', 'Idle Cores') 'Minimum' 'PT1H' -Filter "ClusterName eq '*'"
        $nodes = $idle['Idle Nodes']; $cores = $idle['Idle Cores']
        if (-not $nodes -or -not $nodes.MinBySplit.Count) { return @() }
        $active = (Get-MetricStats $r.id @('Active Nodes') 'Maximum' 'PT1H' -Filter "ClusterName eq '*'")['Active Nodes']
        $out = @()
        foreach ($cl in @($nodes.MinBySplit.Keys | Sort-Object)) {
            $minIdle = [double] $nodes.MinBySplit[$cl]
            if (-not $cl -or $minIdle -lt 1 -or $nodes.PointsBySplit[$cl] -lt 480) { continue }    # needs 20+ days of hourly data
            $minCores = ($cores -and $cores.MinBySplit.ContainsKey($cl)) ? [double] $cores.MinBySplit[$cl] : 0.0
            $ran = ($active -and $active.MaxBySplit.ContainsKey($cl)) ? [double] $active.MaxBySplit[$cl] : 0.0
            $why = ('Cluster kept at least {0:N0} idle node(s) ({1:N0} cores) in every hour for 30 days, so its minimum node count is above 0 and those nodes bill like VMs' -f $minIdle, $minCores)
            $why += ($ran -gt 0) ? ('. It does run jobs (up to {0:N0} active nodes), so only the always-idle part is the saving' -f $ran) : '. No jobs ran on it in 30 days'
            $out += New-FindingFrom $r @{ id = "$($r.id)/computes/$cl"; name = "$($r.name)/$cl"; type = 'microsoft.machinelearningservices/workspaces/computes'
                sku = 'AmlCompute'; sizeGb = [int] $minIdle; confidence = ($ran -gt 0) ? 'medium' : 'high'; reason = $why
                idleDays = 30; idleSource = 'Idle Nodes and Active Nodes metrics by cluster, 30 days'; idleCores = $minCores }
        }
        return $out
    }
    Estimate = {
        if (-not $f.idleCores) { return @{ Cost = $null; Note = 'idle core count not reported' } }
        return @{ Cost = $f.idleCores * $Pricing.machineLearning.perIdleCoreHour * $Pricing.hoursPerMonth; Note = ('{0:N0} always-idle core(s) at a CPU VM rate (cluster VM size not readable; GPU nodes cost far more)' -f $f.idleCores) }
    }
    Action = {
        return @(
            'Set the cluster''s minimum node count to 0 and a short idle time before scale-down (for example 120 seconds), so nodes are released between jobs. The first job after idle then waits a few minutes for a node.',
            "az ml compute update --name $(($f.name -split '/')[-1]) --workspace-name $(($f.name -split '/')[0]) --resource-group $($f.resourceGroup) --min-instances 0")
    }
}
