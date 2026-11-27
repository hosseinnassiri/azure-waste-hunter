# Part of Invoke-WasteHunt.ps1 (dot-sourced into its scope, so it shares the runner's variables).
# READ-ONLY: see CLAUDE.md. Functions only; nothing runs when this file is loaded.

function Invoke-AzRead {
    param([Parameter(Mandatory)] [string[]] $AzArgs)

    $lead = foreach ($a in $AzArgs) { if ($a.StartsWith('-')) { break }; $a }
    $cmd  = @($lead) -join ' '
    if ($cmd -notin $AllowedAz) { throw "Refusing non-read-only az command: 'az $cmd'" }

    # Metrics responses are cached for the run ($Now is fixed, so the same arguments mean the same
    # window). Two Premium disks on one VM, for example, need its CPU history only once. Checks run in
    # parallel, so the first caller for a key fetches and later callers wait for its result; if the
    # fetch fails, the entry is removed and a waiter fetches for itself.
    $cacheKey = ($cmd -eq 'monitor metrics list') ? ($AzArgs -join "`u{1f}") : $null
    $entry = $null
    while ($cacheKey) {
        $mine = @{ Ready = [Threading.ManualResetEventSlim]::new($false); Res = $null }
        if ($MetricCache.TryAdd($cacheKey, $mine)) { $entry = $mine; break }
        $other = $null
        if ($MetricCache.TryGetValue($cacheKey, [ref] $other)) {
            $other.Ready.Wait()
            if ($other.Res) {
                $AzEvents.Enqueue('cached')
                if ($other.Res.Empty) { return $null }
                return $other.Res.Value
            }
        }
    }

    try {
        for ($attempt = 1; ; $attempt++) {
            $AzEvents.Enqueue('call')
            $res = $FixtureDir ? (Invoke-AzFixture $cmd $AzArgs) : (Invoke-AzProcess $AzArgs)
            if ($res.Code -eq 0) {
                if ($entry) { $entry.Res = $res }
                if ($res.Empty) { return $null }
                # Value is always an array, and returning it unrolls it: a JSON array reaches the caller's
                # @() as its elements, never as one nested array (which made every Where-Object match).
                return $res.Value
            }
            $wait = Get-AzRetryDelay $res.Err $attempt
            if ($null -eq $wait) { throw "az $cmd failed (exit $($res.Code)): $(Get-AzErrorSummary $res.Err $cmd)" }
            $AzEvents.Enqueue("retry|$cmd")
            Start-Sleep -Milliseconds ([int] ($wait * 1000))
        }
    }
    finally {
        if ($entry) {
            if (-not $entry.Res) { $gone = $null; [void] $MetricCache.TryRemove($cacheKey, [ref] $gone) }
            $entry.Ready.Set()
        }
    }
}

function Invoke-AzProcess([string[]] $AzArgs) {
    $errFile = [IO.Path]::GetTempFileName()
    try {
        $out  = & az @AzArgs --only-show-errors -o json 2> $errFile
        $code = $LASTEXITCODE
        $err  = (Get-Content $errFile -Raw -ErrorAction SilentlyContinue) ?? ''
        if ($code -ne 0) { return @{ Code = $code; Err = $err } }
        $text = ($out -join "`n").Trim()
        if (-not $text) { return @{ Code = 0; Empty = $true; Value = @() } }
        return @{ Code = 0; Empty = $false; Value = @($text | ConvertFrom-Json -AsHashtable -Depth 64 -DateKind String) }
    }
    finally { Remove-Item $errFile -ErrorAction SilentlyContinue }
}

function Get-AzRetryDelay([string] $Err, [int] $Attempt) {
    if ($Attempt -ge $AzMaxAttempts) { return $null }
    if ($Err -match '(?i)AADSTS|AuthorizationFailed|InvalidAuthenticationToken|\(Forbidden\)|az login|BadRequest|InvalidQuery|ResourceNotFound|NotFound\)') { return $null }
    if ($Err -notmatch '(?i)\b429\b|TooManyRequests|Too Many Requests|RateLimit|throttl|\b50[234]\b|ServiceUnavailable|InternalServerError|GatewayTimeout|BadGateway|timed out|Connection (aborted|reset)|RemoteDisconnected') { return $null }
    if ($RetryBaseSeconds -le 0) { return 0.0 }   # fixture runs: retry at once
    # Exponential backoff with jitter, so parallel checks throttled together don't retry in lockstep
    $wait = $RetryBaseSeconds * [math]::Pow(2, $Attempt - 1) + (Get-Random -Minimum 0.0 -Maximum ($RetryBaseSeconds / 2))
    if ($Err -match '(?i)retry after (\d+)') { $wait = [math]::Max($wait, [int] $Matches[1]) }
    return [math]::Min(30.0, $wait)
}

