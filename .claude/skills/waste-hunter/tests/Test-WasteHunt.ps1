#requires -Version 7.5
<#
.SYNOPSIS
    Offline test suite for azure-waste-hunter. No Azure, no network, no dependencies.

.DESCRIPTION
    Static checks on the queries, guard and skill file, then full runner passes over the synthetic
    fixtures with -OfflinePricing (deterministic prices from pricing.json). Several tests pin bugs
    found during development, which all failed silently, so they must never come back:
      - unreadable subscriptions reported as clean           (Coverage: ...)
      - nested arrays making every filter match everything   (Coverage: disabled subscription ...)
      - metrics clipped to 30 days                           (Idle: ... second 30-day window)
      - $0 in SKILL.md replaced by the invocation arguments  (Skill: ...)
      - a failed check reported as "resolved"                (Changes: ...)

    Exit code: 0 when everything passes, 1 otherwise.
.EXAMPLE
    pwsh ./.claude/skills/waste-hunter/tests/Test-WasteHunt.ps1
#>
[CmdletBinding()] param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$TestsDir = $PSScriptRoot
$SkillDir = Split-Path -Parent $TestsDir
$RepoDir  = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $SkillDir))
$Runner   = Join-Path $SkillDir 'scripts/Invoke-WasteHunt.ps1'
$Fixtures = Join-Path $TestsDir 'fixtures'
$Work     = Join-Path ([IO.Path]::GetTempPath()) ("waste-hunter-tests-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory $Work | Out-Null

$script:Passed = 0; $script:Failed = [Collections.Generic.List[string]]::new()
function Test([string] $Name, [scriptblock] $Body) {
    try { & $Body; $script:Passed++; Write-Host "  ok    $Name" -ForegroundColor Green }
    catch { $script:Failed.Add("$Name :: $($_.Exception.Message)"); Write-Host "  FAIL  $Name`n        $($_.Exception.Message)" -ForegroundColor Red }
}
function Assert([bool] $Cond, [string] $Msg) { if (-not $Cond) { throw $Msg } }
function Assert-Equal($Expected, $Actual, [string] $What) { if ("$Expected" -ne "$Actual") { throw "$What`: expected [$Expected], got [$Actual]" } }

# Run the runner on a fixture folder; returns the report folder's parsed outputs
# Each run gets its own parent folder, so runs never compare against each other unless a test passes
# a shared -Parent on purpose (the "Changes" tests).
function Invoke-Run([string] $FixtureDir, [string] $Name, [string[]] $Extra = @(), [string] $Parent) {
    if (-not $Parent) { $Parent = Join-Path $Work "run-$Name" }
    $out = Join-Path $Parent $Name
    $log = & pwsh -NoProfile -File $Runner -FixtureDir $FixtureDir -OfflinePricing -OutDir $out @Extra 2>&1
    if ($LASTEXITCODE -ne 0) { throw "runner exited $LASTEXITCODE`n$($log | Select-Object -Last 15 | Out-String)" }
    return [pscustomobject] @{
        Dir = $out; Log = ($log | Out-String)
        Report = Get-Content (Join-Path $out 'report.md') -Raw
        Html = Get-Content (Join-Path $out 'report.html') -Raw
        Rows = @(Import-Csv (Join-Path $out 'findings.csv'))
        Json = Get-Content (Join-Path $out 'findings.json') -Raw | ConvertFrom-Json -AsHashtable
    }
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

try {
    Write-Host 'Static checks'
    $queries = @(Get-ChildItem (Join-Path $SkillDir 'queries') -Filter '*.kql')
    $required = 'wasteType', 'id', 'name', 'type', 'tenantId', 'subscriptionId', 'resourceGroup', 'location', 'owner', 'app', 'env',
                'createdTime', 'ageDays', 'idleDays', 'idleSource', 'sku', 'tier', 'sizeGb', 'os', 'extra', 'confidence', 'reason', 'ignored'

    Test 'Queries: every file is marked read-only and uses the shared column set' {
        Assert ($queries.Count -ge 19) "expected 19+ queries, found $($queries.Count)"
        foreach ($q in $queries) {
            $t = Get-Content $q.FullName -Raw
            Assert ($t -match 'READ-ONLY') "$($q.Name) has no READ-ONLY note"
            $last = $t.Substring($t.LastIndexOf('| project'))
            foreach ($c in $required) { Assert ($last -match "(?<![\w.])$c\b") "$($q.Name): final project is missing '$c'" }
        }
    }
    Test 'Queries: never project properties or tags wholesale (no secrets in output)' {
        foreach ($q in $queries) {
            $code = (Get-Content $q.FullName | ForEach-Object { ($_ -replace '//.*$', '') }) -join "`n"
            $code = $code -replace "'[^']*'", "''"                      # ignore string literals
            Assert ($code -notmatch '\bproperties\b(?![.\[])') "$($q.Name) uses 'properties' without a field path"
            $noTostring = $code -replace 'tostring\(tags\)', '' -replace 'rTags = tags', '' -replace 'tags = rTags', ''
            Assert ($noTostring -notmatch '\btags\b(?![\[.])') "$($q.Name) projects 'tags' wholesale"
        }
    }
    Test 'Queries: candidate checkInputs never carry env vars, settings or secrets' {
        foreach ($q in $queries) {
            $t = Get-Content $q.FullName -Raw
            if ($t -notmatch 'checkInputs\s*=\s*pack\(([\s\S]*?)\)\s*$') { continue }
            # pack('key', value, 'key', value ...): check the key names
            $keys = @([regex]::Matches($Matches[1], "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
            foreach ($k in $keys) { Assert ($k -notmatch '(?i)^env|secret|password|connectionstring|setting|apikey|token') "$($q.Name) checkInputs key '$k' looks sensitive" }
            Assert ($Matches[1] -notmatch '(?i)\.env\b|appSettings|connectionStrings|secrets') "$($q.Name) checkInputs reads a sensitive property"
        }
    }
    Test 'Guard: allow list is exactly the read-only command set' {
        $src = Get-Content $Runner -Raw
        Assert ($src -match '\$AllowedAz = @\(([\s\S]*?)\n\)') 'AllowedAz block not found'
        $body = ($Matches[1] -split "`n" | ForEach-Object { $_ -replace '#.*$', '' }) -join "`n"   # comments may contain apostrophes
        $cmds = @([regex]::Matches($body, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value }) | Sort-Object
        $expected = @('account list', 'account set', 'account show', 'advisor recommendation list', 'cognitiveservices account deployment list',
                      'consumption usage list', 'graph query', 'monitor metrics list') | Sort-Object
        Assert-Equal ($expected -join ', ') ($cmds -join ', ') 'allowed az commands'
    }
    Test 'Guard: az is only ever invoked inside Invoke-AzRead' {
        $src = Get-Content $Runner -Raw
        Assert-Equal 1 ([regex]::Matches($src, '&\s*az\s')).Count 'number of direct az invocations'
        Assert ($src -notmatch 'Invoke-Expression|\biex\b|Start-Process\s+az') 'runner must not shell out to az any other way'
    }
    Test 'Guard: the only external endpoint is the Retail Prices API, by GET' {
        $src = Get-Content $Runner -Raw
        $urls = @([regex]::Matches($src, 'https://[a-z0-9.-]+') | ForEach-Object { $_.Value } | Sort-Object -Unique)
        foreach ($u in $urls) { Assert ($u -in 'https://prices.azure.com', 'https://portal.azure.com') "unexpected endpoint $u" }
        Assert ($src -notmatch "Invoke-RestMethod[^\n]*-Method\s+(Post|Put|Patch|Delete)") 'price API must be GET only'
    }
    Test 'Skill: frontmatter has name and description, and no $0/$1/$ARGUMENTS placeholders' {
        $s = Get-Content (Join-Path $SkillDir 'SKILL.md') -Raw
        Assert ($s -match '(?s)^---\s*\nname:\s*waste-hunter\s*\ndescription:\s*\S.+?\n---') 'frontmatter name/description missing'
        Assert ($s -notmatch '\$(\d|ARGUMENTS)') 'SKILL.md contains a $-placeholder the skill loader would replace'
    }
    Test 'Settings: deny rules cover write and secret-reading az commands' {
        $deny = @((Get-Content (Join-Path $RepoDir '.claude/settings.json') -Raw | ConvertFrom-Json).permissions.deny)
        foreach ($p in 'Bash(az * delete *)', 'PowerShell(az * delete *)', 'Bash(az rest *)', 'Bash(az keyvault secret *)', 'Bash(az * deallocate *)') {
            Assert ($p -in $deny) "missing deny rule $p"
        }
    }
    Test 'Settings: deny rules block writes, secrets and shells but never the allowed reads' {
        $deny = @((Get-Content (Join-Path $RepoDir '.claude/settings.json') -Raw | ConvertFrom-Json).permissions.deny)
        # A rule's * matches any text, spaces included
        $rx = @($deny | Where-Object { $_ -like 'Bash(*)' } | ForEach-Object { '^' + ([regex]::Escape($_.Substring(5, $_.Length - 6)) -replace '\\\*', '.*') + '$' })
        $blocked = { param($cmd) @($rx | Where-Object { $cmd -match $_ }).Count -gt 0 }
        $reads = @(
            'az graph query -q @C:/repo/.claude/skills/waste-hunter/queries/01-unattached-disks.kql --first 5 --query count -o tsv'
            'az monitor metrics list --resource /subscriptions/0000/resourceGroups/rg-backup-restore/providers/Microsoft.Compute/virtualMachines/vm-setup --metric "Percentage CPU" --interval P1D --aggregation Maximum'
            'az advisor recommendation list --category Cost'
            'az consumption usage list --subscription 0000 --start-date 2026-10-27 --end-date 2026-11-26'
            'az cognitiveservices account deployment list -g rg-ml -n oai-research --subscription 0000'
            'az account show', 'az account list --all', 'az account set --subscription 0000-1111'
            'az extension show -n resource-graph', 'az extension add -n resource-graph')     # add: local CLI change, asked first (SKILL.md)
        foreach ($c in $reads) { Assert (-not (& $blocked $c)) "deny rules block an allowed read: $c" }
        $writes = @(
            'az webapp config appsettings set -g rg -n app --settings X=1', 'az keyvault set-policy -n kv --upn x', 'az network nic ip-config add -g rg --nic-name n -n c'
            'az vm identity assign -g rg -n vm', 'az acr import -n cr --source x', 'az vm disk attach -g rg --vm-name vm --name d', 'az webapp deployment slot swap -g rg -n app --slot s'
            'az sql db restore -g rg -s srv -n db', 'az aks upgrade -g rg -n aks', 'az webapp up', 'az webapp deploy -g rg -n app --src-path x.zip', 'az containerapp secret list -g rg -n ca --show-values'
            'az storage account keys renew -g rg -n st --key primary', 'az cosmosdb keys regenerate -g rg -n db --key-kind primary', 'az storage blob upload -f x -c c -n n'
            'az storage blob download -c c -n n -f x', 'az containerapp exec -g rg -n ca', 'az ssh vm -g rg -n vm', 'az network bastion ssh -n bas -g rg --target-resource-id x')
        foreach ($c in $writes) { Assert (& $blocked $c) "deny rules do not block: $c" }
        foreach ($b in @($deny | Where-Object { $_ -like 'Bash(*)' })) { Assert ("PowerShell$($b.Substring(4))" -in $deny) "no PowerShell twin for $b" }
    }
    Test 'Pricing: pricing.json parses and has every section the runner reads' {
        $p = Get-Content (Join-Path $SkillDir 'scripts/pricing.json') -Raw | ConvertFrom-Json -AsHashtable
        foreach ($k in 'disks', 'snapshotsPerGb', 'publicIps', 'appServicePlans', 'containerApps', 'storagePerGb', 'containerRegistries', 'openAI', 'network', 'sqlDatabase', 'vms') {
            Assert ($p.ContainsKey($k)) "pricing.json has no '$k'"
        }
    }

    Write-Host 'Full run on synthetic fixtures (offline pricing)'
    $base = Invoke-Run $Fixtures 'base'
    $expected = @(
        'advisor-cost|demo-prod', 'advisor-cost|vm-api-01', 'empty-app-service-plan|asp-legacy-api', 'empty-app-service-plan|asp-playground',
        'empty-app-service-plan|asp-reports-weu', 'empty-resource-group|rg-old-poc', 'hot-blob-unread|stmediaarchive', 'idle-application-gateway|agw-legacy-portal',
        'idle-bastion|bas-dev', 'idle-container-app|ca-orders-legacy', 'idle-container-app|ca-queue-worker', 'idle-container-registry|crgraphapps',
        'idle-container-registry|crlegacybuild', 'idle-load-balancer|lb-empty-scratch', 'idle-load-balancer|lb-old-web', 'idle-network-gateway|erc-pending-dc2',
        'idle-network-gateway|nat-dev-unused', 'idle-network-gateway|vpngw-old-branch', 'idle-openai-deployment|oai-research/gpt-4o-mini-support-ft',
        'idle-openai-deployment|oai-research/gpt-ptu-eval', 'idle-sql-database|sql-legacy/reporting-old', 'idle-storage-account|stgraphdata',
        'idle-storage-account|stlegacyexports', 'log-analytics-workspace|log-security-archive', 'old-snapshot|snap-sql-pre-upgrade-2025',
        'old-snapshot|snap-vm-old01-osdisk', 'orphaned-nic|aks-nodepool1-nic-7', 'orphaned-nic|nic-vm-old01', 'oversized-container-registry|crplatform',
        'premium-disk-deallocated-vm|vm-retired-app_OsDisk', 'unassociated-public-ip|pip-old-lb-frontend', 'unassociated-public-ip|pip-test-dyn',
        'unassociated-public-ip|pip-vm-old01', 'unattached-disk|asrseeddisk-web01-a1b2c3', 'unattached-disk|disk-sql-data-old', 'unattached-disk|disk-temp-build',
        'vm-stopped-not-deallocated|vm-build-agent-02', 'vm-stopped-not-deallocated|vm-win-jumpbox')

    Test 'Findings: exactly the expected set (every flag and every drop is intentional)' {
        $got = @($base.Rows | ForEach-Object { "$($_.wasteType)|$($_.name)" } | Sort-Object)
        $missing = @($expected | Where-Object { $_ -notin $got }); $extra = @($got | Where-Object { $_ -notin $expected })
        Assert (-not $missing -and -not $extra) "missing: $($missing -join ', ') | unexpected: $($extra -join ', ')"
    }
    Test 'Metric checks: candidates that are in use are dropped, not reported' {
        foreach ($n in 'ca-api-busy', 'log-app-prod', 'stwebassets', 'oai-research/gpt-ptu-prod', 'oai-research/gpt-4o-chat', 'bas-prod', 'sql-app/orders', 'vm-weekend-batch_data') {
            Assert (-not ($base.Rows | Where-Object { $_.name -eq $n })) "$n is in use but was reported"
        }
    }
    Test 'Exclusions: ignore-tagged resources are skipped and counted' {
        foreach ($n in 'disk-keep-forensics', 'stkeepforaudit', 'vm-gpu-train') { Assert (-not ($base.Rows | Where-Object { $_.name -eq $n })) "$n is tagged ignore but was reported" }
        Assert ($base.Report -match '3 resource\(s\) excluded') 'excluded count should be 3'
    }
    Test 'Confidence: possible data stores and dependencies are low, never high' {
        Assert-Equal 'low' (Get-Row $base 'stgraphdata').confidence 'stgraphdata (Azure Files mount in the same RG)'
        Assert-Equal 'low' (Get-Row $base 'crgraphapps').confidence 'crgraphapps (referenced by a Container App)'
        Assert ((Get-Row $base 'stgraphdata').suggestedAction -match 'Do NOT delete') 'stgraphdata action must say do not delete'
        Assert-Equal 'low' (Get-Row $base 'lb-empty-scratch').confidence 'rule-less load balancer'
        Assert-Equal 'medium' (Get-Row $base 'ca-queue-worker').confidence 'Container App without HTTP ingress'
        Assert-Equal 'high' (Get-Row $base 'vm-retired-app_OsDisk').confidence 'premium disk on a VM off 90+ days'
    }
    Test 'Costs: deterministic offline prices and billed costs' {
        $cases = [ordered]@{ 'vm-win-jumpbox' = '97.53'; 'nat-dev-unused' = '32.85'; 'sql-legacy/reporting-old' = '147.17'; 'lb-old-web' = '18.25'
                             'vm-build-agent-02' = '276.48'; 'oai-research/gpt-ptu-eval' = '10950'; 'ca-orders-legacy' = '46.66'; 'crlegacybuild' = '100'
                             'disk-sql-data-old' = '135.18'; 'asp-legacy-api' = '248.2' }
        foreach ($k in $cases.Keys) { Assert-Equal $cases[$k] (Get-Row $base $k).monthlyCost "$k monthly cost" }
        Assert ((Get-Row $base 'vm-build-agent-02').costSource -like 'billed*') 'vm-build-agent-02 should use billed cost'
        Assert ((Get-Row $base 'asp-legacy-api').costSource -eq 'advisor') 'asp-legacy-api should use the merged Advisor figure'
        Assert-Equal '' (Get-Row $base 'log-security-archive').monthlyCost 'Log Analytics cost (must be unknown, not 0)'
    }
    Test 'Advisor: a recommendation for an already-found resource is merged, not listed twice' {
        Assert (-not ($base.Rows | Where-Object { $_.wasteType -eq 'advisor-cost' -and $_.name -eq 'asp-legacy-api' })) 'asp-legacy-api appears twice'
        Assert ((Get-Row $base 'asp-legacy-api').reason -match 'corroborated by Advisor') 'merged finding should say corroborated by Advisor'
    }
    Test 'Idle: VM idle time comes from the second 30-day metrics window (no 30-day clipping)' {
        Assert-Equal '47' (Get-Row $base 'vm-build-agent-02').idleDays 'vm-build-agent-02 idle days'
        Assert ((Get-Row $base 'vm-win-jumpbox').idleSource -match '90\+') 'jumpbox with no CPU data should be 90+'
    }
    Test 'Coverage: disabled subscription is not scanned (nested-array regression)' {
        Assert ($base.Report -match '2 of 2 subscription\(s\) visible') 'expected "2 of 2 subscription(s) visible"'
        Assert ($base.Report -match "Skipped subscription 'demo-retired'") 'disabled subscription should be reported as skipped'
    }
    Test 'Reservations: estimated costs on commitment-eligible types carry the caveat' {
        Assert-Equal 'True' (Get-Row $base 'vm-win-jumpbox').commitmentCaveat 'estimated VM cost caveat'
        Assert-Equal 'False' (Get-Row $base 'vm-build-agent-02').commitmentCaveat 'billed VM cost needs no caveat'
        Assert ($base.Report -match 'Reservations and savings plans') 'report should explain the caveat'
    }
    Test 'Owners: per-owner CSVs add up and fall back to resource group tags' {
        $files = @(Get-ChildItem (Join-Path $base.Dir 'by-owner') -Filter '*.csv')
        $sum = ($files | ForEach-Object { @(Import-Csv $_.FullName).Count } | Measure-Object -Sum).Sum
        Assert-Equal $base.Rows.Count $sum 'rows across by-owner CSVs'
        $pip = Get-Row $base 'pip-test-dyn'
        Assert-Equal 'sandbox@example.com' $pip.owner 'owner from resource group tag'
        Assert-Equal 'resource group tag' $pip.ownerSource 'ownerSource'
    }
    Test 'Changes: first run is the baseline' {
        Assert ($base.Report -match 'this report is the baseline') 'first run should say baseline'
        Assert (@($base.Rows | Where-Object { $_.status -ne 'baseline' }).Count -eq 0) 'all statuses should be baseline'
    }

    Write-Host 'Scenario runs'
    Test 'Coverage: an unreadable subscription makes the tenant partial, never clean' {
        $fx = Copy-Fixtures 'coverage'
        Edit-Fixture $fx 'coverage-check.json' { param($d) @($d | Where-Object { $_.name -ne 'demo-dev' }) }
        $r = Invoke-Run $fx 'coverage'
        Assert ($r.Report -match '\| partial \|') 'tenant should be partial'
        Assert ($r.Report -match "can't see subscription 'demo-dev'") 'report should name the unreadable subscription'
    }
    Test 'Coverage: no readable subscriptions makes the tenant failed' {
        $fx = Copy-Fixtures 'coverage0'
        Set-Content (Join-Path $fx 'coverage-check.json') '[]'
        $r = Invoke-Run $fx 'coverage0'
        Assert ($r.Report -match '\| failed \|') 'tenant should be failed'
        Assert-Equal 0 $r.Rows.Count 'findings from a failed tenant'
    }
    Test 'SkipMetrics: metric-confirmed types are left out, with a warning' {
        $r = Invoke-Run $Fixtures 'skipmetrics' @('-SkipMetrics')
        $cand = 'idle-container-app', 'log-analytics-workspace', 'idle-storage-account', 'hot-blob-unread', 'idle-container-registry', 'oversized-container-registry',
                'idle-openai-deployment', 'idle-bastion', 'idle-sql-database', 'premium-disk-deallocated-vm'
        Assert (-not ($r.Rows | Where-Object { $_.wasteType -in $cand })) 'candidate types must be absent'
        Assert ($r.Report -match 'not checked because of -SkipMetrics') 'missing -SkipMetrics warning'
    }
    Test 'Changes: resolved, new, excluded and not-rechecked are told apart' {
        $parent = Join-Path $Work 'history'
        Invoke-Run $Fixtures '20261101-000000' @() $parent | Out-Null
        $fx = Copy-Fixtures 'history'
        Edit-Fixture $fx '03-unassociated-public-ips.json' { param($d) @($d | Where-Object { $_.name -ne 'pip-old-lb-frontend' }) }
        Edit-Fixture $fx '13-idle-load-balancers.json' { param($d) foreach ($x in $d) { if ($x.name -eq 'lb-old-web') { $x.ignored = 1 } }; $d }
        Edit-Fixture $fx '19-empty-resource-groups.json' { param($d) $n = $d[0] | ConvertTo-Json -Depth 5 | ConvertFrom-Json; $n.name = 'rg-new'; $n.id = $n.id -replace 'rg-old-poc', 'rg-new'; @($d) + $n }
        Set-Content (Join-Path $fx '06-old-snapshots.json') 'not json'      # this query now fails
        $r = Invoke-Run $fx '20261108-000000' @() $parent
        Assert ($r.Report -match '\*\*Resolved\*\* \(gone, and rechecked this time\) \| 1 \|') 'one resolved'
        Assert ($r.Report -match 'Resolved:\*\* pip-old-lb-frontend') 'pip-old-lb-frontend resolved'
        Assert ($r.Report -match 'Now excluded by the ignore tag \| 1 \|') 'one now excluded'
        Assert ($r.Report -match 'Not rechecked this time [^|]*\| 2 \|') 'two snapshots not rechecked (failed query is not "resolved")'
        Assert-Equal 'new' (Get-Row $r 'rg-new').status 'new resource group status'
        Assert-Equal 'open' (Get-Row $r 'vm-win-jumpbox').status 'unchanged finding status'
    }
    Test 'Changes: a second scan where nothing changed works (empty lists must not crash)' {
        $parent = Join-Path $Work 'stable'
        Invoke-Run $Fixtures '20261101-000000' @() $parent | Out-Null
        $r = Invoke-Run $Fixtures '20261108-000000' @() $parent
        Assert ($r.Report -match 'New since then \| 0 \|') 'no new findings expected'
        Assert ($r.Report -match '\*\*Resolved\*\* \(gone, and rechecked this time\) \| 0 \|') 'no resolved findings expected'
        Assert (@($r.Rows | Where-Object { $_.status -ne 'open' }).Count -eq 0) 'every finding should be open'
    }
    Test 'Changes: a failed check on one resource does not hide another whose ID it prefixes' {
        $parent = Join-Path $Work 'prefix'
        $fx1 = Copy-Fixtures 'prefix1'
        Edit-Fixture $fx1 '09-log-analytics-workspaces.json' { param($d) foreach ($x in $d) { if ($x.name -eq 'log-app-prod') { $x.checkInputs.retention = 90 } }; $d }
        Invoke-Run $fx1 '20261101-000000' @() $parent | Out-Null
        # log-app-prod is gone; workspace 'log-app' (a prefix of its ID) fails its check
        $fx2 = Copy-Fixtures 'prefix2'
        Edit-Fixture $fx2 '09-log-analytics-workspaces.json' { param($d)
            $bad = $d | Where-Object { $_.name -eq 'log-app-prod' } | ConvertTo-Json -Depth 8 | ConvertFrom-Json
            $bad.name = 'log-app'; $bad.id = $bad.id -replace 'log-app-prod$', 'log-app'; $bad.checkInputs.retention = 'not-a-number'
            @($d | Where-Object { $_.name -ne 'log-app-prod' }) + $bad }
        $r = Invoke-Run $fx2 '20261108-000000' @() $parent
        Assert ($r.Report -match "Couldn't check log-app ") 'log-app check should have failed'
        Assert ($r.Report -match 'Resolved:\*\* [^\n]*log-app-prod') 'log-app-prod should be resolved, not "not rechecked"'
    }
    Test 'Keys: two waste types on one resource are both kept; Advisor merges once; exact duplicates collapse' {
        $fx = Copy-Fixtures 'keys'
        Edit-Fixture $fx '19-empty-resource-groups.json' { param($d)
            $asp = Get-Content (Join-Path $fx '04-empty-app-service-plans.json') -Raw | ConvertFrom-Json | Where-Object { $_.name -eq 'asp-legacy-api' }
            $other = $asp | ConvertTo-Json -Depth 8 | ConvertFrom-Json; $other.wasteType = 'empty-resource-group'
            @($d) + $other + ($d[0] | ConvertTo-Json -Depth 8 | ConvertFrom-Json) }       # plus an exact duplicate of rg-old-poc
        $r = Invoke-Run $fx 'keys'
        $asp = @($r.Rows | Where-Object { $_.name -eq 'asp-legacy-api' })
        Assert-Equal 'empty-app-service-plan, empty-resource-group' (@($asp | ForEach-Object { $_.wasteType } | Sort-Object) -join ', ') 'waste types on asp-legacy-api'
        Assert-Equal 1 @($asp | Where-Object { $_.reason -match 'corroborated by Advisor' }).Count 'findings that merged the Advisor recommendation'
        Assert-Equal 1 @($r.Rows | Where-Object { $_.name -eq 'rg-old-poc' }).Count 'rg-old-poc after an exact duplicate row'
    }
    Test 'Changes: -Compare none skips the comparison' {
        $r = Invoke-Run $Fixtures '20261115-000000' @('-Compare', 'none') (Join-Path $Work 'history')
        Assert ($r.Report -match 'this report is the baseline') '-Compare none should not compare'
    }
    Test 'Costs: a partial saving (tier change, retention only) never reports the whole bill as the saving' {
        $fx = Copy-Fixtures 'partial'
        # log-app-prod: queried, but 90-day retention, so a retention-only finding
        Edit-Fixture $fx '09-log-analytics-workspaces.json' { param($d) foreach ($x in $d) { if ($x.name -eq 'log-app-prod') { $x.checkInputs.retention = 90 } }; $d }
        $billedNames = 'vm-retired-app_OsDisk', 'stmediaarchive', 'crplatform', 'log-app-prod', 'log-security-archive', 'crlegacybuild'
        $ids = @{ 'log-app-prod' = '/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-monitoring/providers/Microsoft.OperationalInsights/workspaces/log-app-prod' }
        foreach ($n in $billedNames) { if (-not $ids[$n]) { $ids[$n] = (Get-Row $base $n).resourceId } }
        $clock = [DateTime]::Parse((Get-Content (Join-Path $fx 'clock.json') -Raw | ConvertFrom-Json -AsHashtable -DateKind String)['now'], [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles] 'AdjustToUniversal, AssumeUniversal')
        Edit-Fixture $fx 'consumption.json' { param($d)
            $add = foreach ($n in $billedNames) { foreach ($i in 1..30) {
                [pscustomobject] @{ instanceId = $ids[$n]; pretaxCost = 10.0; currency = 'USD'; usageStart = $clock.AddDays(-$i).ToString('yyyy-MM-ddT00:00:00Z') } } }
            @($d) + @($add) }
        $r = Invoke-Run $fx 'partial'
        foreach ($n in 'vm-retired-app_OsDisk', 'stmediaarchive', 'crplatform') {
            $row = Get-Row $r $n
            Assert-Equal (Get-Row $base $n).monthlyCost $row.monthlyCost "$n saving (must stay the tier-change estimate, not the 300.00 bill)"
            Assert ($row.costSource -like 'estimated*' -and $row.costSource -match 'whole resource billed 300\.00 USD') "$n cost source should be an estimate noting the whole bill: $($row.costSource)"
        }
        $lawRetention = Get-Row $r 'log-app-prod'
        Assert-Equal '' $lawRetention.monthlyCost 'retention-only workspace saving (unknown, not the whole bill)'
        Assert ($lawRetention.costSource -match 'whole resource billed 300\.00 USD') 'retention-only workspace should note the whole bill'
        # Full savings (delete the registry, stop the unqueried data) still use the bill
        foreach ($n in 'crlegacybuild', 'log-security-archive') {
            Assert-Equal '300' (Get-Row $r $n).monthlyCost "$n billed saving"
            Assert ((Get-Row $r $n).costSource -like 'billed*') "$n should use billed cost"
        }
    }
    Test 'Clock: fixture data is judged against clock.json, not the system clock (stale-fixture regression)' {
        $fx = Copy-Fixtures 'clock'
        $c = Get-Content (Join-Path $fx 'clock.json') -Raw | ConvertFrom-Json -AsHashtable -DateKind String
        $t = [DateTime]::Parse($c['now'], [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles] 'AdjustToUniversal, AssumeUniversal')
        Set-Content (Join-Path $fx 'clock.json') (@{ now = $t.AddDays(10).ToString('o') } | ConvertTo-Json)
        $before = [DateTime]::UtcNow.ToString('yyyy-MM-dd')
        $r = Invoke-Run $fx 'clock'
        $after = [DateTime]::UtcNow.ToString('yyyy-MM-dd')                # the run may cross midnight
        Assert-Equal '57' (Get-Row $r 'vm-build-agent-02').idleDays 'idle days 10 days after the fixture clock'
        Assert ($r.Report -match "Generated ($before|$after)") 'report timestamp must be the real run time, not the fixture clock'
    }
    Test 'Output safety: HTML-escapes and neutralizes CSV formulas in tag values' {
        $fx = Copy-Fixtures 'hostile'
        Edit-Fixture $fx '02-orphaned-nics.json' { param($d) $d[0].owner = '=HYPERLINK("x")<script>alert(1)</script>'; $d }
        $r = Invoke-Run $fx 'hostile'
        Assert (-not $r.Html.Contains('<script>alert(1)')) 'raw script tag reached the HTML'
        Assert ($r.Html.Contains('&lt;script&gt;alert(1)')) 'escaped value missing from the HTML'
        Assert ((Get-Row $r 'nic-vm-old01').owner.StartsWith("'=")) 'formula-looking CSV cell not neutralized'
    }
    Test 'Currency: mixed currencies without a rate warn that the order is approximate' {
        $fx = Copy-Fixtures 'fx'
        Edit-Fixture $fx 'consumption.json' { param($d) foreach ($x in $d) { if ($x.instanceId -like '*disk-sql-data-old') { $x.currency = 'CAD' } }; $d }
        $r = Invoke-Run $fx 'fx' @('-Currency', 'CAD')
        Assert ($r.Report -match 'No exchange rate available for USD to CAD') 'missing approximate-order warning'
        Assert ($r.Report -match 'USD \+ [\d,.]+ CAD|CAD \+ [\d,.]+ USD') 'totals must stay per currency'
    }
}
finally {
    Remove-Item -Recurse -Force $Work -ErrorAction SilentlyContinue
}

Write-Host ''
if ($script:Failed.Count) {
    Write-Host "$($script:Passed) passed, $($script:Failed.Count) failed" -ForegroundColor Red
    $script:Failed | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}
Write-Host "All $($script:Passed) tests passed" -ForegroundColor Green
exit 0
