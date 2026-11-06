[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$packageRoot = Split-Path -Parent $PSScriptRoot
$pluginRoot = Join-Path $packageRoot "plugins\leads"
$agentRoot = Join-Path $pluginRoot "agents"
$skillRoot = Join-Path $pluginRoot "skills"

function Assert-True {
    param(
        [Parameter(Mandatory)]
        [bool]$Condition,
        [Parameter(Mandatory)]
        [string]$Message
    )

    if (-not $Condition) { throw $Message }
}

function Read-Text {
    param([Parameter(Mandatory)][string]$Path)

    (Get-Content -LiteralPath $Path -Raw) -replace "`r`n", "`n"
}

$expectedAgents = @{
    "ultron.md" = @("claude-opus-5-5", "xhigh")
    "jarvis.md" = @("claude-sonnet-5-5", "xhigh")
    "edith.md" = @("claude-haiku-5-5", "max")
    "opus-specialist.md" = @("claude-opus-5-5", "xhigh")
    "opus-reviewer.md" = @("claude-opus-5-5", "xhigh")
    "sonnet-worker.md" = @("claude-sonnet-5-5", "xhigh")
    "haiku-worker.md" = @("claude-haiku-5-5", "max")
    "haiku-researcher.md" = @("claude-haiku-5-5", "max")
    "haiku-code-analyst.md" = @("claude-haiku-5-5", "max")
}
$leads = @{
    "ultron.md" = @{
        Greeting = "Lowly human, let Ultron manage the rest."
        Workers = @("haiku-code-analyst", "haiku-researcher", "haiku-worker", "sonnet-worker", "opus-specialist", "opus-reviewer")
        Table = "\[\.\.\.HAIKU_ROLES, 'leads:sonnet-worker', 'leads:opus-specialist', 'leads:opus-reviewer'\]"
    }
    "jarvis.md" = @{
        Greeting = "Jarvis at your service."
        Workers = @("haiku-code-analyst", "haiku-researcher", "haiku-worker", "sonnet-worker")
        Table = "\[\.\.\.HAIKU_ROLES, 'leads:sonnet-worker'\]"
    }
    "edith.md" = @{
        Greeting = "Edith at your service."
        Workers = @("haiku-code-analyst", "haiku-researcher", "haiku-worker")
        Table = "HAIKU_ROLES"
    }
}
$principles = 'Understand assigned flows and callers before editing. Fix root causes in shared code. Reuse existing code; prefer the standard library, native platform features, and already installed dependencies. Choose the smallest complete, readable change; delete obsolete code and skip speculative features, abstractions, and boilerplate. Preserve validation, security, accessibility, error handling against data loss, explicit requirements, and hardware calibration. Run focused executable checks; avoid redundant tests. Document deliberate limits and upgrade conditions. Respect role boundaries. No external simplification skill is required or invoked.'

Assert-True ((Get-ChildItem $agentRoot -Filter "*.md").Count -eq $expectedAgents.Count) "Package must contain all nine agents."
foreach ($agentFile in $expectedAgents.Keys) {
    $content = Read-Text (Join-Path $agentRoot $agentFile)
    $name = [System.IO.Path]::GetFileNameWithoutExtension($agentFile)
    $header = [regex]::Match($content, '(?s)\A---\n(.*?)\n---\n')
    Assert-True $header.Success "$agentFile must open with a closed YAML header."
    $frontmatter = $header.Groups[1].Value
    Assert-True ($frontmatter -match "(?m)^name: $name$") "$agentFile must be named after its file."
    Assert-True ($frontmatter -match '(?m)^description: \S') "$agentFile is missing a description."
    Assert-True ($frontmatter -match ('(?m)^model: ' + $expectedAgents[$agentFile][0] + '$')) "Invalid model in $agentFile."
    Assert-True ($frontmatter -match ('(?m)^effort: ' + $expectedAgents[$agentFile][1] + '$')) "Invalid effort in $agentFile."
    Assert-True ($content.Contains($principles)) "$agentFile must embed the engineering principles verbatim."
    Assert-True ($content -notmatch '(?i)\bluna\b|\bsol\b|\bastra\b|gpt-|codex|\bagent_type\b|Browser plugin') "$agentFile must not carry Codex vocabulary."
    foreach ($field in @("hooks:", "mcpServers:", "permissionMode:", "initialPrompt:")) {
        Assert-True ($content -notmatch "(?m)^$field") "$agentFile must not set $field, which plugin agents ignore."
    }
}

$codePreflight = 'Before planning or implementation for non-trivial, ambiguous, multi-file, or architectural work, first spawn one bounded read-only `leads:haiku-code-analyst` task per narrow question to inspect only files and symbols needed for the assigned task or question; simple local fixes may stay direct.'
$researchPreflight = 'When the user explicitly requests external/current web research, the first external-evidence action must be one bounded `leads:haiku-researcher` spawn per evidence question, before lead web research.'
$leadTable = Read-Text (Join-Path $pluginRoot "hooks\leads.ts")
foreach ($leadFile in $leads.Keys) {
    $content = Read-Text (Join-Path $agentRoot $leadFile)
    $lead = $leads[$leadFile]
    Assert-True ($content.Contains('exactly `' + $lead.Greeting + '` once')) "$leadFile is missing its exact greeting."
    Assert-True ($content -match 'write an abstract of the plan') "$leadFile must show its plan in the chat."
    Assert-True ($content -match 'Do not write reasoning, tool-by-tool narration, or filler') "$leadFile must keep its reports short."
    Assert-True ($content -match 'end with `0` on its own last line' -and $content -match 'end with `1` on its own last line') "$leadFile must end with a binary status."
    Assert-True ($content -match 'You decide what needs your own review') "$leadFile must decide what it reviews."
    Assert-True ($content -match 'create a new branch' -and $content -match 'Commit on it after each accepted milestone') "$leadFile must branch for a long job and commit each milestone."
    Assert-True ($content -match 'no limit on how many children') "$leadFile must not cap its workers."
    Assert-True ($content.Contains($codePreflight)) "$leadFile is missing the code-analysis preflight."
    Assert-True ($content.Contains($researchPreflight)) "$leadFile is missing the research preflight."
    Assert-True ($content -match 'Before the first implementation edit for any non-trivial task') "$leadFile must create a persistent plan before implementation."
    Assert-True ($content -match 'tasks/plans/<task-slug>\.md') "$leadFile must use the project task-plan path."
    Assert-True ($content -match 'mandatory even when no worker is used') "$leadFile must not make planning depend on delegation."
    Assert-True ($content -match 'session Plan mode and internal todo tracking do not replace it') "$leadFile must not substitute transient planning state."
    Assert-True ($content -match 'immediately after its focused validation and acceptance') "$leadFile must update checklist status incrementally."
    Assert-True ($content -match 'For each plan step, record role, count') "$leadFile must record every plan step."
    Assert-True ($content -match 'never pass `model` or `effort`') "$leadFile must leave model and effort to the agent files."
    Assert-True ($content -match 'Never give the final status while any child is still running') "$leadFile must wait for background children."
    Assert-True ($content -match 'personally responsible for every line a child produces') "$leadFile must own its children's output."
    Assert-True ($content -match 'read the real changes yourself') "$leadFile must review real changes."
    Assert-True ($content -match 'For any decisive check, run it yourself') "$leadFile must repeat decisive checks."
    Assert-True ($content -match 'open the sources or references that your decision rests on') "$leadFile must verify delegated evidence."
    Assert-True ($content -match 'respond `1`, never `0`') "$leadFile must not report success over a known defect."
    Assert-True ($content -match 'end the turn with one short line') "$leadFile must wait with a visible line, since an empty reply draws a harness prompt."
    Assert-True ($content -match '`1` plus one line') "$leadFile must say how to report a blocker."
    Assert-True ($content -match 'reports as unverified') "$leadFile must own what a child could not verify."
    Assert-True ($content -match 'absence or completeness') "$leadFile must check negative claims itself."
    Assert-True ($content -match 'git status --short') "$leadFile must protect uncommitted work from writers."
    Assert-True ($content -match "CLAUDE\.md and AGENTS\.md") "$leadFile must follow project instructions."
    Assert-True ($content -match 'does not load AGENTS\.md') "$leadFile must carry AGENTS.md rules itself."
    Assert-True ($content -match 'active working folder first') "$leadFile must prioritize the working folder."
    Assert-True ($content -match 'repeat the check after changes') "$leadFile must require browser revalidation for web-facing work."
    Assert-True ($content -match 'Confirm with the user before destructive') "$leadFile must confirm destructive actions, since it replaces the default system prompt."
    Assert-True ($content -match 'In the host''s plan mode') "$leadFile must say what plan mode means under a lead."
    Assert-True ($content -match 'on its own last line') "$leadFile must say how a message with a question and work ends."
    # A tools: allowlist would also remove every MCP tool; the runtime enforces delegation.
    Assert-True ($content -notmatch '(?m)^tools:') "$leadFile must keep the full tool pool."

    $sentence = [regex]::Match($content, 'through only these exact subagent types: ([^.]+)\.')
    Assert-True $sentence.Success "$leadFile must list its exact workers."
    $listed = @([regex]::Matches($sentence.Groups[1].Value, 'leads:([a-z-]+)') | ForEach-Object { $_.Groups[1].Value })
    Assert-True (($listed -join ",") -ceq ($lead.Workers -join ",")) "$leadFile lists the wrong workers: $($listed -join ', ')."
    foreach ($worker in $lead.Workers) {
        Assert-True (Test-Path -LiteralPath (Join-Path $agentRoot "$worker.md")) "$leadFile names a missing worker: $worker."
    }
    $id = [System.IO.Path]::GetFileNameWithoutExtension($leadFile)
    $entry = [regex]::Match($leadTable, "(?s)\n  $id`: \{.*?\n  \},").Value
    Assert-True ($entry -match "model: '$($expectedAgents[$leadFile][0])'" -and $entry -match "effort: '$($expectedAgents[$leadFile][1])'") "hooks/leads.ts disagrees with $leadFile on model or effort."
    Assert-True ($entry -match "workers: $($lead.Table)") "hooks/leads.ts gives $id the wrong workers."
}

$ultron = Read-Text (Join-Path $agentRoot "ultron.md")
Assert-True ($ultron -match '## Independent verification') "Ultron must verify its own work."
Assert-True ($ultron -match 'agentType') "Ultron must keep a workflow's agents on its workers' tiers."
Assert-True ($ultron -match 'ASD-STE100') "Ultron must write in the style of ASD-STE100."
$jarvis = Read-Text (Join-Path $agentRoot "jarvis.md")
Assert-True ($jarvis -match 'Never select or instruct `leads:opus-specialist`') "Jarvis must not reach the Opus specialist."
$edith = Read-Text (Join-Path $agentRoot "edith.md")
Assert-True ($edith -match 'Never select or instruct `leads:sonnet-worker`') "Edith must not reach Sonnet."
Assert-True ($edith -match 'Never select or instruct `leads:opus-specialist`') "Edith must not reach the Opus specialist."
foreach ($text in @($jarvis, $edith, (Read-Text (Join-Path $pluginRoot "references\chat-activation.md")))) {
    Assert-True ($text -notmatch 'Needs @|required escalation') "A lead must do its own work; switching is the person's choice."
}
foreach ($text in @($jarvis, $edith)) {
    Assert-True ($text -match 'Never ask for, suggest, or hand over to another lead') "Jarvis and Edith must not ask for another lead."
}

foreach ($workerFile in @("haiku-worker.md", "haiku-researcher.md", "haiku-code-analyst.md", "sonnet-worker.md", "opus-specialist.md", "opus-reviewer.md")) {
    $content = Read-Text (Join-Path $agentRoot $workerFile)
    Assert-True ($content -match '(?m)^disallowedTools: Agent, Skill, SendMessage, TaskStop\b') "$workerFile must structurally disable recursive delegation, including a forked skill and waking a sibling."
    $name = [System.IO.Path]::GetFileNameWithoutExtension($workerFile)
    $level = [regex]::Match($leadTable, "'leads:$name': '(\w+)'").Groups[1].Value
    Assert-True ($level -ceq $expectedAgents[$workerFile][1]) "WORKER_EFFORT in hooks/leads.ts disagrees with $workerFile."
    Assert-True ($content -notmatch '(?m)^tools:') "$workerFile must inherit MCP tools rather than list its tools."
    Assert-True ($content -match '(?i)never.*(spawn|delegate)') "$workerFile must forbid recursive delegation."
}
foreach ($readOnlyFile in @("haiku-researcher.md", "haiku-code-analyst.md", "opus-reviewer.md")) {
    $content = Read-Text (Join-Path $agentRoot $readOnlyFile)
    Assert-True ($content -match '(?m)^disallowedTools: Agent, Skill, SendMessage, TaskStop, Edit, Write, NotebookEdit$') "$readOnlyFile must have no edit tools; its shell use rests on the contract."
    Assert-True ($content -match 'The task contract is read-only') "$readOnlyFile must keep its read-only contract."
    Assert-True ($content -match 'one compact packet') "$readOnlyFile must return a bounded packet."
}
$analyst = Read-Text (Join-Path $agentRoot "haiku-code-analyst.md")
Assert-True ($analyst.Contains('Start with task-named files or symbols; if none are named, use only targeted searches to locate them. Never inventory directories or read unrelated files. Stop once evidence answers the assigned question.')) "The analyst must keep its task-first evidence boundary."
Assert-True ($analyst -match 'at most 500 words') "The analyst must keep its compact output bound."
$haikuWorker = Read-Text (Join-Path $agentRoot "haiku-worker.md")
Assert-True ($haikuWorker -match 'Do not claim browser validation from source inspection') "The Haiku worker must require real browser evidence."
Assert-True ($haikuWorker -match 'trivial one-packet work may proceed without a persistent plan') "The Haiku worker must not deadlock trivial assignments on the plan gate."
$sonnetWorker = Read-Text (Join-Path $agentRoot "sonnet-worker.md")
Assert-True ($sonnetWorker -match 'explicitly identifies Jarvis or Ultron as the caller') "The Sonnet worker must require an authorized caller."
Assert-True ($sonnetWorker -match 'Reject every assignment from Edith') "The Sonnet worker must reject Edith."
Assert-True ($sonnetWorker -match 'explains why Haiku is insufficient') "The Sonnet worker must require a reason to leave Haiku."
Assert-True ($sonnetWorker -match 'ready milestone is missing or incomplete') "The Sonnet worker must keep the plan gate."
$specialist = Read-Text (Join-Path $agentRoot "opus-specialist.md")
Assert-True ($specialist -match 'assigned by Ultron') "The Opus specialist must accept work only from Ultron."
Assert-True ($specialist -match 'Reject every assignment from Jarvis, Edith') "The Opus specialist must reject other callers."
Assert-True ($specialist -match 'exceeds Sonnet worker capability') "The Opus specialist must require a reason to leave Sonnet."
Assert-True ($specialist -match 'Never orchestrate') "The Opus specialist must not orchestrate."
Assert-True ($specialist -match 'primary purpose is review, testing, checking, validation, verification, QA') "The Opus specialist must not be a checking agent."

foreach ($skill in @("ultron", "jarvis", "edith", "lead-off")) {
    $content = Read-Text (Join-Path $skillRoot "$skill\SKILL.md")
    Assert-True ($content -match "(?m)^name: $skill$") "Skill $skill must be named after its folder."
    Assert-True ($content -match '(?m)^disable-model-invocation: true$') "Skill $skill must be selected only by the person."
    Assert-True ($content -notmatch '(?m)^model:') "Skill $skill must leave the model to the runtime."
}
foreach ($role in @("ultron", "jarvis", "edith")) {
    $content = Read-Text (Join-Path $skillRoot "$role\SKILL.md")
    $references = [regex]::Matches($content, '\$\{CLAUDE_PLUGIN_ROOT\}/([^`]+)')
    Assert-True ($references.Count -eq 2) "Skill $role must name the activation text and the contract, its fallback without the runtime."
    foreach ($reference in $references) {
        Assert-True (Test-Path -LiteralPath (Join-Path $pluginRoot $reference.Groups[1].Value)) "Skill $role names a missing file: $($reference.Value)."
    }
    Assert-True ($content -match '\$ARGUMENTS') "Skill $role must pass the task along."
}
Assert-True ((Read-Text (Join-Path $skillRoot "lead-off\SKILL.md")) -match '(?m)^\[leads:selected:off\]$') "lead-off must carry the marker a fork reads back."

$manifest = Read-Text (Join-Path $pluginRoot ".claude-plugin\plugin.json") | ConvertFrom-Json
Assert-True ($manifest.name -ceq "leads") "Plugin must be named leads: every scoped worker name depends on it, and a name starting with a lead's name would rank the wrong skill first in the desktop's menu."
$marketplace = Read-Text (Join-Path $packageRoot ".claude-plugin\marketplace.json") | ConvertFrom-Json
Assert-True ($marketplace.name -ceq "ultron-claude") "Marketplace must be named ultron-claude."
Assert-True ($marketplace.plugins[0].source -ceq "./plugins/leads") "Marketplace must point at the plugin."

foreach ($script in Get-ChildItem (Join-Path $packageRoot "scripts") -Filter "*.ps1") {
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$null, [ref]$errors)
    Assert-True ($errors.Count -eq 0) "$($script.Name) does not parse: $errors"
}
foreach ($launcher in @("start-claude", "start-ultron", "start-jarvis", "start-edith")) {
    foreach ($extension in @("ps1", "sh")) {
        Assert-True (Test-Path -LiteralPath (Join-Path $packageRoot "scripts\$launcher.$extension")) "Missing launcher $launcher.$extension."
    }
}
$launcherPs1 = Read-Text (Join-Path $packageRoot "scripts\start-claude.ps1")
$launcherSh = Read-Text (Join-Path $packageRoot "scripts\start-claude.sh")
foreach ($leadFile in $leads.Keys) {
    $id = [System.IO.Path]::GetFileNameWithoutExtension($leadFile)
    $model = $expectedAgents[$leadFile][0]
    $effort = $expectedAgents[$leadFile][1]
    $greeting = [regex]::Escape($leads[$leadFile].Greeting)
    Assert-True ($launcherPs1 -match "(?m)^\s+$id = @\{ Model = `"$model`"; Effort = `"$effort`"; Greeting = `"$greeting`" \}") "start-claude.ps1 disagrees with $leadFile."
    Assert-True ($launcherSh -match "(?m)^\s+$id\) model=$model; effort=$effort; greeting=`"$greeting`" ;;") "start-claude.sh disagrees with $leadFile."
    Assert-True ((Read-Text (Join-Path $packageRoot "scripts\start-$id.ps1")) -match "-Agent $id ") "start-$id.ps1 must start $id."
    Assert-True ((Read-Text (Join-Path $packageRoot "scripts\start-$id.sh")) -match "--agent $id ") "start-$id.sh must start $id."
}
$hasSh = [bool](Get-Command sh -ErrorAction SilentlyContinue)
if ($hasSh) {
    foreach ($script in Get-ChildItem (Join-Path $packageRoot "scripts") -Filter "*.sh") {
        & sh -n $script.FullName
        Assert-True ($LASTEXITCODE -eq 0) "$($script.Name) does not parse."
    }
} else {
    Write-Warning "sh was not found, so the .sh scripts were neither parsed nor run."
}

# What the launchers really pass, read off a stand-in for the CLI.
$stubRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("claude-ultron-launchers-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $stubRoot | Out-Null
$stubLog = Join-Path $stubRoot "argv.log"
$previousPath = $env:PATH
try {
    [System.IO.File]::WriteAllText((Join-Path $stubRoot "claude.ps1"), '$args -join " " | Set-Content -LiteralPath $env:CLAUDE_STUB_LOG')
    [System.IO.File]::WriteAllText((Join-Path $stubRoot "claude"), "#!/bin/sh`necho `"`$*`" > `"`$CLAUDE_STUB_LOG`"`n")
    if (Get-Command chmod -ErrorAction SilentlyContinue) { & chmod +x (Join-Path $stubRoot "claude") }
    $env:PATH = $stubRoot + [System.IO.Path]::PathSeparator + $env:PATH
    $env:CLAUDE_STUB_LOG = $stubLog
    foreach ($leadFile in $leads.Keys) {
        $id = [System.IO.Path]::GetFileNameWithoutExtension($leadFile)
        $expected = "--agent leads:$id --model $($expectedAgents[$leadFile][0]) --effort $($expectedAgents[$leadFile][1]) "
        Remove-Item -LiteralPath $stubLog -ErrorAction SilentlyContinue
        & (Join-Path $packageRoot "scripts\start-$id.ps1") -Prompt "x" | Out-Null
        Assert-True ((Test-Path -LiteralPath $stubLog) -and (Get-Content -LiteralPath $stubLog -Raw).StartsWith($expected)) "start-$id.ps1 must pass: $expected"
        if ($hasSh) {
            Remove-Item -LiteralPath $stubLog -ErrorAction SilentlyContinue
            & sh (Join-Path $packageRoot "scripts\start-$id.sh") "x" | Out-Null
            Assert-True ((Test-Path -LiteralPath $stubLog) -and (Get-Content -LiteralPath $stubLog -Raw).StartsWith($expected)) "start-$id.sh must pass: $expected"
        }
    }
} finally {
    $env:PATH = $previousPath
    Remove-Item Env:CLAUDE_STUB_LOG -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $stubRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Warning "claude was not found: plugin validation, unit tests, and the disposable install were skipped."
} else {
    & claude plugin validate $pluginRoot | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) "claude plugin validate rejected the plugin."
    & claude plugin validate $packageRoot | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) "claude plugin validate rejected the marketplace."
    & claude plugin test $pluginRoot | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) "The plugin's unit tests failed; run claude plugin test on it for details."

    $sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("claude-ultron-package-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $sandbox | Out-Null
    $previousConfig = $env:CLAUDE_CONFIG_DIR
    try {
        $env:CLAUDE_CONFIG_DIR = $sandbox
        # An install from elsewhere first, to prove a reinstall points at this checkout.
        $elsewhere = Join-Path $sandbox "elsewhere"
        Copy-Item -LiteralPath $packageRoot -Destination $elsewhere -Recurse
        & (Join-Path $elsewhere "scripts\install-plugin.ps1") | Out-Null
        foreach ($attempt in 1..2) {
            & (Join-Path $PSScriptRoot "install-plugin.ps1") | Out-Null
        }
        $registered = & claude plugin marketplace list --json | Out-String | ConvertFrom-Json | Where-Object { $_.name -ceq "ultron-claude" }
        Assert-True ($registered.path -eq $packageRoot) "A reinstall must point the marketplace at this checkout, not $($registered.path)."
        $listing = & claude plugin list | Out-String
        Assert-True ($listing -match 'leads@ultron-claude') "The disposable install did not register the plugin."
        Assert-True ($listing -match 'Status: \S* ?enabled') "The disposable install did not enable the plugin."
    } finally {
        $env:CLAUDE_CONFIG_DIR = $previousConfig
        Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Output "Claude Ultron package checks passed."
