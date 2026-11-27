# waste-hunter 09 · Log Analytics workspaces: paid retention, or data nobody queries (CANDIDATES)
# Waste-type record(s) for queries/09-log-analytics-workspaces.kql: label, flags and the logic for each step. Loaded by
# Import-WasteTypes (lib/Common.ps1). The script blocks run inside Confirm-Candidate, Get-LivePrice,
# Get-Estimate and Get-Action (lib/WasteTypes.ps1) and use the variables those set up there.

@{
    Name = 'log-analytics-workspace'
    Label = 'Log Analytics: paid retention or unqueried data'
    Order = 9
    Candidate = $true
    Check = {
        $m = Get-MetricStats $r.id @('Ingestion Volume', 'Query Count') 'Count'
        $records = Get-StatSum $m 'Ingestion Volume'; $queries = Get-StatSum $m 'Query Count'
        $problems = @(); $conf = 'low'
        if ([int] $ci.retention -gt [int] $ci.freeRetention) {
            $sentinelNote = [bool] $ci.sentinel ? ' with Sentinel' : ''
            $problems += "retention is $($ci.retention) days, above the free $($ci.freeRetention) days$sentinelNote"
        }
        if ($records -gt 0 -and $queries -eq 0 -and -not $young) {
            $problems += "$('{0:N0}' -f $records) records ingested in 30 days but 0 queries, including alert queries"
            $conf = 'medium'
        }
        if (-not $problems) { return @() }
        $why = ($problems -join '; ') + '. Cost depends on GB ingested and retained, which platform metrics do not expose (see the workspace''s Usage and estimated costs page).'
        $retentionOnly = $problems.Count -eq 1 -and $problems[0] -like 'retention*'
        if ($retentionOnly) { $why += ' Longer retention may be a compliance requirement.' }
        # Retention only: lowering it saves the retention charge, not the workspace's whole bill
        return @(New-FindingFrom $r @{ confidence = $conf; reason = $why; idleDays = $null; idleSource = 'Ingestion Volume/Query Count metrics, 30 days'
                                       records = $records; queries = $queries; partialSaving = $retentionOnly })
    }
    Estimate = { return @{ Cost = $null; Note = 'GB ingested and retained not exposed by metrics' } }
    Action = {
        return @(
            "Check the workspace's Usage and estimated costs page for the real GB and cost. Lower retention to the free period unless a compliance rule needs more (or move old data to the cheaper long-term/archive tier). If nobody queries the data, stop sending it (diagnostic settings, data collection rules) or delete the workspace.",
            "az monitor log-analytics workspace update --ids $id --retention-time 31")
    }
}
