# waste-hunter 02 · Orphaned network interfaces (no VM attached)
# Waste-type record(s) for queries/02-orphaned-nics.kql: label, flags and the logic for each step. Loaded by
# Import-WasteTypes (lib/Common.ps1). The script blocks run inside Confirm-Candidate, Get-LivePrice,
# Get-Estimate and Get-Action (lib/WasteTypes.ps1) and use the variables those set up there.

@{
    Name = 'orphaned-nic'
    Label = 'Orphaned NICs (no VM attached)'
    Order = 2
    Estimate = { return @{ Cost = 0.0; Note = 'NICs are free' } }
    Action = {
        return @(
            "Delete the NIC if nothing will reattach it. This frees its private IP$(($f.extra -eq 'holds-public-ip') ? ' and releases its public IP association' : '').",
            "az network nic delete --ids $id")
    }
}