function Get-AzErrorSummary([string] $Err, [string] $Cmd) {
    $lines = @($Err -split '\r?\n' | Where-Object { $_.Trim() })
    $msg = (@($lines | Where-Object { $_ -match 'ERROR|AADSTS|message' } | Select-Object -First 3)) -join ' '
    if (-not $msg) { $msg = (@($lines | Select-Object -First 2)) -join ' ' }
    # 'az graph' comes from a CLI extension. Without it az says the command is "misspelled" (or, with
    # dynamic install on, prompts and fails reading stdin), neither of which names the fix.
    if ($Cmd -like 'graph *' -and $Err -match "(?i)misspelled or not recognized|requires the extension|EOF when reading a line") {
        $msg += " The Azure CLI 'resource-graph' extension isn't installed. Install it yourself with: az extension add -n resource-graph"
    }
    return $msg
}

function Invoke-AzFixture([string] $cmd, [string[]] $AzArgs) {
    $joined = $AzArgs -join ' '; $t = 0
    foreach ($f in $FixtureFaults) {
        if ($f.Cmd -eq $cmd -and $joined.Contains($f.Match) -and $f.Tokens.TryDequeue([ref] $t)) { return @{ Code = 1; Err = $f.Stderr } }
    }
    $v = @(Get-FixtureResponse $cmd $AzArgs)
    # Same shape as a real response: a $null answer is Empty (returns $null), @() returns nothing
    return @{ Code = 0; Empty = ($v.Count -eq 1 -and $null -eq $v[0]); Value = $v }
}

function Get-FixtureResponse([string] $cmd, [string[]] $AzArgs) {
    $read = { param($f) $p = Join-Path $FixtureDir $f; if (Test-Path $p) { Get-Content $p -Raw | ConvertFrom-Json -AsHashtable -DateKind String } }
    switch ($cmd) {
        'account show' { return & $read 'account.json' }
        'account list' { return @(& $read 'accounts.json') }
        'account set'  { return $null }
        'graph query'  {
            $q = $AzArgs[[array]::IndexOf($AzArgs, '-q') + 1].TrimStart('@')
            $rows = @(& $read ([IO.Path]::GetFileNameWithoutExtension($q) + '.json'))
            return @{ count = $rows.Count; data = $rows; skip_token = $null }
        }
        'monitor metrics list' {
            # Keyed "<resource id>|<first metric name>" (lower case), falling back to "<resource id>"
            $id = $AzArgs[[array]::IndexOf($AzArgs, '--resource') + 1].ToLower()
            $metric = $AzArgs[[array]::IndexOf($AzArgs, '--metric') + 1].ToLower()
            $m = $null   # parsed once per run ($FixtureCache): Get-MetricStats only reads it
            if (-not $FixtureCache.TryGetValue('metrics.json', [ref] $m)) { $m = Expand-FixtureSeries (& $read 'metrics.json'); [void] $FixtureCache.TryAdd('metrics.json', $m) }
            if ($m) { foreach ($k in "$id|$metric", $id) { if ($m.ContainsKey($k)) { return $m[$k] } } }
            return @{ value = @() }
        }
        'cognitiveservices account deployment list' {
            # Keyed "<resource group>/<account name>" (lower case)
            $key = ($AzArgs[[array]::IndexOf($AzArgs, '-g') + 1] + '/' + $AzArgs[[array]::IndexOf($AzArgs, '-n') + 1]).ToLower()
            $d = & $read 'deployments.json'
            return ($d -and $d.ContainsKey($key)) ? @($d[$key]) : @()
        }
        'consumption reservation summary list' {
            # Keyed by reservation order ID (lower case): that order's daily summary records
            $o = $AzArgs[[array]::IndexOf($AzArgs, '--reservation-order-id') + 1].ToLower()
            $d = & $read 'reservations.json'
            if (-not ($d -and $d.ContainsKey($o))) { throw "fixture: no reservation order $o" }
            return @($d[$o])
        }
        'consumption usage list' {
            $sub = $AzArgs[[array]::IndexOf($AzArgs, '--subscription') + 1]
            return @(@(& $read 'consumption.json') | Where-Object { $_ -and $_.instanceId -like "/subscriptions/$sub/*" })
        }
    }
}

