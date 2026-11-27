# waste-hunter 07 · Azure Advisor cost recommendations
# Waste-type record(s) for queries/07-advisor-cost.kql: label, flags and the logic for each step. Loaded by
# Import-WasteTypes (lib/Common.ps1). The script blocks run inside Confirm-Candidate, Get-LivePrice,
# Get-Estimate and Get-Action (lib/WasteTypes.ps1) and use the variables those set up there.

@{
    Name = 'advisor-cost'
    Label = 'Other Azure Advisor cost recommendations'
    Order = 99
    Action = { return @("Advisor suggests: $($f.extra). Review it on the Advisor Cost tab.", '') }
}
