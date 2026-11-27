# waste-hunter 39 · Uniform scale set instances stopped but not deallocated
# Waste-type record(s) for queries/39-vmss-instances-stopped-not-deallocated.kql: label, flags and the logic for each step. Loaded by
# Import-WasteTypes (lib/Common.ps1). The script blocks run inside Confirm-Candidate, Get-LivePrice,
# Get-Estimate and Get-Action (lib/WasteTypes.ps1) and use the variables those set up there.
# An instance is priced exactly like a standalone VM, so the price blocks are type 05's.

$vm = & (Join-Path $PSScriptRoot '05-vms-stopped-not-deallocated.ps1')

@{
    Name = 'vmss-instance-stopped-not-deallocated'
    Label = 'Scale set instances stopped but not deallocated'
    Order = 39
    QuickWin = $true   # reversible: listed under Quick wins when high confidence (AKS nodes are medium)
    CommitmentEligible = $true   # a reservation or savings plan can cover it
    LivePrice = $vm.LivePrice
    Estimate = $vm.Estimate
    Action = {
        $set = [regex]::Match($id, '(?i)/resourceGroups/([^/]+)/providers/Microsoft\.Compute/virtualMachineScaleSets/([^/]+)/virtualMachines/([^/]+)$')
        $rgName, $setName, $inst = $set.Success ? @($set.Groups[1].Value, $set.Groups[2].Value, $set.Groups[3].Value) : @('<resource-group>', '<scale-set>', '<instance-id>')
        if ($f.reason -like '*managed by AKS*') {
            return @(
                "This is an AKS node. Don't deallocate it directly: find out why it's stopped, then scale the node pool down (or stop the cluster) if the capacity isn't needed.",
                "az aks nodepool scale --resource-group <cluster-resource-group> --cluster-name <cluster> --name <node-pool> --node-count <n>")
        }
        return @(
            "Deallocate the instance to stop compute billing (its disks keep billing), or delete it, or lower the scale set's capacity if it's no longer needed. If every instance in the set is stopped, deallocate the whole set.",
            "az vmss deallocate --resource-group $rgName --name $setName --instance-ids $inst")
    }
}
