# Part of Invoke-WasteHunt.ps1 (dot-sourced into its scope, so it shares the runner's variables).
# READ-ONLY: see CLAUDE.md. Functions only; nothing runs when this file is loaded.

function Get-Key($o, [string] $k) { if ($o -is [System.Collections.IDictionary] -and $o.Contains($k)) { return $o[$k] }; return $null }

function Get-StatSum($stats, [string] $Name) { $x = $stats[$Name]; return $x ? [double] $x.Sum : 0.0 }

function Get-StatLast($stats, [string] $Name) { $x = $stats[$Name]; return ($x -and $null -ne $x.Last) ? [double] $x.Last : 0.0 }

function ConvertTo-GiB([string] $mem) {
    if ($mem -match '^\s*([\d.]+)\s*(Gi|G)?\s*$') { return [double] $Matches[1] }
    if ($mem -match '^\s*([\d.]+)\s*(Mi|M)\s*$') { return [double] $Matches[1] / 1024 }
    return 0.0
}

function Format-Bytes([double] $b) {
    if ($b -ge 1GB) { return '{0:N1} GiB' -f ($b / 1GB) }; if ($b -ge 1MB) { return '{0:N1} MiB' -f ($b / 1MB) }
    if ($b -ge 1KB) { return '{0:N0} KiB' -f ($b / 1KB) }; return '{0:N0} B' -f $b
}

function New-FindingFrom($row, [hashtable] $Set) {
    $f = [ordered]@{}; foreach ($k in $row.Keys) { if ($k -ne 'checkInputs') { $f[$k] = $row[$k] } }
    foreach ($k in $Set.Keys) { $f[$k] = $Set[$k] }
    return $f
}

function Step-Confidence([string] $c) { @{ low = 'medium'; medium = 'high'; high = 'high' }[$c] }

function Format-Day($v) { if (-not $v) { return '' }; try { [DateTimeOffset]::Parse([string] $v, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime.ToString('yyyy-MM-dd') } catch { [string] $v } }

function Get-FindingKey($f) { return "$($f.wasteType)|$(([string] $f.id).ToLower())" }

function Set-Exclusion($row) {
    if ([bool] $row.ignored) { if (-not (Get-Key $row 'excludedBy')) { $row['excludedBy'] = 'tag'; $row['excludeReason'] = 'waste-hunter:ignore=true' }; return }
    $rid = ([string] $row.id).ToLower()
    foreach ($x in $Exclusions) {
        if ($x.Types -and $row.wasteType -notin $x.Types) { continue }
        if (($x.Id -and $rid -eq $x.Id) -or ($x.Pattern -and $rid -like $x.Pattern)) {
            $row['ignored'] = $true; $row['excludedBy'] = 'file'; $row['excludeReason'] = $x.Reason; $row['excludeUntil'] = $x.Until
            $x.Hits++
            return
        }
    }
}
