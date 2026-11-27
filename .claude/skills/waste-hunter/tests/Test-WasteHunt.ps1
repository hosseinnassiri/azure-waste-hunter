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
# Every script the runner loads (the runner, lib/ and types/), so the guard checks see all of it
$ScriptFiles = @(Get-Item $Runner) + @(Get-ChildItem (Join-Path $SkillDir 'scripts') -Recurse -Filter '*.ps1' | Where-Object { $_.FullName -ne (Get-Item $Runner).FullName } | Sort-Object FullName)
$AllSource = (@($ScriptFiles | ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n")
$Work     = Join-Path ([IO.Path]::GetTempPath()) ("waste-hunter-tests-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory $Work | Out-Null

. (Join-Path $TestsDir 'TestHelpers.ps1')   # Assert, Invoke-Run, Copy-BaseRun, Get-Row, Copy-Fixtures, ...

# Static tests run as they're declared. Tests declared after the base run (they read it, and most run
# the runner again, ~11 s each) are queued and run in parallel workers by Invoke-QueuedTests, which
# prints them in declaration order. Tests sharing a -Group run in one worker, in order: use it when one
# test depends on another's folder.
$script:Passed = 0; $script:Failed = [Collections.Generic.List[string]]::new()
$script:Queue = [Collections.Generic.List[object]]::new(); $script:QueueTests = $false
function Test([string] $Name, [scriptblock] $Body, [string] $Group) {
    if ($script:QueueTests) {
        $i = $script:Queue.Count
        $script:Queue.Add([pscustomobject] @{ I = $i; Name = $Name; Body = $Body.ToString(); Group = ($Group ? $Group : "test-$i") })
        return
    }
    try { & $Body; $script:Passed++; Write-Host "  ok    $Name" -ForegroundColor Green }
    catch { $script:Failed.Add("$Name :: $($_.Exception.Message)"); Write-Host "  FAIL  $Name`n        $($_.Exception.Message)" -ForegroundColor Red }
}
function Invoke-QueuedTests([hashtable] $Vars) {
    if (-not $script:Queue.Count) { return }
    # Each worker runs one runner process at a time, so about half the logical CPUs (2 to 6)
    $workers = [Math]::Max(2, [Math]::Min(6, [int] [Math]::Floor([Environment]::ProcessorCount / 2)))
    Write-Host "Scenario tests ($($script:Queue.Count), $workers at a time)"
    $groups = @($script:Queue | Group-Object Group | ForEach-Object { , @($_.Group) })
    $helpers = Join-Path $TestsDir 'TestHelpers.ps1'
    $results = @($groups | ForEach-Object -ThrottleLimit $workers -Parallel {
        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'
        foreach ($kv in ($using:Vars).GetEnumerator()) { Set-Variable -Name $kv.Key -Value $kv.Value }
        . $using:helpers
        foreach ($t in $_) {
            # A script block belongs to the runspace that made it, so each test is rebuilt from its text here
            try { & ([scriptblock]::Create($t.Body)); [pscustomobject] @{ I = $t.I; Name = $t.Name; Error = $null } }
            catch { [pscustomobject] @{ I = $t.I; Name = $t.Name; Error = $_.Exception.Message } }
        }
    })
    Assert-Equal $script:Queue.Count $results.Count 'queued tests that reported a result'
    foreach ($r in @($results | Sort-Object I)) {
        if (-not $r.Error) { $script:Passed++; Write-Host "  ok    $($r.Name)" -ForegroundColor Green }
        else { $script:Failed.Add("$($r.Name) :: $($r.Error)"); Write-Host "  FAIL  $($r.Name)`n        $($r.Error)" -ForegroundColor Red }
    }
}

try {
    Write-Host 'Static checks'
    $queries = @(Get-ChildItem (Join-Path $SkillDir 'queries') -Filter '*.kql')
    $required = 'wasteType', 'id', 'name', 'type', 'tenantId', 'subscriptionId', 'resourceGroup', 'location', 'owner', 'app', 'env',
                'createdTime', 'ageDays', 'idleDays', 'idleSource', 'sku', 'tier', 'sizeGb', 'os', 'extra', 'confidence', 'reason', 'ignored'

    Test 'Queries: every file is marked read-only and uses the shared column set' {
        Assert ($queries.Count -ge 38) "expected 38+ queries, found $($queries.Count)"
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
    Test 'Queries: no column is named after a reserved word (Resource Graph fails with a bare ParserFailure)' {
        # Found live: `shards` (query 26) and `kind` (a probe query). Fixtures can't catch this. KQL's own
        # kind= option on join, union and mv-expand is fine, and so is reading the kind property.
        $rx = '(?i)(?<!\b(?:join|union|mv-expand)\s+)\b(kind|shards)\s*=(?!=)'
        foreach ($q in $queries) {
            $code = (Get-Content $q.FullName | ForEach-Object { $_ -replace '//.*$', '' }) -join "`n"
            $code = $code -replace "'[^']*'", "''"
            $m = [regex]::Match($code, $rx)   # not -match: the message would read $Matches, unset (strict mode) when nothing matches
            Assert (-not $m.Success) "$($q.Name) names a column '$($m.Groups[1].Value)', which Resource Graph rejects; rename it (shardCount, acctKind)"
        }
    }
    Test 'Queries: prefixes that cost nothing (IPv6, derived from a custom BYOIP prefix) are not reported as unused' {
        $code = (Get-Content (Join-Path $SkillDir 'queries/31-unused-public-ip-prefixes.kql') | ForEach-Object { $_ -replace '//.*$', '' }) -join "`n"
        Assert ($code -match "publicIPAddressVersion\)\s*!~\s*'IPv6'") 'query 31 must skip IPv6 prefixes (no charge)'
        Assert ($code -match 'isempty\(tostring\(properties\.customIPPrefix\.id\)\)') 'query 31 must skip prefixes derived from a custom IP prefix (no charge)'
    }
    Test 'Queries: a table other than the main one is joined at most once (Resource Graph rejects more)' {
        # DisallowedMaxNumberOfRemoteTables, found live on query 22 (the fixtures can't catch it). A query
        # may join its own main table any number of times; any other table only once.
        foreach ($q in $queries) {
            $code = (Get-Content $q.FullName | ForEach-Object { $_ -replace '//.*$', '' }) -join "`n"
            $main = ([regex]::Match($code, '^\s*(\w+)')).Groups[1].Value.ToLower()
            $right = @([regex]::Matches($code, '(?i)\bjoin\b[^(]*\(\s*(\w+)') | ForEach-Object { $_.Groups[1].Value.ToLower() } | Where-Object { $_ -ne $main })
            foreach ($g in @($right | Group-Object)) { Assert ($g.Count -le 1) "$($q.Name) (main table $main) joins '$($g.Name)' $($g.Count) times; Resource Graph allows another table once" }
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
        $src = $AllSource
        Assert ($src -match '\$AllowedAz = @\(([\s\S]*?)\n\)') 'AllowedAz block not found'
        $body = ($Matches[1] -split "`n" | ForEach-Object { $_ -replace '#.*$', '' }) -join "`n"   # comments may contain apostrophes
        $cmds = @([regex]::Matches($body, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value }) | Sort-Object
        $expected = @('account list', 'account set', 'account show', 'advisor recommendation list', 'cognitiveservices account deployment list',
                      'consumption reservation summary list', 'consumption usage list', 'graph query', 'monitor metrics list') | Sort-Object
        Assert-Equal ($expected -join ', ') ($cmds -join ', ') 'allowed az commands'
    }
    Test 'Guard: az is only ever invoked inside Invoke-AzRead' {
        $src = $AllSource
        Assert-Equal 1 ([regex]::Matches($src, '&\s*az\s')).Count 'number of direct az invocations'
        # The az call lives in Invoke-AzProcess, which only Invoke-AzRead may call (after the allow-list check)
        Assert ($src -match '(?s)function Invoke-AzProcess.*?&\s*az\s') 'the az call must be inside Invoke-AzProcess'
        $callers = @([regex]::Matches($src, '(?<!function )Invoke-AzProcess\b(?!'')') | ForEach-Object {
            $before = $src.Substring(0, $_.Index); $before.Substring($before.LastIndexOf("`nfunction ") + 10).Split(' ', 2)[0] })
        Assert-Equal 'Invoke-AzRead' (($callers | Sort-Object -Unique) -join ', ') 'functions that call Invoke-AzProcess'
        Assert ($src -notmatch 'Invoke-Expression|\biex\b|Start-Process\s+az') 'runner must not shell out to az any other way'
    }
    Test 'Guard: the runner loads every script file under scripts/ (none escapes the guard checks)' {
        Assert ($ScriptFiles.Count -ge 7) "expected the runner plus 6+ lib files, found $($ScriptFiles.Count)"
        foreach ($f in @($ScriptFiles | Select-Object -Skip 1)) {
            Assert ((Get-Content $Runner -Raw).Contains($f.BaseName) -or $f.DirectoryName -like '*types') "$($f.Name) is not loaded by the runner"
        }
    }
    Test 'Guard: the only external endpoint is the Retail Prices API, by GET' {
        $src = $AllSource
        $urls = @([regex]::Matches($src, 'https://[a-z0-9.-]+') | ForEach-Object { $_.Value } | Sort-Object -Unique)
        foreach ($u in $urls) { Assert ($u -in 'https://prices.azure.com', 'https://portal.azure.com') "unexpected endpoint $u" }
        Assert ($src -notmatch "Invoke-RestMethod[^\n]*-Method\s+(Post|Put|Patch|Delete)") 'price API must be GET only'
    }
    Test 'Skill: frontmatter has name and description, and no $0/$1/$ARGUMENTS placeholders' {
        $s = Get-Content (Join-Path $SkillDir 'SKILL.md') -Raw
        Assert ($s -match '(?s)^---\s*\nname:\s*waste-hunter\s*\ndescription:\s*\S.+?\n---') 'frontmatter name/description missing'
        Assert ($s -notmatch '\$(\d|ARGUMENTS)') 'SKILL.md contains a $-placeholder the skill loader would replace'
    }
    Test 'Skill: frontmatter fits the Agent Skills limits (Copilot rejects a description over 1024 characters)' {
        $s = Get-Content (Join-Path $SkillDir 'SKILL.md') -Raw
        $name = [regex]::Match($s, '(?m)^name:\s*(.+?)\s*$').Groups[1].Value
        $desc = [regex]::Match($s, '(?m)^description:\s*(.+?)\s*$').Groups[1].Value
        Assert ($name -match '^[a-z0-9]+(-[a-z0-9]+)*$' -and $name.Length -le 64) "name '$name' must be 1-64 lowercase letters, digits and single hyphens"
        Assert-Equal (Split-Path $SkillDir -Leaf) $name 'name matches the skill folder'
        Assert ($desc.Length -ge 1 -and $desc.Length -le 1024) "description is $($desc.Length) characters; the limit is 1024"
    }
    Test 'Skill: SKILL.md finds its runner from its own folder, so an installed plugin copy works outside this repo' {
        $s = Get-Content (Join-Path $SkillDir 'SKILL.md') -Raw
        Assert ($s -notmatch '\.claude/skills/') 'SKILL.md uses a repo-relative .claude/skills/ path, which breaks a plugin install'
        Assert ($s -match [regex]::Escape('pwsh -NoProfile -File "${CLAUDE_SKILL_DIR}/scripts/Invoke-WasteHunt.ps1"')) 'SKILL.md should run the runner through ${CLAUDE_SKILL_DIR}'
    }
    Test 'Plugin: the marketplace entry points at a plugin that holds this skill, with a matching manifest' {
        $m = Get-Content (Join-Path $RepoDir '.claude-plugin/marketplace.json') -Raw | ConvertFrom-Json -AsHashtable
        foreach ($k in 'name', 'owner', 'plugins') { Assert $m.ContainsKey($k) "marketplace.json has no '$k'" }
        $entry = @($m.plugins | Where-Object { $_['name'] -eq 'waste-hunter' })
        Assert-Equal 1 $entry.Count 'one waste-hunter plugin entry'
        $root = Join-Path $RepoDir $entry[0]['source']
        Assert (Test-Path (Join-Path $root 'skills/waste-hunter/SKILL.md')) "plugin source $($entry[0]['source']) has no skills/waste-hunter/SKILL.md"
        Assert-Equal (Resolve-Path $SkillDir).Path (Resolve-Path (Join-Path $root 'skills/waste-hunter')).Path 'the plugin ships this skill, not a copy'
        $p = Get-Content (Join-Path $root '.claude-plugin/plugin.json') -Raw | ConvertFrom-Json -AsHashtable
        Assert-Equal 'waste-hunter' $p['name'] 'plugin.json name'
        Assert-Equal 'MIT' $p['license'] 'plugin.json license'
        # No version: installs follow the commit SHA. A fixed version would leave users on a stale copy until bumped.
        Assert (-not $p.ContainsKey('version') -and -not $entry[0].ContainsKey('version')) 'set no plugin version (updates follow commits)'
    }
    Test 'Settings: deny rules cover write and secret-reading az commands' {
        $deny = @((Get-Content (Join-Path $RepoDir '.claude/settings.json') -Raw | ConvertFrom-Json).permissions.deny)
        foreach ($p in 'Bash(az * delete *)', 'PowerShell(az * delete *)', 'Bash(az rest *)', 'Bash(az keyvault secret *)', 'Bash(az * deallocate *)') {
            Assert ($p -in $deny) "missing deny rule $p"
        }
    }
    Test 'Settings: every Bash deny rule has a PowerShell twin, and the reverse (Bash rules do not bind the PowerShell tool)' {
        $deny = @((Get-Content (Join-Path $RepoDir '.claude/settings.json') -Raw | ConvertFrom-Json).permissions.deny)
        $bash = @($deny | Where-Object { $_ -like 'Bash(*)' } | ForEach-Object { $_.Substring(5) })
        $ps = @($deny | Where-Object { $_ -like 'PowerShell(*)' } | ForEach-Object { $_.Substring(11) })
        foreach ($b in $bash) { Assert ($b -in $ps) "Bash($b is denied but PowerShell($b is not" }
        foreach ($p in $ps) { Assert ($p -in $bash) "PowerShell($p is denied but Bash($p is not" }
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
            'az consumption usage list --subscription 0000 --include-additional-properties --start-date 2026-10-27 --end-date 2026-11-26'
            'az consumption reservation summary list --grain daily --reservation-order-id 0000 --start-date 2026-10-27 --end-date 2026-11-26'
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
    Test 'Types: every query has a waste-type record, and every record comes from a query, a parent check or its own Collect' {
        $fromQueries = @($queries | ForEach-Object { [regex]::Matches((Get-Content $_.FullName -Raw), "wasteType\s*=\s*(?:iff\([^,]*,\s*)?'([^']+)'(?:\s*,\s*'([^']+)')?") | ForEach-Object { $_.Groups[1].Value; $_.Groups[2].Value } | Where-Object { $_ } } | Sort-Object -Unique)
        $recs = @(Get-ChildItem (Join-Path $SkillDir 'scripts/types') -Filter '*.ps1' | ForEach-Object { $f = $_; & $_.FullName | ForEach-Object { $_['File'] = $f.BaseName; $_ } })
        $names = @($recs | ForEach-Object { $_.Name })
        foreach ($t in $fromQueries) { Assert ($t -in $names) "query waste type '$t' has no record in scripts/types" }
        foreach ($r in $recs) {
            if ($r['Parent']) { Assert ($r.Parent -in $names) "$($r.Name): parent '$($r.Parent)' has no record"; continue }
            if ($r['Collect']) {
                Assert ($r.Name -notin $fromQueries) "record '$($r.Name)' has Collect but a query also emits it"
                Assert (-not ($queries | Where-Object { $_.BaseName -eq $r.File })) "record '$($r.Name)' has Collect, so it must not have a query file"
                continue
            }
            Assert ($r.Name -in $fromQueries) "record '$($r.Name)' ($($r.File).ps1) matches no query's wasteType"
            $q = @($queries | Where-Object { $_.BaseName -eq $r.File })
            Assert ($q.Count -eq 1 -and (Get-Content $q[0].FullName -Raw) -match "wasteType\s*=\s*(?:iff\([^,]*,\s*)?(?:'[^']+'\s*,\s*)?'$([regex]::Escape($r.Name))'") "record '$($r.Name)' should live in the types file named after its query ($($r.File))"
        }
    }
    Test 'Types: a malformed waste-type record stops the run with the reason' {
        $lib = Join-Path $SkillDir 'scripts/lib/WasteTypes.ps1'
        foreach ($case in @(
            @{ files = @{ 'a.ps1' = "@{ Name = 'x'; Label = 'X'; Order = 1; Action = { 'a' }; Typo = 1 }" }; error = "unknown key 'Typo'" }
            @{ files = @{ 'a.ps1' = "@{ Name = 'x'; Label = 'X'; Order = 1; Candidate = `$true; Action = { 'a' } }" }; error = "needs a Check" }
            @{ files = @{ 'a.ps1' = "@{ Name = 'x'; Label = 'X'; Order = 1 }" }; error = "needs an Action" }
            @{ files = @{ 'a.ps1' = "@{ Name = 'x'; Label = 'X'; Order = 1; Action = { 'a' } }"; 'b.ps1' = "@{ Name = 'x'; Label = 'Y'; Order = 2; Action = { 'b' } }" }; error = "defined in both" }
            @{ files = @{ 'a.ps1' = "@{ Name = 'x'; Label = 'X'; Order = 1; Parent = 'nope'; Action = { 'a' } }" }; error = "parent 'nope'" }
            @{ files = @{ 'a.ps1' = "@{ Name = 'x'; Label = 'X'; Order = 1; Candidate = `$true; Check = { }; Collect = { }; Action = { 'a' } }" }; error = "can't also be a candidate" })) {
            $dir = Join-Path $Work ("types-" + [guid]::NewGuid().ToString('N').Substring(0, 6)); New-Item -ItemType Directory $dir | Out-Null
            foreach ($k in $case.files.Keys) { Set-Content (Join-Path $dir $k) $case.files[$k] }
            $out = & pwsh -NoProfile -Command "`$ErrorActionPreference = 'Stop'; . '$lib'; try { Import-WasteTypes '$dir' | Out-Null; 'LOADED' } catch { `$_.Exception.Message }" 2>&1 | Out-String
            Assert ($out -notmatch 'LOADED' -and $out.Contains($case.error)) "expected '$($case.error)', got: $($out.Trim())"
        }
    }
    Test 'Pricing: pricing.json parses and has every section the runner reads' {
        $p = Get-Content (Join-Path $SkillDir 'scripts/pricing.json') -Raw | ConvertFrom-Json -AsHashtable
        foreach ($k in 'disks', 'snapshotsPerGb', 'publicIps', 'appServicePlans', 'containerApps', 'storagePerGb', 'containerRegistries', 'openAI', 'network', 'sqlDatabase', 'vms',
                       'cosmosDb', 'dataPlatforms', 'redisCache', 'messaging', 'apiManagement', 'machineLearning', 'licensing', 'schedules') {
            Assert ($p.ContainsKey($k)) "pricing.json has no '$k'"
        }
    }

    Write-Host 'Full run on synthetic fixtures (offline pricing)'
    $base = Invoke-Run $Fixtures 'base' -KeepParallel
    $script:QueueTests = $true   # from here on, tests are queued and run in parallel (Invoke-QueuedTests)
    $expected = @(
        'advisor-cost|demo-prod', 'empty-app-service-plan|asp-legacy-api', 'empty-app-service-plan|asp-playground',
        'empty-app-service-plan|asp-reports-weu', 'empty-resource-group|rg-old-poc', 'hot-blob-unread|stmediaarchive', 'idle-application-gateway|agw-legacy-portal',
        'idle-bastion|bas-dev', 'idle-container-app|ca-orders-legacy', 'idle-container-app|ca-queue-worker', 'idle-container-registry|crgraphapps',
        'idle-container-registry|crlegacybuild', 'idle-load-balancer|lb-empty-scratch', 'idle-load-balancer|lb-old-web', 'idle-network-gateway|erc-pending-dc2',
        'idle-network-gateway|nat-dev-unused', 'idle-network-gateway|vpngw-old-branch', 'idle-openai-deployment|oai-research/gpt-4o-mini-support-ft',
        'idle-openai-deployment|oai-research/gpt-ptu-eval', 'idle-sql-database|sql-legacy/reporting-old', 'idle-storage-account|stgraphdata',
        'idle-storage-account|stlegacyexports', 'log-analytics-workspace|log-security-archive', 'old-snapshot|snap-sql-pre-upgrade-2025',
        'old-snapshot|snap-vm-old01-osdisk', 'orphaned-nic|aks-nodepool1-nic-7', 'orphaned-nic|nic-vm-old01', 'oversized-container-registry|crplatform',
        'premium-disk-deallocated-vm|vm-retired-app_OsDisk', 'unassociated-public-ip|pip-old-lb-frontend', 'unassociated-public-ip|pip-test-dyn',
        'unassociated-public-ip|pip-vm-old01', 'unattached-disk|asrseeddisk-web01-a1b2c3', 'unattached-disk|disk-sql-data-old', 'unattached-disk|disk-temp-build',
        'vm-stopped-not-deallocated|vm-build-agent-02', 'vm-stopped-not-deallocated|vm-win-jumpbox',
        'vmss-instance-stopped-not-deallocated|vmss-web_3', 'vmss-instance-stopped-not-deallocated|aks-nodepool1-12345678-vmss_1',
        'idle-ddos-protection-plan|ddos-legacy-plan', 'stopped-app-service-plan|asp-intranet-old', 'stopped-app-service-plan|asp-free-stopped',
        'orphaned-vm-backup|rsv-dev/vm-old01', 'orphaned-workload-backup|rsv-dev/vm-old01/billing', 'idle-firewall|fw-hub-legacy', 'idle-firewall|fw-dev-dnat',
        'overprovisioned-cosmos-db|cosmos-orders-legacy', 'overprovisioned-cosmos-db|cosmos-dev-idle',
        'idle-data-platform|fab-analytics', 'idle-data-platform|syn-ws/dw-legacy', 'idle-data-platform|adx-telemetry', 'idle-data-platform|pbi-reports', 'idle-data-platform|pbi-legacy',
        'idle-redis-cache|redis-session-old', 'idle-redis-cache|amr-sessions-legacy', 'idle-messaging-namespace|sb-legacy-orders', 'idle-messaging-namespace|evh-dev-unused', 'idle-messaging-namespace|sb-dev-notifications',
        'idle-api-management|apim-legacy', 'idle-ml-compute|mlw-research/cpu-cluster', 'idle-ml-compute|mlw-research/batch-cluster',
        'orphaned-private-endpoint|pe-st-deleted', 'orphaned-private-endpoint|pe-sql-rejected', 'unused-public-ip-prefix|ippre-legacy',
        'empty-edge-profile|afd-old-site', 'empty-edge-profile|tm-unused', 'nonprod-vm-always-on|vm-dev-api',
        'underused-reservation|Standard_D4s_v5 (bbbbbbbb)', 'hybrid-benefit-not-applied|vm-win-app01', 'hybrid-benefit-not-applied|sqlsrv-erp/erp',
        'nonprod-geo-redundant-storage|stdevlogs', 'full-snapshot|snap-sql-daily-premium', 'full-snapshot|snap-build-weekly-03', 'underused-vm|vm-api-01', 'underused-vm|vm-batch-old')

    Test 'Findings: exactly the expected set (every flag and every drop is intentional)' {
        $got = @($base.Rows | ForEach-Object { "$($_.wasteType)|$($_.name)" } | Sort-Object)
        $missing = @($expected | Where-Object { $_ -notin $got }); $extra = @($got | Where-Object { $_ -notin $expected })
        Assert (-not $missing -and -not $extra) "missing: $($missing -join ', ') | unexpected: $($extra -join ', ')"
    }
    Test 'Metric checks: candidates that are in use are dropped, not reported' {
        foreach ($n in 'ca-api-busy', 'log-app-prod', 'stwebassets', 'oai-research/gpt-ptu-prod', 'oai-research/gpt-4o-chat', 'bas-prod', 'sql-app/orders', 'vm-weekend-batch_data', 'fw-prod-egress',
                       'cosmos-busy', 'cosmos-free', 'syn-ws/dw-prod', 'adx-busy', 'pbi-portal', 'redis-prod', 'amr-catalog', 'evh-telemetry', 'sb-std-orders', 'apim-prod', 'mlw-research/gpu-train', 'stdevtiny',
                       'vm-api-02', 'vm-api-tiny', 'vm-cache-01', 'Standard_E8s_v5 (cccccccc)') {
            Assert (-not ($base.Rows | Where-Object { $_.name -eq $n })) "$n is in use but was reported"
        }
    }
    Test 'Exclusions: ignore-tagged resources are skipped and counted' {
        foreach ($n in 'disk-keep-forensics', 'stkeepforaudit', 'vm-gpu-train') { Assert (-not ($base.Rows | Where-Object { $_.name -eq $n })) "$n is tagged ignore but was reported" }
        Assert ($base.Report -match '3 resource\(s\) excluded') 'excluded count should be 3'
    }
    Test 'Exclusions file: ids, patterns, waste types, expiry and unused entries' {
        $oai = (Get-Row $base 'oai-research/gpt-ptu-eval').resourceId
        $excl = Join-Path $Work 'excl.json'
        @{ exclusions = @(
            @{ id = (Get-Row $base 'disk-temp-build').resourceId.ToUpper(); reason = 'build cache, recreated nightly' }               # case-insensitive
            @{ pattern = '/subscriptions/*/resourceGroups/rg-sandbox/*'; wasteType = 'unassociated-public-ip'; reason = 'sandbox IPs are allowlisted by a partner'; until = '2099-12-31' }
            @{ id = (Get-Row $base 'bas-dev').resourceId; reason = 'kept for incident response' }                                        # a metric-check candidate
            @{ id = $oai; wasteType = @('idle-openai-deployment'); reason = 'PTU reserved for the Q1 launch' }                            # exists only after its check
            @{ id = (Get-Row $base 'vm-win-jumpbox').resourceId; reason = 'old hold'; until = '2026-01-31' }                              # expired (fixture clock is 2026-11-26)
            @{ id = '/subscriptions/0000/resourceGroups/rg-gone/providers/Microsoft.Compute/disks/disk-deleted'; reason = 'stale entry' }) } |
            ConvertTo-Json -Depth 5 | Set-Content $excl
        $r = Invoke-Run $Fixtures 'exclfile' @('-ExclusionsFile', $excl)
        foreach ($n in 'disk-temp-build', 'pip-test-dyn', 'bas-dev', 'oai-research/gpt-ptu-eval') { Assert (-not ($r.Rows | Where-Object { $_.name -eq $n })) "$n should be excluded by the file" }
        foreach ($n in 'lb-empty-scratch', 'asp-playground', 'vm-win-jumpbox', 'oai-research/gpt-4o-mini-support-ft') { Get-Row $r $n | Out-Null }   # same RG, other type / expired / other deployment
        Assert ($r.Report -match '7 resource\(s\) excluded \(3 by the `waste-hunter:ignore=true` tag, 4 by the exclusions file `excl\.json`') 'excluded counts by source'
        Assert ($r.Report -match "Exclusion for '[^']*vm-win-jumpbox' expired on 2026-01-31") 'expired exclusion should be reported'
        Assert ($r.Report -match "Exclusion for '[^']*disk-deleted' matched nothing") 'unused exclusion should be reported'
        $ex = @(Import-Csv (Join-Path $r.Dir 'excluded.csv'))
        Assert-Equal 7 $ex.Count 'rows in excluded.csv'
        Assert-Equal 'PTU reserved for the Q1 launch' (@($ex | Where-Object { $_.name -eq 'oai-research/gpt-ptu-eval' })[0].reason) 'reason recorded in excluded.csv'
        Assert-Equal 'tag' (@($ex | Where-Object { $_.name -eq 'disk-keep-forensics' })[0].excludedBy) 'tag exclusions are listed too'
        Assert-Equal 0 @($r.Rows | Where-Object { $_.wasteType -eq 'idle-bastion' }).Count 'bas-dev was the only idle Bastion'
        Assert ($r.Report -match 'Idle Bastion hosts: 1 resource\(s\) checked') 'an excluded candidate must not be checked (only bas-prod)'
    }
    Test 'Exclusions file: the committed example is valid' {
        $r = Invoke-Run $Fixtures 'exclexample' @('-ExclusionsFile', (Join-Path $SkillDir 'exclusions.example.json'))
        Assert ($r.Report -match "Exclusion for '[^']*disk-forensics-2026' matched nothing") 'example entries load (and match nothing in the fixtures)'
    }
    Test 'Exclusions file: a malformed file stops the scan with the reason' {
        foreach ($case in @(
            @{ json = '{ "exclusions": [ { "id": "/subscriptions/x" } ] }'; error = 'needs a "reason"' }
            @{ json = '{ "exclusions": [ { "id": "/x", "pattern": "/y*", "reason": "r" } ] }'; error = 'exactly one of "id" or "pattern"' }
            @{ json = '{ "exclusions": [ { "id": "/x", "reason": "r", "until": "31/03/2027" } ] }'; error = 'must be a date like' }
            @{ json = '[ { "id": "/x", "reason": "r" } ]'; error = 'top-level "exclusions" list' }
            @{ json = '{ not json'; error = 'not valid JSON' })) {
            $f = Join-Path $Work 'bad-excl.json'; Set-Content $f $case.json
            $log = & pwsh -NoProfile -File $Runner -FixtureDir $Fixtures -OfflinePricing -OutDir (Join-Path $Work 'bad-excl-out') -ExclusionsFile $f 2>&1 | Out-String
            Assert ($LASTEXITCODE -ne 0) "a malformed file must fail the run: $($case.json)"
            Assert ($log.Contains($case.error)) "expected '$($case.error)' for $($case.json), got: $($log.Trim() -split "`n" | Select-Object -First 3)"
        }
    }
    Test 'Confidence: possible data stores and dependencies are low, never high' {
        Assert-Equal 'low' (Get-Row $base 'stgraphdata').confidence 'stgraphdata (Azure Files mount in the same RG)'
        Assert-Equal 'low' (Get-Row $base 'crgraphapps').confidence 'crgraphapps (referenced by a Container App)'
        Assert ((Get-Row $base 'stgraphdata').suggestedAction -match 'Do NOT delete') 'stgraphdata action must say do not delete'
        Assert-Equal 'low' (Get-Row $base 'lb-empty-scratch').confidence 'rule-less load balancer'
        Assert-Equal 'medium' (Get-Row $base 'ca-queue-worker').confidence 'Container App without HTTP ingress'
        Assert-Equal 'high' (Get-Row $base 'vm-retired-app_OsDisk').confidence 'premium disk on a VM off 90+ days'
        Assert-Equal 'low' (Get-Row $base 'rsv-dev/vm-old01').confidence 'backup of a deleted VM (may be the only copy)'
        Assert ((Get-Row $base 'rsv-dev/vm-old01').suggestedAction -match 'Do NOT delete') 'backup of a deleted VM: action must say do not delete'
        Assert-Equal 'low' (Get-Row $base 'rsv-dev/vm-old01/billing').confidence 'backup of a database on a deleted VM (may be the only copy)'
        Assert ((Get-Row $base 'rsv-dev/vm-old01/billing').suggestedAction -match 'Do NOT delete') 'database backup on a deleted VM: action must say do not delete'
        Assert-Equal 'high' (Get-Row $base 'fw-hub-legacy').confidence 'firewall with no traffic'
        Assert-Equal 'medium' (Get-Row $base 'fw-dev-dnat').confidence 'firewall with some traffic but no rule hits'
        Assert-Equal 'high' (Get-Row $base 'cosmos-dev-idle').confidence 'Cosmos DB with no RU consumed'
        Assert-Equal 'medium' (Get-Row $base 'cosmos-orders-legacy').confidence 'Cosmos DB used a little'
        Assert-Equal 'low' (Get-Row $base 'fab-analytics').confidence 'Fabric capacity (no usage metric to confirm it)'
        Assert-Equal 'medium' (Get-Row $base 'adx-telemetry').confidence 'Data Explorer ingesting but never queried'
        Assert-Equal 'high' (Get-Row $base 'pbi-reports').confidence 'Power BI Embedded at 0% CPU'
        Assert-Equal 'low' (Get-Row $base 'pbi-legacy').confidence 'Power BI Embedded with no CPU data (Gen1 or no activity)'
        Assert ((Get-Row $base 'pbi-reports').referenceCommandNotExecuted -match 'powerbi embedded-capacity pause') 'Power BI Embedded action is pause'
        Assert-Equal 'medium' (Get-Row $base 'mlw-research/batch-cluster').confidence 'ML cluster that runs jobs but keeps an idle node'
        Assert-Equal 'medium' (Get-Row $base 'pe-sql-rejected').confidence 'rejected private endpoint (may be re-requested)'
        Assert-Equal 'medium' (Get-Row $base 'ippre-legacy').confidence 'IP prefix (may be allowlisted)'
        Assert-Equal 'low' (Get-Row $base 'tm-unused').confidence 'empty Traffic Manager profile (free)'
        foreach ($n in 'vm-win-app01', 'sqlsrv-erp/erp') { Assert-Equal 'low' (Get-Row $base $n).confidence "$n (a saving only with licences)" }
        Assert-Equal 'high' (Get-Row $base 'Standard_D4s_v5 (bbbbbbbb)').confidence 'reservation used 30%'
    }
    Test 'Advisor: a right-size recommendation merges into the oversized-VM finding' {
        $v = Get-Row $base 'vm-api-01'
        Assert-Equal 'underused-vm' $v.wasteType 'vm-api-01 waste type'
        Assert-Equal 'high' $v.confidence 'oversized VM whose memory fits in half the size (and Advisor agrees)'
        Assert ($v.reason -match 'corroborated by Advisor') 'reason should say corroborated by Advisor'
        Assert-Equal 'advisor' $v.costSource 'cost source'
    }
    Test 'Metric checks: thresholds are judged on the right statistic (peak, percentile, per-split minimum)' {
        Assert ((Get-Row $base 'cosmos-orders-legacy').reason -match '4,000 RU/s provisioned across 2 database/container scope\(s\).*peaked at 3\.0%.*About 800 RU/s') 'Cosmos: sum of per-container RU/s, peak normalized use, 2x-peak target'
        Assert ((Get-Row $base 'vm-api-01').reason -match 'under 3\.3% in 95% of hours') 'oversized VM: 95th percentile of hourly averages'
        Assert ((Get-Row $base 'vm-api-01').reason -match 'memory peaked at 35% used, so it fits in half the size') 'oversized VM: worst-hour memory checked'
        Assert-Equal 'medium' (Get-Row $base 'vm-batch-old').confidence 'oversized VM with no memory data'
        Assert ((Get-Row $base 'vm-batch-old').reason -match 'memory is not reported') 'no memory data is said plainly'
        Assert ((Get-Row $base 'mlw-research/cpu-cluster').reason -match 'at least 2 idle node\(s\) \(8 cores\)') 'ML: per-cluster minimum idle nodes and cores'
        Assert ((Get-Row $base 'stdevlogs').reason -match '500 GiB as RA-GRS.*LRS keeps') 'storage: capacity and the target redundancy'
        $amr = Get-Row $base 'amr-sessions-legacy'
        Assert ($amr.reason -match 'Azure Managed Redis Balanced B5, high availability, 2 instances') 'Managed Redis: kind, SKU and instance count'
        Assert ($amr.referenceCommandNotExecuted -match '^az redisenterprise delete') 'Managed Redis uses the redisenterprise command'
        Assert ($amr.suggestedAction -match 'turning off high availability halves') 'Managed Redis with HA: mention the dev/test option'
        $sbs = Get-Row $base 'sb-dev-notifications'
        Assert ($sbs.reason -match 'Service Bus Standard, 1 base unit\), but the base unit bills every hour') 'Service Bus Standard: billed by its base unit'
        Assert ($sbs.suggestedAction -notmatch 'scale it down') 'Service Bus Standard has no units to scale down'
        Assert ((Get-Row $base 'sb-legacy-orders').suggestedAction -match 'scale it down to the fewest units') 'Service Bus Premium can still scale down'
    }
    Test 'Scale set instances: per-instance deallocate command; AKS nodes go through the node pool at medium confidence' {
        $inst = Get-Row $base 'vmss-web_3'
        Assert-Equal 'az vmss deallocate --resource-group rg-web --name vmss-web --instance-ids 3' $inst.referenceCommandNotExecuted 'instance command names the set and instance id'
        Assert-Equal 'high' $inst.confidence 'plain scale set instance'
        $aks = Get-Row $base 'aks-nodepool1-12345678-vmss_1'
        Assert-Equal 'medium' $aks.confidence 'AKS node'
        Assert ($aks.referenceCommandNotExecuted -match '^az aks nodepool scale') 'AKS node is fixed on the node pool'
        Assert ($aks.suggestedAction -match "Don't deallocate it directly") 'AKS node: warn against deallocating the instance'
    }
    Test 'Costs: deterministic offline prices and billed costs' {
        $cases = [ordered]@{ 'vm-win-jumpbox' = '97.53'; 'nat-dev-unused' = '32.85'; 'sql-legacy/reporting-old' = '147.17'; 'lb-old-web' = '18.25'
                             'vm-build-agent-02' = '276.48'; 'oai-research/gpt-ptu-eval' = '10950'; 'ca-orders-legacy' = '46.66'; 'crlegacybuild' = '100'
                             'disk-sql-data-old' = '135.18'; 'asp-legacy-api' = '248.2'
                             'ddos-legacy-plan' = '2943.55'; 'asp-intranet-old' = '219'; 'asp-free-stopped' = '0'; 'fw-hub-legacy' = '1277.5'; 'fw-dev-dnat' = '912.5'
                             'cosmos-orders-legacy' = '186.88'; 'cosmos-dev-idle' = '70.08'; 'fab-analytics' = '8409.6'; 'syn-ws/dw-legacy' = '5511.5'
                             'adx-telemetry' = '2020.64'; 'pbi-reports' = '1465.91'; 'pbi-legacy' = '735.91'; 'redis-session-old' = '100.74'; 'amr-sessions-legacy' = '227.76'; 'evh-dev-unused' = '10.95'; 'sb-dev-notifications' = '9.81'; 'apim-legacy' = '48.03'
                             'mlw-research/cpu-cluster' = '292'; 'pe-st-deleted' = '7.3'; 'ippre-legacy' = '70.08'; 'afd-old-site' = '35'; 'tm-unused' = '0'
                             'vm-dev-api' = '90.1'; 'vm-batch-old' = '70.08'; 'vm-win-app01' = '134.32'; 'sqlsrv-erp/erp' = '587.5'; 'stdevlogs' = '15.6'; 'snap-sql-daily-premium' = '35.84'; 'snap-build-weekly-03' = '12.8'; 'vm-api-01' = '280.32'
                             'vmss-web_3' = '70.08'; 'aks-nodepool1-12345678-vmss_1' = '140.16' }
        foreach ($k in $cases.Keys) { Assert-Equal $cases[$k] (Get-Row $base $k).monthlyCost "$k monthly cost" }
        Assert ((Get-Row $base 'vm-build-agent-02').costSource -like 'billed*') 'vm-build-agent-02 should use billed cost'
        Assert ((Get-Row $base 'asp-legacy-api').costSource -eq 'advisor') 'asp-legacy-api should use the merged Advisor figure'
        Assert-Equal '' (Get-Row $base 'log-security-archive').monthlyCost 'Log Analytics cost (must be unknown, not 0)'
        Assert-Equal '' (Get-Row $base 'rsv-dev/vm-old01').monthlyCost 'backup cost (must be unknown, not 0)'
        Assert-Equal '' (Get-Row $base 'rsv-dev/vm-old01/billing').monthlyCost 'database backup cost (must be unknown, not 0)'
        Assert-Equal 'True' (Get-Row $base 'asp-intranet-old').commitmentCaveat 'stopped-app plan cost can be covered by a commitment'
        Assert-Equal '' (Get-Row $base 'Standard_D4s_v5 (bbbbbbbb)').monthlyCost 'reservation cost (price not readable: unknown, not 0)'
        foreach ($n in 'cosmos-orders-legacy', 'vm-dev-api', 'vm-win-app01', 'stdevlogs', 'mlw-research/batch-cluster') {
            Assert ((Get-Row $base $n).costSource -like 'estimated*') "$n is a partial saving, priced as the difference"
        }
    }
    Test 'Advisor: a recommendation for an already-found resource is merged, not listed twice' {
        Assert (-not ($base.Rows | Where-Object { $_.wasteType -eq 'advisor-cost' -and $_.name -eq 'asp-legacy-api' })) 'asp-legacy-api appears twice'
        Assert ((Get-Row $base 'asp-legacy-api').reason -match 'corroborated by Advisor') 'merged finding should say corroborated by Advisor'
    }
    Test 'Idle: VM idle time comes from the second 30-day metrics window (no 30-day clipping)' {
        Assert-Equal '47' (Get-Row $base 'vm-build-agent-02').idleDays 'vm-build-agent-02 idle days'
        Assert ((Get-Row $base 'vm-win-jumpbox').idleSource -match '90\+') 'jumpbox with no CPU data should be 90+'
        Assert-Equal '12' (Get-Row $base 'vmss-web_3').idleDays 'scale set instance idle days come from its last CPU datapoint too'
        Assert ((Get-Row $base 'aks-nodepool1-12345678-vmss_1').idleSource -match '90\+') 'AKS node with no CPU data should be 90+'
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
                'idle-openai-deployment', 'idle-bastion', 'idle-sql-database', 'premium-disk-deallocated-vm', 'idle-firewall',
                'overprovisioned-cosmos-db', 'idle-data-platform', 'idle-redis-cache', 'idle-messaging-namespace', 'idle-api-management', 'idle-ml-compute',
                'nonprod-geo-redundant-storage', 'underused-vm'
        Assert (-not ($r.Rows | Where-Object { $_.wasteType -in $cand })) 'candidate types must be absent'
        Assert ($r.Report -match 'not checked because of -SkipMetrics') 'missing -SkipMetrics warning'
    }
    Test 'Changes: resolved, new, excluded and not-rechecked are told apart' -Group 'history' {
        $parent = Join-Path $Work 'history'
        Copy-BaseRun $parent '20261101-000000' | Out-Null
        $fx = Copy-Fixtures 'history'
        Edit-Fixture $fx '03-unassociated-public-ips.json' { param($d) @($d | Where-Object { $_.name -ne 'pip-old-lb-frontend' }) }
        Edit-Fixture $fx '13-idle-load-balancers.json' { param($d) foreach ($x in $d) { if ($x.name -eq 'lb-old-web') { $x.ignored = 1 } }; $d }
        Edit-Fixture $fx '19-empty-resource-groups.json' { param($d) $n = $d[0] | ConvertTo-Json -Depth 5 | ConvertFrom-Json; $n.name = 'rg-new'; $n.id = $n.id -replace 'rg-old-poc', 'rg-new'; @($d) + $n }
        Set-Content (Join-Path $fx '06-old-snapshots.json') 'not json'      # this query now fails
        $r = Invoke-Run $fx '20261108-000000' @() $parent
        Assert ($r.Report -match '\*\*Resolved\*\* \(gone, and rechecked this time\) \| 1 \|') 'one resolved'
        Assert ($r.Report -match 'Resolved:\*\* pip-old-lb-frontend') 'pip-old-lb-frontend resolved'
        Assert ($r.Report -match 'Now excluded \(ignore tag or exclusions file\) \| 1 \|') 'one now excluded'
        Assert ($r.Report -match 'Not rechecked this time [^|]*\| 2 \|') 'two snapshots not rechecked (failed query is not "resolved")'
        Assert-Equal 'new' (Get-Row $r 'rg-new').status 'new resource group status'
        Assert-Equal 'open' (Get-Row $r 'vm-win-jumpbox').status 'unchanged finding status'
    }
    Test 'Changes: a failed query that emits two waste types leaves both "not rechecked"' {
        # Query 22 emits orphaned-vm-backup and orphaned-workload-backup through iff(); the runner must
        # read both names from it, or a failure would report the workload backup as resolved
        $parent = Join-Path $Work 'two-types'
        Copy-BaseRun $parent '20261101-000000' | Out-Null
        $fx = Copy-Fixtures 'two-types'
        Set-Content (Join-Path $fx '22-orphaned-vm-backups.json') 'not json'
        $r = Invoke-Run $fx '20261108-000000' @() $parent
        Assert ($r.Report -match '\*\*Resolved\*\* \(gone, and rechecked this time\) \| 0 \|') 'nothing resolved by a failed query'
        Assert ($r.Report -match 'Not rechecked this time [^|]*\| 2 \|') 'both backup findings not rechecked'
    }
    Test 'Changes: a second scan where nothing changed works (empty lists must not crash)' {
        $parent = Join-Path $Work 'stable'
        Copy-BaseRun $parent '20261101-000000' | Out-Null
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
    # Retry and caching (Set-Faults and Get-AzStats are in TestHelpers.ps1)
    $throttle = 'ERROR: (TooManyRequests) Too many requests. Please retry after 1 seconds. Code: RateLimiting'
    Test 'Retry: throttled and transient az errors are retried; sign-in errors are not; repeated metric reads are cached' {
        $fx = Copy-Fixtures 'retry'
        # A second Premium disk on vm-retired-app: its CPU history must come from the cache
        Edit-Fixture $fx '18-premium-disks-on-deallocated-vms.json' { param($d)
            $n = $d[0] | ConvertTo-Json -Depth 8 | ConvertFrom-Json; $n.name = 'vm-retired-app_data1'; $n.id = $n.id -replace '_OsDisk$', '_data1'; @($d) + $n }
        Set-Faults $fx @(
            @{ cmd = 'graph query'; match = '01-unattached-disks'; failures = 2; stderr = $throttle }
            @{ cmd = 'monitor metrics list'; match = 'bas-dev'; failures = 1; stderr = 'ERROR: (ServiceUnavailable) The service is temporarily unavailable. Status 503' }
            @{ cmd = 'graph query'; match = '02-orphaned-nics'; failures = 1; stderr = "ERROR: AADSTS700082: The refresh token has expired. Run 'az login'." })
        $r = Invoke-Run $fx 'retry' -KeepParallel
        foreach ($n in 'disk-sql-data-old', 'bas-dev', 'vm-retired-app_OsDisk', 'vm-retired-app_data1') { Get-Row $r $n | Out-Null }
        Assert ($r.Report -match '02-orphaned-nics\.kql: az graph query failed \(exit 1\): ERROR: AADSTS700082') 'a sign-in error must fail at once, not be retried'
        Assert (-not ($r.Rows | Where-Object { $_.wasteType -eq 'orphaned-nic' })) 'orphaned NICs should be missing (their query failed)'
        Assert ($r.Report -match '\| partial \|') 'tenant with a failed query should be partial'
        $s = Get-AzStats $r
        Assert-Equal 3 $s.Retried 'retried calls (2 throttled graph pages + 1 metrics 503)'
        Assert ($r.Report -match 'retried after throttling or a transient error \(graph query x2, monitor metrics list x1\)') 'retries should be listed per command'
        Assert ($s.Cached -ge 3) "second disk on the same VM should read its 3 CPU windows from the cache (cached: $($s.Cached))"
    }
    Test 'Retry: throttling that outlasts every attempt fails the query (partial), never a silent clean result' {
        $fx = Copy-Fixtures 'retry-max'
        Set-Faults $fx @(@{ cmd = 'graph query'; match = '01-unattached-disks'; failures = 4; stderr = $throttle })
        $r = Invoke-Run $fx 'retry-max' -KeepParallel
        Assert ($r.Report -match '01-unattached-disks\.kql: az graph query failed') 'query should fail after the last attempt'
        Assert ($r.Report -match '\| partial \|') 'tenant should be partial'
        Assert-Equal 3 (Get-AzStats $r).Retried 'retries before giving up (4 attempts)'
    }
    Test 'Errors: a missing resource-graph extension fails the tenant with the fix, and is not retried' {
        $fx = Copy-Fixtures 'no-extension'
        # Real az 2.x output with extension.use_dynamic_install=no (which the runner sets)
        Set-Faults $fx @(@{ cmd = 'graph query'; match = 'coverage-check'; failures = 1
            stderr = "ERROR: 'graph' is misspelled or not recognized by the system.`nIf the command is from an extension, please make sure the corresponding extension is installed." })
        $r = Invoke-Run $fx 'no-extension'
        Assert ($r.Report -match '\| failed \|') 'tenant should be failed'
        Assert ($r.Report -match 'az extension add -n resource-graph') 'report should name the fix'
        Assert-Equal 0 (Get-AzStats $r).Retried 'retries for a missing extension'
        Assert ((Get-Content $Runner -Raw) -match "\`$env:AZURE_EXTENSION_USE_DYNAMIC_INSTALL = 'no'") 'runner must disable dynamic extension install'
    }
    Test 'Parallel: -Parallel 1 and the default give the same findings and costs' {
        $r = Invoke-Run $Fixtures 'serial' @('-Parallel', '1')
        $a = @($base.Rows | ForEach-Object { "$($_.wasteType)|$($_.name)|$($_.monthlyCost)|$($_.confidence)" } | Sort-Object) -join "`n"
        $b = @($r.Rows | ForEach-Object { "$($_.wasteType)|$($_.name)|$($_.monthlyCost)|$($_.confidence)" } | Sort-Object) -join "`n"
        Assert ($a -eq $b) 'serial and parallel runs differ'
        Assert ($r.Report -match 'Metric checks ran 1 at a time') 'report should state the parallelism'
    }
    Test 'Trends: savings over time, time to resolve and oldest open across three scans' {
        $parent = Join-Path $Work 'trends'
        $now = [DateTime]::UtcNow
        # Backdate a finished scan: its generated time, and (optionally) first-seen and resolved dates
        $backdate = { param([string] $dir, [int] $days, [bool] $firstSeen)
            $p = Join-Path $dir 'findings.json'; $j = Get-Content $p -Raw | ConvertFrom-Json -AsHashtable -DateKind String
            $j.meta.generated = $now.AddDays(-$days).ToString('o')
            if ($firstSeen) { foreach ($f in $j.findings) { $f.firstSeen = $now.AddDays(-$days).ToString('yyyy-MM-dd') } }
            foreach ($r in @($j.resolved)) { if ($r) { $r.resolvedOn = $now.AddDays(-$days).ToString('yyyy-MM-dd') } }
            $j | ConvertTo-Json -Depth 8 | Set-Content $p }
        $r1 = Copy-BaseRun $parent 'scan1'
        & $backdate $r1.Dir 60 $true
        $fx2 = Copy-Fixtures 'trends2'
        Edit-Fixture $fx2 '03-unassociated-public-ips.json' { param($d) @($d | Where-Object { $_.name -ne 'pip-old-lb-frontend' }) }
        $r2 = Invoke-Run $fx2 'scan2' @() $parent
        & $backdate $r2.Dir 30 $false                     # resolved pip-old-lb-frontend 30 days after first seen
        $fx3 = Copy-Fixtures 'trends3'
        Edit-Fixture $fx3 '03-unassociated-public-ips.json' { param($d) @($d | Where-Object { $_.name -ne 'pip-old-lb-frontend' }) }
        Edit-Fixture $fx3 '13-idle-load-balancers.json' { param($d) @($d | Where-Object { $_.name -ne 'lb-old-web' }) }
        $r3 = Invoke-Run $fx3 'scan3' @() $parent          # resolves lb-old-web, 60 days after first seen
        Assert ($r3.Report -match '## Trends') 'trends section missing'
        Assert ($r3.Report -match '3 scan\(s\) of this scope') 'expected 3 scans'
        Assert ($r3.Report -match "\| $($now.AddDays(-60).ToString('yyyy-MM-dd')) <sub>scan1</sub> \| \d+ \| [^|]+ \| [^|]+ \| - \| - \|") 'baseline scan row shows - for new/resolved'
        Assert ($r3.Report -match "\| $($now.AddDays(-30).ToString('yyyy-MM-dd')) <sub>scan2</sub> \| \d+ \| [^|]+ \| [^|]+ \| 0 \| 1 \|") 'second scan: 0 new, 1 resolved'
        Assert ($r3.Report -match '\(this scan\)\*\* \| \d+ \| [^|]+ \| [^|]+ \| 0 \| 1 \|') 'this scan: 0 new, 1 resolved'
        Assert ($r3.Report -match 'median 45 day\(s\) from first seen to resolved, over 2 resolved finding\(s\)') 'median of 30 and 60 days'
        Assert ($r3.Report -match 'open 60 day\(s\) since') 'oldest open findings, 60 days'
        $csv = @(Import-Csv (Join-Path $r3.Dir 'trends.csv'))
        Assert-Equal 3 $csv.Count 'rows in trends.csv'
        Assert-Equal 1 @($r3.Json.resolved | Where-Object { $_ }).Count 'findings this scan resolved, recorded in findings.json'
        Assert ($r3.Html -match '<h2>Trends</h2>') 'trends missing from the HTML'
        Assert (-not ($r1.Report -match '## Trends')) 'a baseline scan has no trends'
    }
    Test 'Changes: -Compare none skips the comparison' -Group 'history' {   # after the test above: its scans are in 'history'
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
    Test 'Quick wins: high-confidence, reversible or dependency-free findings only, most costly first' {
        Assert ($base.Report -match '(?s)## Quick wins: [\d,.]+ USD/month(.*?)\n## ') 'Quick wins section missing'
        $qw = $Matches[1]
        foreach ($n in 'ddos-legacy-plan', 'afd-old-site', 'syn-ws/dw-legacy', 'mlw-research/cpu-cluster', 'cosmos-dev-idle', 'vmss-web_3') { Assert ($qw -match [regex]::Escape("[$n]")) "$n should be a quick win" }
        foreach ($n in 'stmediaarchive', 'disk-sql-data-old', 'rsv-dev/vm-old01', 'redis-session-old', 'sb-legacy-orders', 'pe-sql-rejected', 'fab-analytics', 'tm-unused', 'vm-dev-api', 'aks-nodepool1-12345678-vmss_1') {
            Assert ($qw -notmatch [regex]::Escape("[$n]")) "$n must not be a quick win (data store, dependency, not high confidence, or free)"
        }
        Assert-Equal 15 ([regex]::Matches($qw, '(?m)^\| \[')).Count 'quick wins are capped at 15'
        Assert ($qw.IndexOf('[syn-ws/dw-legacy]') -lt $qw.IndexOf('[afd-old-site]')) 'quick wins should be ordered by cost'
        Assert ($base.Html -match '<h2>Quick wins: ') 'quick wins missing from the HTML'
    }
    Test 'Owners: each owner also gets a short markdown summary to paste' {
        $md = @(Get-ChildItem (Join-Path $base.Dir 'by-owner') -Filter '*.md')
        $csv = @(Get-ChildItem (Join-Path $base.Dir 'by-owner') -Filter '*.csv')
        Assert-Equal $csv.Count $md.Count 'one summary per owner CSV'
        $t = Get-Content (Join-Path $base.Dir 'by-owner/api-team@example.com.md') -Raw
        Assert ($t -match '# Azure cleanup candidates for api-team@example\.com') 'summary title'
        Assert ($t -match 'nothing in Azure was changed') 'summary says nothing was changed'
        foreach ($n in 'vm-api-01', 'asp-legacy-api', 'vm-dev-api', 'apim-legacy') { Assert ($t -match [regex]::Escape("**$n**")) "summary should list $n" }
        Assert ($t.IndexOf('**vm-api-01**') -lt $t.IndexOf('**apim-legacy**')) 'summary sorted by cost'
    }
    Test 'Reservations: orders found in usage records are checked; bad or unreadable orders are reported, never "resolved"' {
        Assert ($base.Report -match 'Reservation orders checked: 1 ') 'the order in the usage record should be found and checked'
        Assert ((Get-Row $base 'Standard_D4s_v5 (bbbbbbbb)').reason -match 'Used 30% of its reserved hours') 'utilization from reserved vs used hours'
        $log = & pwsh -NoProfile -File $Runner -FixtureDir $Fixtures -OfflinePricing -OutDir (Join-Path $Work 'res-bad') -ReservationOrder 'not-a-guid' 2>&1 | Out-String
        Assert ($LASTEXITCODE -eq 2 -and $log -match 'is not a reservation order ID') "a malformed -ReservationOrder must stop the run: $log"
        $r = Invoke-Run $Fixtures 'res-unknown' @('-ReservationOrder', 'dddddddd-1111-2222-3333-444444444444')
        Assert ($r.Report -match "Couldn't read the utilization of reservation order dddddddd-") 'an unreadable order should be a warning'
        Assert ($r.Report -match 'Reservation orders checked: 2 ') 'both orders tried'
        # A later scan that doesn't see the order (no usage read) must not call its finding resolved
        $parent = Join-Path $Work 'res-history'
        Copy-BaseRun $parent '20261101-000000' | Out-Null
        $r2 = Invoke-Run $Fixtures '20261108-000000' @('-SkipConsumption') $parent
        Assert ($r2.Report -match 'Reservation orders checked: 0 ') 'no usage read, so no order found'
        Assert ($r2.Report -match '\*\*Resolved\*\* \(gone, and rechecked this time\) \| 0 \|') 'an unchecked reservation is not resolved'
        Assert ($r2.Report -match 'Not rechecked this time [^|]*\| 1 \|') 'the reservation finding is not rechecked'
    }
    Test 'Exclusions health: gone resources, resources no longer flagged, and entries about to expire' {
        $clock = [DateTime]::Parse((Get-Content (Join-Path $Fixtures 'clock.json') -Raw | ConvertFrom-Json -AsHashtable -DateKind String)['now'], [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles] 'AdjustToUniversal, AssumeUniversal')
        $excl = Join-Path $Work 'excl-health.json'
        @{ exclusions = @(
            @{ id = '/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-web/providers/Microsoft.Web/sites/app-portal'; reason = 'old hold' }   # exists, not flagged
            @{ id = '/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-legacy/providers/Microsoft.Compute/disks/disk-gone'; reason = 'old hold' }       # gone
            @{ id = (Get-Row $base 'afd-old-site').resourceId; reason = 'launch in December'; until = $clock.AddDays(5).ToString('yyyy-MM-dd') }) } |                     # expires soon
            ConvertTo-Json -Depth 5 | Set-Content $excl
        $r = Invoke-Run $Fixtures 'excl-health' @('-ExclusionsFile', $excl)
        Assert ($r.Report -match "app-portal' matched nothing in this scan: the resource still exists but isn't flagged any more") 'exists but not flagged'
        Assert ($r.Report -match "disk-gone' matched nothing in this scan: the resource no longer exists") 'resource gone'
        Assert ($r.Report -match "afd-old-site' expires on $($clock.AddDays(5).ToString('yyyy-MM-dd')), in [45] day\(s\) \(launch in December\)") 'expiring soon'
        Assert (-not ($r.Rows | Where-Object { $_.name -eq 'afd-old-site' })) 'still excluded until it expires'
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

    Invoke-QueuedTests @{ Work = $Work; Fixtures = $Fixtures; Runner = $Runner; SkillDir = $SkillDir; RepoDir = $RepoDir; TestsDir = $TestsDir
                          base = $base; expected = $expected; throttle = $throttle }
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
