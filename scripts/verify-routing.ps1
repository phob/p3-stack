# Verifies that /p3-mode can route to the skills it names under Claude Code:
# workflows through the Skill tool, flagged principle-* leaves by reading their SKILL.md.
# T1-T3 are static and installer checks; T4-T6 run headless `claude -p` sessions in a temp project.
[CmdletBinding()]
param(
    [string]$OutDir = (Join-Path $env:TEMP "p3-verify-$(Get-Date -Format 'yyyyMMdd-HHmmss')"),
    [switch]$All,
    [switch]$StaticOnly,
    [switch]$RoutingOnly,
    [switch]$RoutingControl,
    [int]$RoutingRuns = 2,
    [int]$Throttle = 4,
    [string]$Model = 'claude-sonnet-5-5',
    [string]$RoutingModel = 'claude-opus-5-5',
    [switch]$KeepProject
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = Split-Path $PSScriptRoot -Parent
$skillsDir = Join-Path $repo 'skills'
$entryPoints = @('p3-mode', 'setup-p3')
$defaultList = @(
    'how', 'why', 'architect', 'swarm', 'arena', 'interrogate', 'unslop', 'no-comments',
    'technical-writing', 'benchmark-checklist', 'show-me-your-work', 'figure-it-out', 'tdd'
)
$negativeList = @($entryPoints + 'principle-prove-it-works')

$logDir = Join-Path $OutDir 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$results = [System.Collections.Generic.List[object]]::new()

function Add-Result([string]$Test, [string]$Case, [string]$Result, [string]$Detail) {
    $results.Add([pscustomobject]@{ Test = $Test; Case = $Case; Result = $Result; Detail = $Detail })
}

function Get-Frontmatter([string]$Path) {
    $lines = Get-Content -LiteralPath $Path
    if ($lines.Count -lt 2 -or $lines[0].Trim() -ne '---') { return $null }
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq '---') { return ($lines[1..($i - 1)] -join "`n") }
    }
    return $null
}

function Test-Flagged([string]$Path) {
    $fm = Get-Frontmatter $Path
    return ($null -ne $fm) -and ($fm -match '(?m)^\s*disable-model-invocation:\s*true\s*$')
}

$skillNames = @(Get-ChildItem -Directory -Path $skillsDir | Where-Object { Test-Path (Join-Path $_.FullName 'SKILL.md') } | ForEach-Object Name)
$skillFileCountBefore = @(Get-ChildItem -Path $skillsDir -Recurse -File).Count
# Principles stay flagged so their descriptions stay out of every session's skill listing.
$userOnly = @($entryPoints + @($skillNames | Where-Object { $_ -like 'principle-*' }))

# T1 static-flag
$flagged = @($skillNames | Where-Object { Test-Flagged (Join-Path $skillsDir "$_\SKILL.md") })
$missingFm = @($skillNames | Where-Object { $null -eq (Get-Frontmatter (Join-Path $skillsDir "$_\SKILL.md")) })
$unexpected = @($flagged | Where-Object { $_ -notin $userOnly })
$unflaggedEntry = @($userOnly | Where-Object { $_ -notin $flagged })
if ($unexpected.Count -eq 0 -and $unflaggedEntry.Count -eq 0 -and $missingFm.Count -eq 0) {
    Add-Result 'T1 static-flag' "$($skillNames.Count) skills" 'PASS' "flagged: $($flagged -join ', ')"
} else {
    Add-Result 'T1 static-flag' "$($skillNames.Count) skills" 'FAIL' "unexpected flag: [$($unexpected -join ', ')]; entry not flagged: [$($unflaggedEntry -join ', ')]; no frontmatter: [$($missingFm -join ', ')]"
}

# T2 static-refs
$refs = [System.Collections.Generic.SortedSet[string]]::new()
foreach ($md in Get-ChildItem -Path (Join-Path $skillsDir 'p3-mode') -Recurse -Filter '*.md') {
    $text = Get-Content -LiteralPath $md.FullName -Raw
    foreach ($pattern in 'the \*\*([a-z0-9-]+)\*\* skill', '\*\*(principle-[a-z0-9-]+)\*\*', '`/([a-z0-9-]+)`') {
        foreach ($m in [regex]::Matches($text, $pattern)) { [void]$refs.Add($m.Groups[1].Value) }
    }
}
$badRefs = @($refs | Where-Object {
        $path = Join-Path $skillsDir "$_\SKILL.md"
        -not (Test-Path $path) -or (($_ -notin $userOnly) -and (Test-Flagged $path))
    })
