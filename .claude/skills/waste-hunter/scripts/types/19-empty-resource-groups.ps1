# waste-hunter 19 · Empty resource groups
# Waste-type record(s) for queries/19-empty-resource-groups.kql: label, flags and the logic for each step. Loaded by
# Import-WasteTypes (lib/Common.ps1). The script blocks run inside Confirm-Candidate, Get-LivePrice,
# Get-Estimate and Get-Action (lib/WasteTypes.ps1) and use the variables those set up there.

@{
    Name = 'empty-resource-group'
    Label = 'Empty resource groups'
    Order = 19
    Estimate = { return @{ Cost = 0.0; Note = 'resource groups are free' } }
    Action = {
        return @(
            'Delete it if nothing is about to be deployed there. Check for locks and role assignments others may rely on first.',
            "az group delete --name $($f.name) --subscription $($f.subscriptionId)")
    }
}
