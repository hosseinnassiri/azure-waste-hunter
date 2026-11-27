# Helpers for Test-WasteHunt.ps1. Dot-sourced by the suite and by each parallel worker that runs
# scenario tests, so both use the same code. They read $Work, $Fixtures, $Runner and (Copy-BaseRun)
# $base from the caller's scope.

function Assert([bool] $Cond, [string] $Msg) { if (-not $Cond) { throw $Msg } }
function Assert-Equal($Expected, $Actual, [string] $What) { if ("$Expected" -ne "$Actual") { throw "$What`: expected [$Expected], got [$Actual]" } }

# A finished report folder's parsed outputs
function Read-Run([string] $Dir, [string] $Log = '') {
    return [pscustomobject] @{
        Dir = $Dir; Log = $Log
        Report = Get-Content (Join-Path $Dir 'report.md') -Raw
        Html = Get-Content (Join-Path $Dir 'report.html') -Raw
        Rows = @(Import-Csv (Join-Path $Dir 'findings.csv'))
        Json = Get-Content (Join-Path $Dir 'findings.json') -Raw | ConvertFrom-Json -AsHashtable
    }
}

# Run the runner on a fixture folder; returns the report folder's parsed outputs.
# Each run gets its own parent folder, so runs never compare against each other unless a test passes
# a shared -Parent on purpose (the "Changes" tests).
function Invoke-Run([string] $FixtureDir, [string] $Name, [string[]] $Extra = @(), [string] $Parent, [switch] $KeepParallel) {
    if (-not $Parent) { $Parent = Join-Path $Work "run-$Name" }
    $out = Join-Path $Parent $Name
    # Fixture az calls answer instantly, so parallel metric checks only add runspace setup (about 6 s a
    # run). Runs are sequential unless they ask otherwise. The base run and the retry runs keep the
    # default, and 'Parallel: ...' compares the base run with a sequential one, so a variable missing
    # from Invoke-InParallel's $vars still fails the suite.
    if (-not $KeepParallel -and $Extra -notcontains '-Parallel') { $Extra = @($Extra) + @('-Parallel', '1') }
    $log = & pwsh -NoProfile -File $Runner -FixtureDir $FixtureDir -OfflinePricing -OutDir $out @Extra 2>&1
    if ($LASTEXITCODE -ne 0) { throw "runner exited $LASTEXITCODE`n$($log | Select-Object -Last 15 | Out-String)" }
    return Read-Run $out ($log | Out-String)
}

# A first scan of the unmodified fixtures, for tests that compare a later scan with it: a copy of the
# base run (the same scan) under $Parent\$Name, instead of running it again. A later scan finds earlier
# reports by their findings.json (scope, synthetic, generated time), not by how the folder was made.
function Copy-BaseRun([string] $Parent, [string] $Name) {
    New-Item -ItemType Directory -Force $Parent | Out-Null
    $out = Join-Path $Parent $Name
    Copy-Item -Recurse $base.Dir $out
    return Read-Run $out
}

function Get-Row($run, [string] $name) {
    $r = @($run.Rows | Where-Object { $_.name -eq $name })
    Assert ($r.Count -eq 1) "expected exactly one finding named '$name', found $($r.Count)"
    return $r[0]
}

# Copy the fixtures so a test can change them without touching the committed ones
function Copy-Fixtures([string] $Name) { $d = Join-Path $Work "fx-$Name"; Copy-Item -Recurse $Fixtures $d; return $d }
function Edit-Fixture([string] $Dir, [string] $File, [scriptblock] $Change) {
    $p = Join-Path $Dir $File
    $data = @(Get-Content $p -Raw | ConvertFrom-Json)
    $data = @(& $Change $data)
    ConvertTo-Json -InputObject $data -Depth 12 | Set-Content $p
}

# Retry and caching. Fixture faults (faults.json) make the first N matching az calls fail with a
# given stderr, which exercises the same retry path a real az error takes.
function Set-Faults([string] $Dir, [object[]] $Faults) { ConvertTo-Json -InputObject @($Faults) -Depth 5 | Set-Content (Join-Path $Dir 'faults.json') }
function Get-AzStats($run) {
    Assert ($run.Report -match 'az calls: (\d+), (\d+) retried.*?, (\d+) metric read') 'az calls line missing from the report'
    return @{ Calls = [int] $Matches[1]; Retried = [int] $Matches[2]; Cached = [int] $Matches[3] }
}