if ($refs.Count -gt 0 -and $badRefs.Count -eq 0) {
    Add-Result 'T2 static-refs' "$($refs.Count) refs" 'PASS' ($refs -join ', ')
} else {
    Add-Result 'T2 static-refs' "$($refs.Count) refs" 'FAIL' "missing or flagged: $($badRefs -join ', ')"
}

# T3 installer
$project = Join-Path $env:TEMP "p3-verify-proj-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
New-Item -ItemType Directory -Force -Path $project | Out-Null

function Invoke-Installer([string]$Label) {
    Push-Location $repo
    try {
        $out = & pwsh -NoProfile -File (Join-Path $repo 'install.ps1') -Project $project 2>&1 | ForEach-Object { "$_" }
        $code = $LASTEXITCODE
    } finally { Pop-Location }
    $out | Set-Content (Join-Path $logDir "T3-install-$Label.txt")
    return [pscustomobject]@{ Output = @($out); ExitCode = $code }
}

function Get-LinkProblems([string]$Sub, [string[]]$Except) {
    foreach ($name in $skillNames | Where-Object { $_ -notin $Except }) {
        $item = Get-Item -LiteralPath (Join-Path $project "$Sub\$name") -Force -ErrorAction SilentlyContinue
        if (-not $item) { "$Sub\$name missing"; continue }
        if ($item.LinkType -ne 'Junction') { "$Sub\$name is not a junction ($($item.LinkType))"; continue }
        $target = [System.IO.Path]::GetFullPath(@($item.Target)[0]).TrimEnd('\')
        $want = [System.IO.Path]::GetFullPath((Join-Path $skillsDir $name)).TrimEnd('\')
        if ($target -ne $want) { "$Sub\$name -> $target, want $want" }
    }
}

$realDir = Join-Path $project '.agents\skills\how'
New-Item -ItemType Directory -Force -Path $realDir | Out-Null
Set-Content -Path (Join-Path $realDir 'marker.txt') -Value 'user-owned'

$run1 = Invoke-Installer 'run1-with-real-dir'
$problems = @(
    if ($run1.ExitCode -ne 0) { "exit $($run1.ExitCode)" }
    if (-not ($run1.Output -match 'WARNING: skip how in .*\.agents\\skills')) { 'no skip warning for .agents\skills\how' }
    if ($run1.Output -match 'WARNING: skip how in .*\.claude\\skills') { '.claude\skills\how was skipped' }
    $realItem = Get-Item -LiteralPath $realDir -Force
    if ($realItem.LinkType) { '.agents\skills\how was replaced by a link' }
    if (-not (Test-Path (Join-Path $realDir 'marker.txt'))) { 'user dir content lost' }
    Get-LinkProblems '.claude\skills' @()
    Get-LinkProblems '.agents\skills' @('how')
)
Add-Result 'T3 installer' 'real dir skipped, rest linked' ($(if ($problems) { 'FAIL' } else { 'PASS' })) ($(if ($problems) { $problems -join '; ' } else { ($run1.Output | Where-Object { $_ -match 'WARNING|linked' }) -join ' | ' }))

Remove-Item -LiteralPath $realDir -Recurse -Force
foreach ($label in 'run2-complete', 'run3-idempotent') {
    $run = Invoke-Installer $label
    $problems = @(
        if ($run.ExitCode -ne 0) { "exit $($run.ExitCode)" }
        if ($run.Output -match 'WARNING|ERROR|Exception') { "unexpected output: $($run.Output -join ' | ')" }
        if (@($run.Output -match "^linked $($skillNames.Count) skills into").Count -ne 2) { "summary lines: $($run.Output -join ' | ')" }
        Get-LinkProblems '.claude\skills' @()
        Get-LinkProblems '.agents\skills' @()
    )
    Add-Result 'T3 installer' $label ($(if ($problems) { 'FAIL' } else { 'PASS' })) ($(if ($problems) { $problems -join '; ' } else { 'all junctions in .claude and .agents' }))
}

$viaLink = Get-Content -LiteralPath (Join-Path $project '.claude\skills\how\SKILL.md') -Raw
$direct = Get-Content -LiteralPath (Join-Path $skillsDir 'how\SKILL.md') -Raw
Add-Result 'T3 installer' 'how\SKILL.md resolves to worktree' ($(if ($viaLink -eq $direct) { 'PASS' } else { 'FAIL' })) ''

function Get-RunFacts([string]$LogPath) {
    $facts = [pscustomobject]@{
        SkillCalls = [System.Collections.Generic.List[string]]::new()
        Refusals   = [System.Collections.Generic.List[string]]::new()
        BaseDirs   = [System.Collections.Generic.List[string]]::new()
        SkillUseIds = [System.Collections.Generic.HashSet[string]]::new()
        # Principle SKILL.md paths opened by any tool (Read, cat, Get-Content), since all of them load the leaf.
        PrincipleOpens = [System.Collections.Generic.SortedSet[string]]::new()
        ToolInputs = [System.Collections.Generic.List[string]]::new()
        InitSkills = @()
        Final      = ''
        Subtype    = ''
        Cost       = 0.0
        DurationMs = 0
        Turns      = 0
    }
    foreach ($line in Get-Content -LiteralPath $LogPath) {
        if (-not $line.StartsWith('{')) { continue }
        $ev = $line | ConvertFrom-Json -Depth 64
        switch ($ev.type) {
            'system' { if ($ev.subtype -eq 'init') { $facts.InitSkills = @($ev.skills) } }
            'result' {
                $facts.Final = [string]$ev.result
                $facts.Subtype = [string]$ev.subtype
                $facts.Cost = [double]$ev.total_cost_usd
                $facts.DurationMs = [int]$ev.duration_ms
                $facts.Turns = [int]$ev.num_turns
            }
            'assistant' {
                foreach ($block in @($ev.message.content)) {
                    if ($block.type -ne 'tool_use') { continue }
                    $facts.ToolInputs.Add("$($block.name) $($block.input | ConvertTo-Json -Compress -Depth 8)")
                    if ($block.name -eq 'Skill') {
                        $facts.SkillCalls.Add([string]$block.input.skill)
                        [void]$facts.SkillUseIds.Add([string]$block.id)
                    }
                    foreach ($m in [regex]::Matches(($block.input | ConvertTo-Json -Compress -Depth 8), '(principle-[a-z0-9-]+)[\\/]+SKILL\.md')) { [void]$facts.PrincipleOpens.Add($m.Groups[1].Value) }
                }
            }
            'user' {
                $content = $ev.message.content
                $blocks = if ($content -is [string]) { @([pscustomobject]@{ type = 'text'; text = $content }) } else { @($content) }
                foreach ($block in $blocks) {
                    if ($block.type -eq 'tool_result') {
                        $text = if ($block.content -is [string]) { $block.content } else { (@($block.content) | ForEach-Object { $_.text }) -join "`n" }
                        # Only Skill results count: a principle's own frontmatter also contains the flag name.
                        if ($facts.SkillUseIds.Contains([string]$block.tool_use_id) -and $text -match 'disable-model-invocation') { $facts.Refusals.Add($text) }
                    } elseif ($block.type -eq 'text') {
                        foreach ($m in [regex]::Matches([string]$block.text, 'Base directory for this skill: (.+?)\r?(\n|$)')) { $facts.BaseDirs.Add($m.Groups[1].Value.Trim()) }
                    }
                }
            }
        }
    }
    return $facts
}

$claudeArgsBase = @('--setting-sources', 'project', '--no-session-persistence', '--output-format', 'stream-json', '--verbose', '--permission-mode', 'bypassPermissions')

function Invoke-ClaudeBatch([object[]]$Jobs) {
    $Jobs | ForEach-Object -ThrottleLimit $Throttle -Parallel {
        Set-Location $_.Cwd
        $a = @('-p', $_.Prompt) + $using:claudeArgsBase + @('--model', $_.Model, '--max-turns', "$($_.MaxTurns)")
        & claude @a 2>&1 | ForEach-Object { "$_" } | Set-Content -LiteralPath $_.Log
    }
}

$totalCost = 0.0
$e2eStart = Get-Date

if (-not $StaticOnly) {
    # Personal skills that p3-stack does not ship; their absence from a session's init proves personal skills were excluded.
    $personalOnly = @(Get-ChildItem -Path (Join-Path $HOME '.claude\skills') -Force -ErrorAction SilentlyContinue | ForEach-Object Name | Where-Object { $_ -notin $skillNames })

    $invokeList = if ($All) { @($skillNames | Where-Object { $_ -notin $userOnly }) } else { $defaultList }
    $prompt = { param($n) "Use the Skill tool to invoke the skill named ``$n``. After it loads, reply with exactly: LOADED $n. Do nothing else." }
    $jobs = @(if (-not $RoutingOnly) {
        foreach ($n in $invokeList) { [pscustomobject]@{ Test = 'T4'; Name = $n; Cwd = $project; Model = $Model; MaxTurns = 6; Prompt = (& $prompt $n); Log = (Join-Path $logDir "T4-$n.jsonl") } }
        foreach ($n in $negativeList) { [pscustomobject]@{ Test = 'T5'; Name = $n; Cwd = $project; Model = $Model; MaxTurns = 6; Prompt = (& $prompt $n); Log = (Join-Path $logDir "T5-$n.jsonl") } }
    })
    if ($jobs) { Invoke-ClaudeBatch $jobs }

    foreach ($job in $jobs) {
        $f = Get-RunFacts $job.Log
        $totalCost += $f.Cost
        $n = $job.Name
        $leaked = @($f.InitSkills | Where-Object { $_ -in $personalOnly })
        $wantBase = Join-Path $project ".claude\skills\$n"
        $problems = @(
            if ($f.InitSkills.Count -eq 0) { 'no init event' }
            if ($leaked) { "personal skills leaked: $($leaked -join ', ')" }
            if ($n -notin $f.SkillCalls) { "no Skill tool_use for $n (calls: $($f.SkillCalls -join ', '))" }
            if ($job.Test -eq 'T4') {
                if ($f.Refusals.Count -gt 0) { "refused: $($f.Refusals[0])" }
                if ($f.Final -notmatch [regex]::Escape("LOADED $n")) { "final text: $($f.Final)" }
                if ($wantBase -notin $f.BaseDirs) { "loaded from: [$($f.BaseDirs -join ', ')], want $wantBase" }
            } else {
                if ($f.Refusals.Count -eq 0) { 'Skill call was not refused with disable-model-invocation' }
                if ($f.BaseDirs.Count -gt 0) { "skill content loaded anyway from $($f.BaseDirs -join ', ')" }
            }
        )
        $label = if ($job.Test -eq 'T4') { 'T4 e2e-invoke' } else { 'T5 e2e-negative' }
        $detail = if ($problems) { $problems -join '; ' } else { "{0} turns, {1:N1}s, `${2:N3}" -f $f.Turns, ($f.DurationMs / 1000), $f.Cost }
        Add-Result $label $n ($(if ($problems) { 'FAIL' } else { 'PASS' })) $detail
    }

    # T6 e2e-routing
    New-Item -ItemType Directory -Force -Path (Join-Path $project 'src') | Out-Null
    Copy-Item -LiteralPath (Join-Path $repo 'install.ps1') -Destination (Join-Path $project 'src\install.ps1')
    $question = 'how does src/install.ps1 decide where to link skills, and is the idempotency handling right? Investigation only, change nothing.'
    $routingJobs = @(1..$RoutingRuns | ForEach-Object { [pscustomobject]@{ Test = 'T6'; Name = "run$_"; Cwd = $project; Model = $RoutingModel; MaxTurns = 15; Prompt = "/p3-mode $question"; Log = (Join-Path $logDir "T6-run$_.jsonl") } })
    if ($RoutingControl) {
        $routingJobs += [pscustomobject]@{ Test = 'T6'; Name = 'control (no /p3-mode)'; Cwd = $project; Model = $RoutingModel; MaxTurns = 15; Prompt = $question; Log = (Join-Path $logDir 'T6-control.jsonl') }
    }
    Invoke-ClaudeBatch $routingJobs

    foreach ($job in $routingJobs) {
        $f = Get-RunFacts $job.Log
        $totalCost += $f.Cost
        $principleCalls = @($f.SkillCalls | Where-Object { $_ -like 'principle-*' })
        $principleReads = @($f.PrincipleOpens)
        $outside = @($f.BaseDirs | Where-Object { -not $_.StartsWith((Join-Path $project '.claude\skills')) })
        # -p stream-json does not echo the expanded slash command, so p3-mode is evidenced by the model opening files only p3-mode names.
        $p3Evidence = @($f.ToolInputs | Where-Object { $_ -match 'p3-mode[\\/]+(playbooks|references)' }).Count
        if ($job.Name -like 'control*') {
            Add-Result 'T6 e2e-routing' $job.Name 'INFO' ("Skill calls: [$($f.SkillCalls -join ', ')]; p3-mode file opens: $p3Evidence; end: $($f.Subtype), $($f.Turns) turns, `${0:N2}" -f $f.Cost)
            continue
        }
        $hard = @(
            if ('how' -notin $f.SkillCalls) { 'no Skill tool_use for how' }
            if ($principleCalls) { "Skill tool_use for flagged principles: $($principleCalls -join ', ')" }
            if ($f.Refusals.Count -gt 0) { "refused: $($f.Refusals -join ' | ')" }
            if ($outside) { "skill loaded from outside project: $($outside -join ', ')" }
        )
        $result = if ($hard) { 'FAIL' } elseif ($principleReads) { 'PASS' } else { 'FAIL' }
        $summary = "p3-mode file opens: $p3Evidence; Skill calls: [$($f.SkillCalls -join ', ')]; principle opens: [$($principleReads -join ', ')]; end: $($f.Subtype), $($f.Turns) turns, {0:N0}s, `${1:N2}" -f ($f.DurationMs / 1000), $f.Cost
        if ($hard) { $summary = ($hard -join '; ') + '; ' + $summary }
        elseif (-not $principleReads) { $summary = 'no principle-* SKILL.md opened; ' + $summary }
        Add-Result 'T6 e2e-routing' $job.Name $result $summary
    }
}

# T7 cleanup
$cleanup = @(
    if ($KeepProject) { "kept $project" }
    elseif (-not $project.StartsWith($env:TEMP)) { "refused to delete $project (outside TEMP)" }
    else {
        # Delete links non-recursively first so nothing behind a junction is ever touched.
        foreach ($sub in '.claude\skills', '.agents\skills') {
            foreach ($item in Get-ChildItem -LiteralPath (Join-Path $project $sub) -Force -ErrorAction SilentlyContinue) {
                if ($item.LinkType) { [System.IO.Directory]::Delete($item.FullName) }
            }
        }
        Remove-Item -LiteralPath $project -Recurse -Force
        if (Test-Path $project) { "$project still exists" }
    }
    $after = @(Get-ChildItem -Path $skillsDir -Recurse -File).Count
    if ($after -ne $skillFileCountBefore) { "repo skill file count changed: $skillFileCountBefore -> $after" }
)
Add-Result 'T7 cleanup' 'temp project removed, repo intact' ($(if ($cleanup -and -not $KeepProject) { 'FAIL' } else { 'PASS' })) ($cleanup -join '; ')

$table = $results | Format-Table -AutoSize -Wrap | Out-String -Width 400
$footer = "e2e cost: `${0:N2}; e2e wall time: {1:N0}s; logs: {2}" -f $totalCost, ((Get-Date) - $e2eStart).TotalSeconds, $logDir
Write-Output $table
Write-Output $footer
($table + "`n" + $footer) | Set-Content (Join-Path $OutDir 'results.txt')
$results | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $OutDir 'results.json')

$failed = @($results | Where-Object Result -eq 'FAIL').Count
exit ([int]($failed -gt 0))
