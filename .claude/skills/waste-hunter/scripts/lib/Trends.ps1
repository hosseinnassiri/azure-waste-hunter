# Part of Invoke-WasteHunt.ps1 (dot-sourced into its scope, so it shares the runner's variables).
# READ-ONLY: see CLAUDE.md. Functions only; nothing runs when this file is loaded.
#
# Trends across scans, from the findings.json of every earlier scan of the same scope (and the same
# real/synthetic mode) in the reports folder. Local files only.
#   Scans     one row per scan: findings, estimated monthly per currency, the high-confidence part,
#             new and resolved (older reports didn't record new/resolved, so those are $null)
#   Resolved  every finding a scan resolved, with days from first seen to resolved. A scan records
#             only findings it really rechecked, so a failed query never counts as a fix.
#   Oldest    the findings open longest
# Amounts stay per currency, as everywhere else in the report.

# Monthly totals per currency, overall and for high confidence, from findings or findings.json rows
function Get-TrendTotals($items) {
    $all = @{}; $high = @{}
    foreach ($i in @($items | Where-Object { $null -ne $_ })) {
        $cost = Get-Key $i 'monthlyCost'
        if ($null -eq $cost) { continue }
        $cur = [string] (Get-Key $i 'currency')
        $all[$cur] = ($all[$cur] ?? 0) + [double] $cost
        if ((Get-Key $i 'confidence') -eq 'high') { $high[$cur] = ($high[$cur] ?? 0) + [double] $cost }
    }
    return @{ All = $all; High = $high }
}

function Get-MedianValue([double[]] $xs) {
    if (-not $xs) { return $null }
    $s = @($xs | Sort-Object); $n = $s.Count
    return ($n % 2) ? $s[($n - 1) / 2] : ($s[$n / 2 - 1] + $s[$n / 2]) / 2
}

function Get-DaysBetween([string] $from, [string] $to) {
    $f = [DateTime]::MinValue; $t = [DateTime]::MinValue
    $c = [Globalization.CultureInfo]::InvariantCulture
    if (-not [DateTime]::TryParseExact($from, 'yyyy-MM-dd', $c, 'None', [ref] $f) -or -not [DateTime]::TryParseExact($to, 'yyyy-MM-dd', $c, 'None', [ref] $t)) { return $null }
    return [int] ($t - $f).TotalDays
}

# $History: earlier scans, oldest first (@{ meta; json; dir }). Reads the current scan from the
# runner's $findings, $resolved and $today.
function Get-TrendData($History) {
    $scans = [Collections.Generic.List[object]]::new()
    $done = [Collections.Generic.List[object]]::new()
    $seen = [Collections.Generic.HashSet[string]]::new()
    $addResolved = {
        param($p, [string] $on)
        $k = "$(Get-Key $p 'key')|$on"
        if (-not $seen.Add($k)) { return }
        $first = [string] (Get-Key $p 'firstSeen')
        $done.Add([pscustomobject] @{ Name = [string] (Get-Key $p 'name'); WasteType = [string] (Get-Key $p 'wasteType'); Owner = [string] (Get-Key $p 'owner')
            FirstSeen = $first; ResolvedOn = $on; Days = (Get-DaysBetween $first $on); MonthlyCost = (Get-Key $p 'monthlyCost'); Currency = [string] (Get-Key $p 'currency') })
    }
    foreach ($h in @($History | Where-Object { $_ })) {
        $rows = @((Get-Key $h.json 'findings') | Where-Object { $null -ne $_ })
        $t = Get-TrendTotals $rows
        $ch = Get-Key $h.meta 'changes'
        $generated = [string] (Get-Key $h.meta 'generated')
        $scans.Add([pscustomobject] @{ Date = $generated.Substring(0, [math]::Min(10, $generated.Length)); Folder = (Split-Path $h.dir -Leaf); Findings = $rows.Count
            Totals = $t.All; High = $t.High; New = (Get-Key $ch 'new'); Resolved = (Get-Key $ch 'resolved'); Current = $false })
        foreach ($p in @((Get-Key $h.json 'resolved') | Where-Object { $null -ne $_ })) { & $addResolved $p ([string] (Get-Key $p 'resolvedOn')) }
    }
    $t = Get-TrendTotals $findings
    $scans.Add([pscustomobject] @{ Date = $today; Folder = (Split-Path $OutDir -Leaf); Findings = $findings.Count; Totals = $t.All; High = $t.High
        New = @($findings | Where-Object { $_.status -eq 'new' }).Count; Resolved = @($resolved).Count; Current = $true })
    foreach ($p in @($resolved | Where-Object { $null -ne $_ })) { & $addResolved $p $today }

    $timed = @($done | Where-Object { $null -ne $_.Days })
    $byOwner = @($timed | Group-Object { $_.Owner ? $_.Owner.Trim().ToLower() : '' } | ForEach-Object {
        [pscustomobject] @{ Owner = $_.Name; Count = $_.Count; MedianDays = (Get-MedianValue @($_.Group | ForEach-Object { [double] $_.Days })) } } |
        Sort-Object @{ e = { [bool] $_.Owner }; Descending = $true }, @{ e = 'MedianDays'; Descending = $true })
    $oldest = @($findings | Where-Object { $_.status -eq 'open' -and $_.firstSeen } | ForEach-Object {
        [pscustomobject] @{ Name = $_.name; WasteType = $_.wasteType; Owner = $_.owner; FirstSeen = $_.firstSeen; Days = (Get-DaysBetween $_.firstSeen $today)
                            MonthlyCost = $_.monthlyCost; Currency = $_.currency; Rank = [double] $_.rankValue } } |
        Sort-Object @{ e = 'Days'; Descending = $true }, @{ e = 'Rank'; Descending = $true } | Select-Object -First 10)
    return [pscustomobject] @{ Scans = @($scans); Resolved = @($done); MedianDays = (Get-MedianValue @($timed | ForEach-Object { [double] $_.Days }))
                               ResolvedTimed = $timed.Count; ByOwner = $byOwner; Oldest = $oldest }
}