# Fixture mode: long hourly series are stored in metrics.json as a description,
# { hourly = { agg, count, lo, hi, end } }, written by TsHours in tests/New-Fixtures.ps1, and expanded
# here into the points az would return: <count> hourly points ending at <end>, cycling between lo and hi.
function Expand-FixtureSeries($Metrics) {
    if (-not $Metrics) { return $Metrics }
    foreach ($resp in @($Metrics.Values)) {
        foreach ($v in @(Get-Key $resp 'value')) {
            foreach ($ts in @(Get-Key $v 'timeseries')) {
                $h = Get-Key $ts 'hourly'
                if (-not $h) { continue }
                $n = [int] $h['count']; $lo = [double] $h['lo']; $hi = [double] $h['hi']; $agg = [string] $h['agg']
                $end = [DateTime]::Parse([string] $h['end'], [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
                $start = $end.AddHours(-$n)
                $ts['data'] = @(for ($i = 0; $i -lt $n; $i++) {
                    @{ timeStamp = $start.AddHours($i).ToString('yyyy-MM-ddTHH:00:00Z'); $agg = $lo + ($hi - $lo) * (($i * 7) % 20) / 19 } })
                [void] $ts.Remove('hourly')
            }
        }
    }
    return $Metrics
}

function Invoke-GraphQuery([string] $QueryFile, [string[]] $Subscriptions, [string] $MgId) {
    $rows = [Collections.Generic.List[object]]::new()
    $skip = $null
    do {
        $a = @('graph', 'query', '-q', "@$QueryFile", '--first', '1000')
        if ($MgId) { $a += @('--management-groups', $MgId) }
        elseif ($Subscriptions) { $a += '--subscriptions'; $a += $Subscriptions }
        if ($skip) { $a += @('--skip-token', $skip) }
        $res = Invoke-AzRead $a
        foreach ($r in @($res.data)) { if ($null -ne $r) { $rows.Add($r) } }
        $skip = $res.skip_token
    } while ($skip)
    return , $rows
}

# Runs a function over items, -Parallel at a time, and returns one result per item in input order:
# @{ Value = <the function's output>; Error = <message or $null> }. Each runspace loads the lib/ and
# types/ files itself and gets the variables in $vars, and every az call still goes through
# Invoke-AzRead and its allow list.
function Invoke-InParallel([object[]] $Items, [string] $Function) {
    $Items = @($Items | Where-Object { $null -ne $_ })
    if (-not $Items) { return }
    if ($Parallel -le 1) {
        foreach ($it in $Items) {
            try { [pscustomobject] @{ Value = @(& $Function $it); Error = $null } }
            catch { [pscustomobject] @{ Value = @(); Error = $_.Exception.Message } }
        }
        return
    }
    $vars = @{ Now = $Now; MinAgeDays = $MinAgeDays; FixtureDir = $FixtureDir; AllowedAz = $AllowedAz; AzEvents = $AzEvents; MetricCache = $MetricCache
               FixtureFaults = $FixtureFaults; FixtureCache = $FixtureCache; RetryBaseSeconds = $RetryBaseSeconds; AzMaxAttempts = $AzMaxAttempts; Pricing = $Pricing }
    $indexed = for ($i = 0; $i -lt $Items.Count; $i++) { [pscustomobject] @{ I = $i; Item = $Items[$i] } }
    $out = @($indexed | ForEach-Object -ThrottleLimit $Parallel -Parallel {
        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'
        $job = $_
        foreach ($kv in ($using:vars).GetEnumerator()) { Set-Variable -Name $kv.Key -Value $kv.Value }
        # The same lib/ and types/ files the runner loaded, so checks run the same code. Script blocks
        # belong to the runspace that created them, so each runspace loads its own copy.
        foreach ($lib in $using:LibFiles) { . $lib }
        $WasteTypes = Import-WasteTypes $using:TypesDir
        try { [pscustomobject] @{ I = $job.I; Value = @(& $using:Function $job.Item); Error = $null } }
        catch { [pscustomobject] @{ I = $job.I; Value = @(); Error = $_.Exception.Message } }
    })
    foreach ($r in @($out | Sort-Object I)) { [pscustomobject] @{ Value = $r.Value; Error = $r.Error } }
}
