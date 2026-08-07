[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$packageRoot = Split-Path -Parent $PSScriptRoot
$workspaceRoot = Split-Path -Parent $packageRoot
$codexPackageRoot = Join-Path $workspaceRoot "codex-ultron"
$agentRoot = Join-Path $packageRoot "agents"
$promptRoot = Join-Path $packageRoot "prompts"
$expectedAgents = @(
    "edith",
    "jarvis",
    "luna-code-analyst",
    "luna-researcher",
    "luna-worker",
    "ultron"
)
$expectedModels = @{
    "ultron" = "gpt-5.6-sol"
    "jarvis" = "gpt-5.6-terra"
    "edith" = "gpt-5.6-luna"
    "luna-code-analyst" = "gpt-5.6-luna"
    "luna-researcher" = "gpt-5.6-luna"
    "luna-worker" = "gpt-5.6-luna"
}

function Assert-True {
    param(
        [Parameter(Mandatory)]
        [bool]$Condition,
        [Parameter(Mandatory)]
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

$manifest = Get-Content (Join-Path $packageRoot "plugin.json") -Raw | ConvertFrom-Json
$config = Get-Content (Join-Path $packageRoot "config\copilot-config.example.json") -Raw | ConvertFrom-Json
Assert-True ($manifest.agents -eq "agents/") "Manifest agents path must be agents/."
Assert-True ($manifest.skills -eq "skills/") "Manifest skills path must be skills/."
Assert-True (Test-Path (Join-Path $packageRoot $manifest.agents)) "Manifest agents path does not exist."
Assert-True (Test-Path (Join-Path $packageRoot $manifest.skills)) "Manifest skills path does not exist."
Assert-True (Test-Path $promptRoot) "Package prompts path does not exist."
Assert-True ($config.model -eq "gpt-5.6-sol") "Example config must default to GPT-5.6 Sol."
Assert-True ($config.contextTier -eq "default") "Example config must use default context."
foreach ($lunaName in $expectedAgents | Where-Object { $_ -like "luna-*" }) {
    $lunaConfig = $config.subagents.agents.$lunaName
    Assert-True ($lunaConfig.model -eq "gpt-5.6-luna") "$lunaName must use GPT-5.6 Luna."
    Assert-True ($lunaConfig.effortLevel -eq "max") "$lunaName must use max reasoning."
    Assert-True ($lunaConfig.contextTier -eq "default") "$lunaName must use default context."
}

$agentFiles = @(Get-ChildItem $agentRoot -Filter "*.agent.md" | Sort-Object Name)
$agentNames = @()
foreach ($agentFile in $agentFiles) {
    $content = Get-Content $agentFile.FullName -Raw
    $nameMatch = [regex]::Match($content, "(?m)^name:\s*([^\r\n]+)\r?$")
    Assert-True $nameMatch.Success "Missing agent name in $($agentFile.Name)."
    $agentNames += ($nameMatch.Groups[1].Value -replace '^[''"]|[''"]$', '').Trim()
    Assert-True ($content -match "(?m)^tools:\s*\[") "Missing explicit tools in $($agentFile.Name)."
    Assert-True ($content -match "(?m)^agents:\s*") "Missing explicit subagent allowlist in $($agentFile.Name)."
    $agentName = ($nameMatch.Groups[1].Value -replace '^[''"]|[''"]$', '').Trim()
    Assert-True ($content -match ("(?m)^model:\s*'" + [regex]::Escape($expectedModels[$agentName]) + "'\s*$")) "Invalid model in $($agentFile.Name)."
}

Assert-True ((($agentNames | Sort-Object) -join "`n") -eq ($expectedAgents -join "`n")) "Agent names do not match the expected package roles."
Assert-True (($agentNames | Select-Object -Unique).Count -eq $agentNames.Count) "Agent names must be unique."

foreach ($leadName in @("ultron", "jarvis", "edith")) {
    $content = Get-Content (Join-Path $agentRoot "$leadName.agent.md") -Raw
    foreach ($workerName in $expectedAgents | Where-Object { $_ -like "luna-*" }) {
        Assert-True ($content -match [regex]::Escape($workerName)) "$leadName does not allow $workerName."
    }
    Assert-True ($content -match "Execute small.*directly") "$leadName is missing the direct execution path."
    Assert-True ($content -match "Do not emit routine intermediary") "$leadName must suppress routine intermediary narration."
    Assert-True ($content -match 'respond only with `0`') "$leadName must use the binary success response."
    Assert-True ($content -match 'respond only with `1`') "$leadName must use the binary failure response."
    Assert-True ($content -match "fewest words possible") "$leadName must keep blocking questions minimal."
    Assert-True ($content -match "(?m)^tools:.*\btodo\b") "$leadName must retain todo functionality."
    Assert-True ($content -match "(?m)^tools:.*\bagent\b") "$leadName must retain subagent functionality."
    Assert-True ($content -match "Keep each todo action-only and 2-5 words") "$leadName must keep todo text concise."
    Assert-True ($content -match "Silence applies only to chat, never to engineering rigor") "$leadName must preserve engineering rigor."
    Assert-True ($content -match "Adapt to its architecture and style") "$leadName must adapt to existing architecture."
    Assert-True ($content -match "clean, readable, maintainable code") "$leadName must enforce maintainable code."
    Assert-True ($content -match "Before non-trivial implementation, act as architect") "$leadName must plan non-trivial implementation."
    Assert-True ($content -match "current architecture, intended design, interfaces to preserve, ordered milestones with ownership, and validation") "$leadName plan is missing architecture fields."
    Assert-True ($content -match "multiple subagents in one parallel batch") "$leadName must support parallel subagents."
    Assert-True ($content -match "Never parallelize dependent work or overlapping writers") "$leadName must restrict unsafe parallel work."
    Assert-True ($content -match "exactly one detailed, narrowly scoped task") "$leadName must provide one narrow task per subagent."
    Assert-True ($content -match "cannot spawn or delegate to another agent") "$leadName must forbid recursive delegation."
    Assert-True ($content -match "gpt-5\.6-luna.*max reasoning") "$leadName must route Luna roles to max reasoning."
    Assert-True ($content -match 'When `/explain` is invoked') "$leadName must support explain mode."
    Assert-True ($content -match "private chain-of-thought") "$leadName explain mode must protect private reasoning."
}

$leadGreetings = @{
    "ultron" = "Lowly human, let Ultron manage the rest."
    "jarvis" = "Jarvis at your service."
    "edith" = "Edith at your service."
}
foreach ($leadName in $leadGreetings.Keys) {
    $content = Get-Content (Join-Path $agentRoot "$leadName.agent.md") -Raw
    Assert-True ($content -match [regex]::Escape("You are $leadName")) "$leadName must know its identity."
    Assert-True ($content -match [regex]::Escape($leadGreetings[$leadName])) "$leadName is missing its chat greeting."
    Assert-True ($content -match "exactly once") "$leadName must emit its greeting once per chat."
}

foreach ($workerName in $expectedAgents | Where-Object { $_ -like "luna-*" }) {
    $content = Get-Content (Join-Path $agentRoot "$workerName.agent.md") -Raw
    Assert-True ($content -match "(?m)^agents:\s*\[\]") "$workerName must not invoke subagents."
    Assert-True ($content -notmatch "(?m)^tools:.*\bagent\b") "$workerName must not have the agent tool."
    Assert-True ($content -match "(?m)^user-invocable:\s*false") "$workerName must be hidden from users."
    Assert-True ($content -match "(?m)^disable-model-invocation:\s*true") "$workerName must require an explicit parent allowlist."
    Assert-True ($content -match "Do not emit progress") "$workerName must suppress progress narration."
    Assert-True ($content -match "Report blockers explicitly") "$workerName must preserve blocker signaling."
}

$workerContent = Get-Content (Join-Path $agentRoot "luna-worker.agent.md") -Raw
Assert-True ($workerContent -match "Preserve the existing architecture, boundaries, conventions, public contracts, and behavior") "luna-worker must preserve existing architecture."
Assert-True ($workerContent -match "clean, readable, maintainable code") "luna-worker must enforce maintainable code."

foreach ($agentName in $expectedAgents) {
    $packagedAgent = Get-Content (Join-Path $agentRoot "$agentName.agent.md") -Raw
    $workspaceAgent = Get-Content (Join-Path $workspaceRoot ".github\agents\$agentName.agent.md") -Raw
    Assert-True ((($packagedAgent -replace "`r`n", "`n").TrimEnd()) -ceq (($workspaceAgent -replace "`r`n", "`n").TrimEnd())) "Packaged and workspace definitions differ for $agentName."
}

$packagedSkill = Get-Content (Join-Path $packageRoot "skills\ultron-orchestrator\SKILL.md") -Raw
$workspaceSkill = Get-Content (Join-Path $workspaceRoot ".github\skills\ultron-orchestrator\SKILL.md") -Raw
Assert-True ((($packagedSkill -replace "`r`n", "`n").TrimEnd()) -ceq (($workspaceSkill -replace "`r`n", "`n").TrimEnd())) "Packaged and workspace skill definitions differ."
Assert-True ($packagedSkill -match "No Progress Narration") "Orchestrator skill is missing the silent execution policy."
Assert-True ($packagedSkill -match 'responds only with `0`') "Orchestrator skill must enforce binary success output."
Assert-True ($packagedSkill -match 'or `1` when completion is impossible') "Orchestrator skill must enforce binary failure output."
Assert-True ($packagedSkill -match "multiple subagents in one parallel batch") "Orchestrator skill must permit safe parallel delegation."
Assert-True ($packagedSkill -match "exactly one detailed, narrowly scoped task") "Orchestrator skill must enforce one narrow task per subagent."
Assert-True ($packagedSkill -match "Subagents never orchestrate, spawn agents") "Orchestrator skill must forbid recursive delegation."
Assert-True ($packagedSkill -match "Engineering Quality") "Orchestrator skill must preserve engineering quality."
Assert-True ($packagedSkill -match "gpt-5\.6-luna.*max reasoning") "Orchestrator skill must route Luna roles to max reasoning."
Assert-True ($packagedSkill -match "## Explain Mode") "Orchestrator skill is missing explain mode guidance."

$packagedExplainPrompt = Get-Content (Join-Path $promptRoot "explain.prompt.md") -Raw
$workspaceExplainPrompt = Get-Content (Join-Path $workspaceRoot ".github\prompts\explain.prompt.md") -Raw
Assert-True ((($packagedExplainPrompt -replace "`r`n", "`n").TrimEnd()) -ceq (($workspaceExplainPrompt -replace "`r`n", "`n").TrimEnd())) "Packaged and workspace explain prompts differ."
Assert-True ($packagedExplainPrompt -match "(?m)^name:\s*explain\s*$") "Explain prompt must register the /explain command."
Assert-True ($packagedExplainPrompt -notmatch "(?m)^agent:") "Explain prompt must preserve the currently selected agent."
Assert-True ($packagedExplainPrompt -notmatch "(?m)^model:") "Explain prompt must preserve the current agent model."
Assert-True ($packagedExplainPrompt -match "private chain-of-thought") "Explain prompt must protect private reasoning."

$sharedInstructionsPath = Join-Path $workspaceRoot "AGENTS.md"
if (Test-Path $sharedInstructionsPath) {
    $sharedInstructions = Get-Content $sharedInstructionsPath -Raw
    Assert-True ($sharedInstructions -match "Delegated subagents return one bounded packet") "Shared instructions must permit useful Luna result packets."
    Assert-True ($sharedInstructions -match "User-facing leads respond only") "Binary completion must apply only to user-facing leads."
}

$nativeAgents = @{
    "ultron.toml" = "gpt-5.6-sol"
    "jarvis.toml" = "gpt-5.6-terra"
    "luna_code_analyst.toml" = "gpt-5.6-luna"
    "luna_researcher.toml" = "gpt-5.6-luna"
    "luna_worker.toml" = "gpt-5.6-luna"
}
foreach ($nativeAgent in $nativeAgents.Keys) {
    $content = Get-Content (Join-Path $codexPackageRoot "agents\$nativeAgent") -Raw
    Assert-True ($content -match ('(?m)^model = "' + [regex]::Escape($nativeAgents[$nativeAgent]) + '"\r?$')) "Invalid native model in $nativeAgent."
}
foreach ($leadName in @("ultron", "jarvis")) {
    $content = Get-Content (Join-Path $codexPackageRoot "agents\$leadName.toml") -Raw
    Assert-True ($content -match "Execute small.*directly") "$leadName native role is missing the efficient direct path."
    Assert-True ($content -notmatch "Give `luna_code_analyst` one tightly scoped") "$leadName native role must not require analysis delegation for every implementation task."
}

$launchers = @{
    "start-edith.ps1" = "gpt-5.6-luna"
    "start-ultron.ps1" = "gpt-5.6-sol"
    "start-jarvis.ps1" = "gpt-5.6-terra"
    "start-ultron.sh" = "gpt-5.6-sol"
    "start-jarvis.sh" = "gpt-5.6-terra"
}
foreach ($launcherName in $launchers.Keys) {
    $content = Get-Content (Join-Path $PSScriptRoot $launcherName) -Raw
    Assert-True ($content -notmatch 'long_context|--model auto') "Forbidden routing found in $launcherName."
    Assert-True ($content -match [regex]::Escape($launchers[$launcherName])) "Invalid model in $launcherName."
    Assert-True ($content -match 'xhigh') "Missing xhigh reasoning in $launcherName."
    Assert-True ($content -match 'default') "Missing default context in $launcherName."
}

foreach ($launcherName in @("start-edith.ps1", "start-ultron.ps1", "start-jarvis.ps1")) {
    $content = Get-Content (Join-Path $PSScriptRoot $launcherName) -Raw
    Assert-True ($content -match '\[CmdletBinding\(PositionalBinding = \$false\)\]') "$launcherName must disable positional argument binding."
    Assert-True ($content -notmatch '\[string\]\$Model|\[string\]\$Context|\$ReasoningEffort') "$launcherName permits routing overrides."
    Assert-True ($content -match '\$args\.Count -gt 0') "$launcherName does not reject unsupported arguments."
}

foreach ($launcherName in @("start-edith.sh", "start-ultron.sh", "start-jarvis.sh")) {
    $content = Get-Content (Join-Path $PSScriptRoot $launcherName) -Raw
    Assert-True ($content -match '--model\|--model=\*\|--context\|--context=\*\|--reasoning-effort\|--reasoning-effort=\*') "$launcherName does not reject routing overrides."
    Assert-True ($content -match '--agent\|--agent=\*\|--plugin-dir\|--plugin-dir=\*') "$launcherName permits agent or plugin routing overrides."
}

$readme = Get-Content (Join-Path $packageRoot "README.md") -Raw
Assert-True ($readme -match "Selecting Ultron.*automatically selects.*gpt-5\.6-sol") "README must document automatic Ultron model routing."
Assert-True ($readme -match "selecting Jarvis.*automatically selects.*gpt-5\.6-terra") "README must document automatic Jarvis model routing."
Assert-True ($readme -match "Selecting Edith.*automatically selects.*gpt-5\.6-luna") "README must document automatic Edith model routing."

foreach ($script in Get-ChildItem $PSScriptRoot -Filter "*.ps1") {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
    Assert-True ($parseErrors.Count -eq 0) "PowerShell parse errors in $($script.Name): $($parseErrors.Message -join '; ')"
}

$powerShellInstaller = Get-Content (Join-Path $PSScriptRoot "install.ps1") -Raw
$shellInstaller = Get-Content (Join-Path $PSScriptRoot "install.sh") -Raw
Assert-True ($powerShellInstaller -notmatch 'skillAgents|skillRoot "agents"') "PowerShell installer duplicates agents under the skill root."
Assert-True ($shellInstaller -notmatch 'skill_root/agents') "Shell installer duplicates agents under the skill root."
Assert-True ($powerShellInstaller -match 'sourcePrompts') "PowerShell installer must install prompt files."
Assert-True ($shellInstaller -match 'source_prompts') "Shell installer must install prompt files."

Write-Output "Copilot Ultron package checks passed."