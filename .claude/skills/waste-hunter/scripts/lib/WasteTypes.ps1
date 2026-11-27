# Part of Invoke-WasteHunt.ps1 (dot-sourced into its scope, so it shares the runner's variables).
# READ-ONLY: see CLAUDE.md. Functions only; nothing runs when this file is loaded.
#
# Waste types are records in scripts/types/NN-<name>.ps1, one file per query. Each file returns one
# or more hashtables:
#   Name                the wasteType the query (or a parent check) emits
#   Label               report heading
#   Order               report order (the query number; a derived type sits at parent + 0.5)
#   Candidate           $true: query rows are candidates, confirmed by Check against metrics
#   Parent              a type emitted by another type's Check (hot-blob-unread from idle-storage-account)
#   PartialSaving       the saving is a price difference, so billed cost is never used as the saving
#   CommitmentEligible  a reservation or savings plan can cover it (estimated costs get the caveat)
#   QuickWin            the fix is reversible or removes something nothing depends on, so a high-confidence
#                       finding of this type is listed under "Quick wins"
#   Collect             a type with no Resource Graph query: returns its rows (the shared column set)
#                       from other allowed reads, once per scan. Reservations use it.
#   Check               candidates only: 0..n findings from New-FindingFrom, or none when in use
#   LivePrice           @{ Cost; Note } from the Retail Prices API, or $null to fall back
#   Estimate            @{ Cost; Note } from pricing.json ($null Cost = unknown)
#   Action              @(<suggested action>, <reference command, text only>)
# The script blocks run inside the functions below and use the variables those set up (PowerShell
# resolves variables through the caller's scopes): $r, $ci, $young in Check; $f, $sku, $region, $rg,
# $red, $hours in LivePrice; $f, $sku in Estimate; $f, $who, $id in Action.

$WasteTypeKeys = @('Name', 'Label', 'Order', 'Candidate', 'Parent', 'PartialSaving', 'CommitmentEligible', 'QuickWin', 'Collect', 'Check', 'LivePrice', 'Estimate', 'Action')

# Loads and validates every record, ordered for the report. A malformed record stops the run.
function Import-WasteTypes([string] $Dir) {
    $all = [Collections.Generic.List[object]]::new()
    foreach ($file in @(Get-ChildItem $Dir -Filter '*.ps1' | Sort-Object Name)) {
        foreach ($rec in @(& $file.FullName)) {
            if (-not ($rec -is [hashtable])) { throw "$($file.Name): a waste-type file must return hashtables, got $($rec.GetType().Name)" }
            foreach ($k in $rec.Keys) { if ($k -notin $WasteTypeKeys) { throw "$($file.Name): unknown key '$k' in waste type '$($rec['Name'])'" } }
            foreach ($k in 'Name', 'Label', 'Order') { if (-not $rec[$k]) { throw "$($file.Name): waste type needs '$k'" } }
            foreach ($k in 'Check', 'LivePrice', 'Estimate', 'Action', 'Collect') { if ($rec.ContainsKey($k) -and -not ($rec[$k] -is [scriptblock])) { throw "$($file.Name): '$k' of '$($rec.Name)' must be a script block" } }
            if ($rec['Candidate'] -and -not $rec['Check']) { throw "$($file.Name): candidate type '$($rec.Name)' needs a Check" }
            if ($rec['Collect'] -and ($rec['Candidate'] -or $rec['Parent'])) { throw "$($file.Name): '$($rec.Name)' has Collect, so it can't also be a candidate or have a parent" }
            if (-not $rec['Action']) { throw "$($file.Name): waste type '$($rec.Name)' needs an Action" }
            $rec['File'] = $file.Name
            $all.Add($rec)
        }
    }
    $types = [ordered]@{}
    foreach ($rec in @($all | Sort-Object { [double] $_.Order }, { $_.Name })) {
        if ($types.Contains($rec.Name)) { throw "waste type '$($rec.Name)' is defined in both $($types[$rec.Name].File) and $($rec.File)" }
        $types[$rec.Name] = $rec
    }
    foreach ($rec in $types.Values) { if ($rec['Parent'] -and -not $types.Contains($rec.Parent)) { throw "$($rec.File): parent '$($rec.Parent)' of '$($rec.Name)' is not defined" } }
    return $types
}

# Metric-confirmed candidates (records with Candidate): each query row becomes 0..n findings, or
# none when the metrics show it's in use.
function Confirm-Candidate($r) {
    $ci = (Get-Key $r 'checkInputs') ?? @{}
    $young = ($null -ne $r.ageDays -and [int] $r.ageDays -lt $MinAgeDays)
    $t = $WasteTypes[[string] $r.wasteType]
    if (-not $t -or -not $t['Check']) { return @() }
    return & $t.Check
}

# Monthly list price in the resource's own region, from the Retail Prices API. $null means no
# regional price was found, so the caller falls back to Get-Estimate.
function Get-LivePrice($f) {
    $region = ([string] $f.location).ToLower()
    if ($script:PriceApiDown -or -not $region -or $region -eq 'global') { return $null }
    $sku = [string] $f.sku; $rg = Get-ODataLiteral $region; $hours = $Pricing.hoursPerMonth
    $red = ($sku -like '*_ZRS') ? 'ZRS' : 'LRS'
    $t = $WasteTypes[[string] $f.wasteType]
    if (-not $t -or -not $t['LivePrice']) { return $null }
    $res = & $t.LivePrice
    return $res ? $res : $null
}

# List price from pricing.json (US East, USD)
function Get-Estimate($f) {
    $sku = [string] $f.sku
    $t = $WasteTypes[[string] $f.wasteType]
    if ($t -and $t['Estimate']) {
        $res = & $t.Estimate
        if ($res) { return $res }
    }
    return @{ Cost = $null; Note = '' }
}

# Suggested action and reference command (text only: never executed)
function Get-Action($f) {
    $who = $f.owner ? "the owner ($($f.owner))" : 'the resource group owner'
    $id = $f.id
    $t = $WasteTypes[[string] $f.wasteType]
    if ($t) { return & $t.Action }
}
