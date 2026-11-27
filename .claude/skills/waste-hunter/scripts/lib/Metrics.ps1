# Part of Invoke-WasteHunt.ps1 (dot-sourced into its scope, so it shares the runner's variables).
# READ-ONLY: see CLAUDE.md. Functions only; nothing runs when this file is loaded.

function Get-LastCpuActivity([string] $ResourceId) {
    for ($k = 0; $k -lt 3; $k++) {
        $end = $Now.AddDays(-30 * $k); $start = $end.AddDays(-30)
        $res = Invoke-AzRead @('monitor', 'metrics', 'list', '--resource', $ResourceId, '--metric', 'Percentage CPU',
            '--interval', 'P1D', '--aggregation', 'Maximum',
            '--start-time', $start.ToString('yyyy-MM-ddTHH:mm:ssZ'), '--end-time', $end.ToString('yyyy-MM-ddTHH:mm:ssZ'))
        $stamps = foreach ($v in @((Get-Key $res 'value'))) { foreach ($ts in @((Get-Key $v 'timeseries'))) { foreach ($d in @((Get-Key $ts 'data'))) {
            $mx = Get-Key $d 'maximum'
            if ($null -ne $mx -and [double] $mx -gt 0) { [string] (Get-Key $d 'timeStamp') } } } }
        $last = @($stamps) | Sort-Object | Select-Object -Last 1
        if ($last) { return @{ Window = 90; Last = [DateTimeOffset]::Parse($last, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime } }
    }
    return @{ Window = 90; Last = $null }
}

function Get-MetricStats([string] $Id, [string[]] $Metrics, [string] $Aggregation = 'Total', [string] $Interval = 'P1D',
                         [int] $Days = 30, [string] $Filter) {
    $a = @('monitor', 'metrics', 'list', '--resource', $Id, '--metric') + $Metrics +
         @('--aggregation', $Aggregation, '--interval', $Interval,
           '--start-time', $Now.AddDays(-$Days).ToString('yyyy-MM-ddTHH:mm:ssZ'), '--end-time', $Now.ToString('yyyy-MM-ddTHH:mm:ssZ'))
    if ($Filter) { $a += @('--filter', $Filter) }
    $res = Invoke-AzRead $a
    $agg = $Aggregation.ToLower()
    $out = @{}
    # Index access throughout: strict mode throws on a missing key read with dot syntax, and metric
    # responses omit keys freely.
    foreach ($v in @((Get-Key $res 'value'))) {
        if (-not $v) { continue }
        $s = @{ Sum = 0.0; Points = 0; Last = $null; BySplit = @{} }
        foreach ($ts in @((Get-Key $v 'timeseries'))) {
            if (-not $ts) { continue }
            $mv = @((Get-Key $ts 'metadatavalues') | Where-Object { $_ })
            $key = $mv ? [string] (Get-Key $mv[0] 'value') : ''
            foreach ($d in @((Get-Key $ts 'data'))) {
                $x = Get-Key $d $agg
                if ($null -eq $x) { continue }
                $x = [double] $x
                $s.Sum += $x; $s.Points++; $s.Last = $x
                $s.BySplit[$key] = ($s.BySplit[$key] ?? 0.0) + $x
            }
        }
        $out[[string] (Get-Key (Get-Key $v 'name') 'value')] = $s
    }
    return $out
}

function Add-BilledCosts([string] $SubscriptionId, [hashtable] $Billed) {
    $usage = Invoke-AzRead @('consumption', 'usage', 'list', '--subscription', $SubscriptionId,
        '--start-date', $Now.AddDays(-30).ToString('yyyy-MM-dd'), '--end-date', $Now.ToString('yyyy-MM-dd'))
    $n = 0; $total = 0
    foreach ($u in @($usage)) {
        if ($u) { $total++ }
        # Index access: some billing schemas omit these keys entirely
        $iid = Get-Key $u 'instanceId'; $cost = Get-Key $u 'pretaxCost'
        if (-not $iid -or $null -eq $cost -or [string] $cost -eq 'None') { continue }
        $key = ([string] $iid).ToLower()
        if (-not $Billed.ContainsKey($key)) { $Billed[$key] = @{ Cost = 0.0; Days = [Collections.Generic.HashSet[string]]::new(); Currency = '' } }
        $e = $Billed[$key]
        $e.Cost += [double] $cost
        $start = Get-Key $u 'usageStart'; $cur = Get-Key $u 'currency'
        if ($start) { [void] $e.Days.Add(([string] $start).Substring(0, 10)) }
        if ($cur) { $e.Currency = [string] $cur }
        $n++
    }
    # Newer billing accounts (MCA, some Visual Studio offers) return usage records that
    # 'az consumption' maps to its legacy schema with no instanceId or cost. Report that instead of
    # pretending the cost is zero.
    if ($total -gt 0 -and $n -eq 0) { throw "Consumption API returned $total usage record(s) with no instanceId/pretaxCost (billing schema not readable by 'az consumption')" }
    return $n
}
