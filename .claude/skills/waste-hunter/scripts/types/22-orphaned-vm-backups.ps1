# waste-hunter 22 · Backups of VMs, and of databases on VMs, whose VM no longer exists
# Waste-type record(s) for queries/22-orphaned-vm-backups.kql: label, flags and the logic for each step. Loaded by
# Import-WasteTypes (lib/WasteTypes.ps1). The script blocks run inside Confirm-Candidate, Get-LivePrice,
# Get-Estimate and Get-Action (lib/WasteTypes.ps1) and use the variables those set up there.

@{
    Name = 'orphaned-vm-backup'
    Label = 'Backups of deleted VMs'
    Order = 22
    Estimate = { return @{ Cost = $null; Note = "backup storage of retained recovery points (and the protected-instance fee while protected); see the vault's Backup items and Cost analysis" } }
    Action = {
        return @(
            "Do NOT delete before confirming with ${who}: this may be the only copy of the deleted VM's data, kept on purpose. Check retention, legal hold or compliance requirements first. If it's not needed, stop protection and delete the backup data (soft delete keeps it recoverable for 14 more days).",
            "az backup protection disable --ids $id --delete-backup-data true --yes")
    }
}

# SQL Server and SAP HANA databases backed up from inside a VM that no longer exists (same query)
@{
    Name = 'orphaned-workload-backup'
    Label = 'Backups of databases on deleted VMs'
    Order = 22.5
    Estimate = { return @{ Cost = $null; Note = "backup storage of retained recovery points (and the protected-instance fee while protected); see the vault's Backup items and Cost analysis" } }
    Action = {
        return @(
            "Do NOT delete before confirming with ${who}: this may be the only copy of the database, kept on purpose. Check retention, legal hold or compliance requirements first. If it's not needed, stop protection and delete the backup data (soft delete keeps it recoverable for 14 more days).",
            "az backup protection disable --ids $id --delete-backup-data true --yes")
    }
}
