# waste-hunter 30 · Private endpoints whose target is gone or refused the connection
# Waste-type record(s) for queries/30-orphaned-private-endpoints.kql: label, flags and the logic for each step. Loaded by
# Import-WasteTypes (lib/WasteTypes.ps1). The script blocks run inside Confirm-Candidate, Get-LivePrice,
# Get-Estimate and Get-Action (lib/WasteTypes.ps1) and use the variables those set up there.

@{
    Name = 'orphaned-private-endpoint'
    Label = 'Private endpoints with no working connection'
    Order = 30
    QuickWin = $true   # no traffic can flow through it
    Estimate = { return @{ Cost = $Pricing.network.privateEndpointPerHour * $Pricing.hoursPerMonth; Note = 'private endpoint list price; data processed extra' } }
    Action = {
        $what = ($f.tier -eq 'Rejected') ? "Ask $who whether the connection should be requested again; if not, delete the endpoint" : 'Delete the endpoint (its network interface goes with it), and the private DNS record for it if nothing else uses that'
        return @("$what.", "az network private-endpoint delete --ids $id")
    }
}
