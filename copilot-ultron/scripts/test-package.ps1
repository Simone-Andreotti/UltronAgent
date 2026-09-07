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
$expectedEfforts = @{
    "ultron" = "medium"
    "jarvis" = "high"
    "edith" = "xhigh"
    "luna-code-analyst" = "high"
    "luna-researcher" = "medium"
    "luna-worker" = "medium"
}
$expectedModels = @{
    "ultron" = "gpt-6-astra"
    "jarvis" = "gpt-5.6-sol"
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
$marketplace = Get-Content (Join-Path $packageRoot ".github\plugin\marketplace.json") -Raw | ConvertFrom-Json
$mcpConfig = Get-Content (Join-Path $packageRoot ".mcp.json") -Raw | ConvertFrom-Json
$config = Get-Content (Join-Path $packageRoot "config\copilot-config.example.json") -Raw | ConvertFrom-Json
Assert-True ($manifest.agents -eq "agents/") "Manifest agents path must be agents/."
Assert-True ($manifest.skills -eq "skills/") "Manifest skills path must be skills/."
Assert-True ($manifest.mcpServers -eq ".mcp.json") "Manifest must expose the Playwright MCP fallback."
Assert-True ($manifest.version -eq "1.4.0") "Manifest version must match the current package release."
Assert-True ($marketplace.name -eq "ultron-agent") "Marketplace name is invalid."
Assert-True ($marketplace.metadata.version -eq $manifest.version) "Marketplace metadata version must match the plugin manifest."
Assert-True ($marketplace.plugins.Count -eq 1) "Marketplace must publish exactly one plugin."
Assert-True ($marketplace.plugins[0].name -eq $manifest.name) "Marketplace plugin name must match the plugin manifest."
Assert-True ($marketplace.plugins[0].version -eq $manifest.version) "Marketplace plugin version must match the plugin manifest."
Assert-True ($marketplace.plugins[0].source -eq ".") "Marketplace plugin source must resolve to the package root."
Assert-True ($mcpConfig.mcpServers.'ultron-playwright'.command -eq "npx") "Playwright fallback must use npx."
Assert-True (($mcpConfig.mcpServers.'ultron-playwright'.args -join " ") -eq "-y @playwright/mcp@0.0.79") "Playwright fallback version must be pinned."
Assert-True (($mcpConfig.mcpServers.'ultron-playwright'.tools -join "") -eq "*") "Playwright fallback must expose all browser tools."
Assert-True (Test-Path (Join-Path $packageRoot $manifest.agents)) "Manifest agents path does not exist."
Assert-True (Test-Path (Join-Path $packageRoot $manifest.skills)) "Manifest skills path does not exist."
Assert-True (Test-Path $promptRoot) "Package prompts path does not exist."
Assert-True ($config.model -eq "gpt-6-astra") "Example config must default to GPT-6 Astra."
Assert-True ($config.contextTier -eq "default") "Example config must use default context."
foreach ($lunaName in $expectedAgents | Where-Object { $_ -like "luna-*" }) {
    $lunaConfig = $config.subagents.agents."ultron-orchestrator:$lunaName"
    Assert-True ($lunaConfig.model -eq "gpt-5.6-luna") "$lunaName must use GPT-5.6 Luna."
    Assert-True ($lunaConfig.effortLevel -eq $expectedEfforts[$lunaName]) "$lunaName has the wrong reasoning effort."
    Assert-True ($lunaConfig.contextTier -eq "default") "$lunaName must use default context."
}

$yamlParser = @'
import json
import sys
import yaml

path = sys.argv[1]
text = open(path, encoding="utf-8").read()
parts = text.split("---", 2)
if len(parts) != 3:
    raise SystemExit(f"{path}: missing YAML frontmatter")
metadata = yaml.safe_load(parts[1])
if not isinstance(metadata, dict):
    raise SystemExit(f"{path}: frontmatter must be a mapping")
print(json.dumps(metadata))
'@

function Get-AgentFrontmatter {
    param([Parameter(Mandatory)][string]$Path)
    $json = & python -c $yamlParser $Path
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to parse YAML frontmatter in $Path."
    }
    return ($json | ConvertFrom-Json)
}

$agentFiles = @(Get-ChildItem $agentRoot -Filter "*.agent.md" | Sort-Object Name)
$agentNames = @()
foreach ($agentFile in $agentFiles) {
    $content = Get-Content $agentFile.FullName -Raw
    $frontmatter = Get-AgentFrontmatter -Path $agentFile.FullName
    $nameMatch = [regex]::Match($content, "(?m)^name:\s*([^\r\n]+)\r?$")
    Assert-True $nameMatch.Success "Missing agent name in $($agentFile.Name)."
    $agentNames += ($nameMatch.Groups[1].Value -replace '^[''"]|[''"]$', '').Trim()
    Assert-True (($null -eq $frontmatter.tools) -or ($frontmatter.tools -contains "*")) "$($agentFile.Name) must use the host's full tool set."
    Assert-True ($content -match "(?m)^agents:\s*") "Missing explicit subagent allowlist in $($agentFile.Name)."
    $agentName = ($nameMatch.Groups[1].Value -replace '^[''"]|[''"]$', '').Trim()
    Assert-True ($frontmatter.model -eq $expectedModels[$agentName]) "$($agentFile.Name) has the wrong model metadata."
    Assert-True ($frontmatter.reasoningEffort -eq $expectedEfforts[$agentName]) "$($agentFile.Name) has the wrong reasoning metadata."
    Assert-True ($frontmatter.'reasoning-effort' -eq $frontmatter.reasoningEffort) "$($agentFile.Name) must preserve effort on CLI 1.0.68 as well as current CLI."
}

Assert-True ((($agentNames | Sort-Object) -join "`n") -eq ($expectedAgents -join "`n")) "Agent names do not match the expected package roles."
Assert-True (($agentNames | Select-Object -Unique).Count -eq $agentNames.Count) "Agent names must be unique."

$codePreflight = 'Before planning or implementation for non-trivial, ambiguous, multi-file, or architectural work, first spawn exactly one bounded read-only `luna-code-analyst` task to inspect only files and symbols needed for the assigned task or question; simple local fixes may stay direct.'
$researchPreflight = 'When the user explicitly requests external/current web research, the first external-evidence action must be exactly one bounded `luna-researcher` spawn, before lead web research.'
foreach ($leadName in @("ultron", "jarvis", "edith")) {
    $content = Get-Content (Join-Path $agentRoot "$leadName.agent.md") -Raw
    foreach ($workerName in $expectedAgents | Where-Object { $_ -like "luna-*" }) {
        Assert-True ($content -match [regex]::Escape($workerName)) "$leadName does not allow $workerName."
    }
    Assert-True ($content -match "Delegate routine .* exact Luna role") "$leadName is missing routine Luna delegation."
    Assert-True ($content -match [regex]::Escape($codePreflight)) "$leadName is missing the gated Luna code-analysis preflight."
    Assert-True ($content -match [regex]::Escape($researchPreflight)) "$leadName is missing the gated Luna research preflight."
    Assert-True ($content -match "Do not emit routine intermediary") "$leadName must suppress routine intermediary narration."
    Assert-True ($content -match 'respond only with `0`') "$leadName must use the binary success response."
    Assert-True ($content -match 'respond only with `1`') "$leadName must use the binary failure response."
    Assert-True ($content -match "fewest words possible") "$leadName must keep blocking questions minimal."
    Assert-True ($content -match "Keep each todo action-only and 2-5 words") "$leadName must keep todo text concise."
    Assert-True ($content -match "Silence applies only to chat, never to engineering rigor") "$leadName must preserve engineering rigor."
    Assert-True ($content -match "Adapt to its architecture and style") "$leadName must adapt to existing architecture."
    Assert-True ($content -match "clean, readable, maintainable code") "$leadName must enforce maintainable code."
    Assert-True ($content -match "Before the first implementation edit for non-trivial work") "$leadName must plan before implementation."
    Assert-True ($content -match "Current Architecture, Intended Design, Preserved Interfaces, Milestones, and Validation") "$leadName plan is missing architecture fields."
    Assert-True ($content -match "changes to multiple implementation files, public behavior or interfaces, dependencies, configuration, permissions, architecture, security-sensitive code, or multiple validation stages") "$leadName must define non-trivial work."
    Assert-True ($content -match 'mark it `\[x\]` immediately after focused validation') "$leadName must update its plan incrementally."
    Assert-True ($content -match "mandatory even without a worker; todo tracking does not replace it") "$leadName must persist plans independently of delegation and todo."
    Assert-True ($content -match "multiple subagents in one parallel batch") "$leadName must support parallel subagents."
    Assert-True ($content -match "Never parallelize dependent work or overlapping writers") "$leadName must restrict unsafe parallel work."
    Assert-True ($content -match "exactly one detailed, narrowly scoped task") "$leadName must provide one narrow task per subagent."
    Assert-True ($content -match "cannot spawn or delegate to another agent") "$leadName must forbid recursive delegation."
    Assert-True ($content -match "Code analysis uses high reasoning; research and implementation use medium reasoning") "$leadName must route Luna reasoning by role."
    Assert-True ($content -match "normally one") "$leadName must use the minimum worker count by default."
    Assert-True ($content -match "plan milestone names exactly one Luna role, worker count, owned scope, dependencies, executable check, and escalation condition") "$leadName plan milestones need complete role contracts."
    Assert-True ($content -match "repeat the browser check") "$leadName must require browser revalidation."
    Assert-True ($content -match 'When `/explain` is invoked') "$leadName must support explain mode."
    Assert-True ($content -match "private chain-of-thought") "$leadName explain mode must protect private reasoning."
}

$analystBoundary = 'Start with task-named files or symbols; if none are named, use only targeted searches to locate them. Never inventory directories or read unrelated files. Stop once evidence answers the assigned question.'
$analystOutputBoundary = 'Return a compact evidence packet of at most 500 words, except when a blocker needs more detail'
$analyst = Get-Content (Join-Path $agentRoot "luna-code-analyst.agent.md") -Raw
Assert-True ($analyst -match [regex]::Escape($analystBoundary)) "luna-code-analyst must preserve its task-first evidence boundary."
Assert-True ($analyst -match [regex]::Escape($analystOutputBoundary)) "luna-code-analyst must preserve its compact output boundary."

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
    Assert-True ($content -match "(?m)^user-invocable:\s*false") "$workerName must be hidden from users."
    Assert-True ($content -match "(?m)^disable-model-invocation:\s*false") "$workerName must be available as a child agent."
    Assert-True ($content -match "never invoke agent, task, handoff, or delegation tools") "$workerName must prevent recursive delegation by instruction."
    Assert-True ($content -match "Do not emit progress") "$workerName must suppress progress narration."
    Assert-True ($content -match "Report blockers explicitly") "$workerName must preserve blocker signaling."
}

$workerContent = Get-Content (Join-Path $agentRoot "luna-worker.agent.md") -Raw
Assert-True ($workerContent -match "Preserve the existing architecture, boundaries, conventions, public contracts, and behavior") "luna-worker must preserve existing architecture."
Assert-True ($workerContent -match "clean, readable, maintainable code") "luna-worker must enforce maintainable code."

$workspaceAgentRoot = Join-Path $workspaceRoot ".github\agents"
if (Test-Path (Join-Path $workspaceAgentRoot ".ultron-orchestrator-agents")) {
    foreach ($agentName in $expectedAgents) {
        $packagedAgent = Get-Content (Join-Path $agentRoot "$agentName.agent.md") -Raw
        $workspaceAgent = Get-Content (Join-Path $workspaceAgentRoot "$agentName.agent.md") -Raw
        Assert-True ((($packagedAgent -replace "`r`n", "`n").TrimEnd()) -ceq (($workspaceAgent -replace "`r`n", "`n").TrimEnd())) "Packaged and workspace definitions differ for $agentName."
    }
}

$packagedSkill = Get-Content (Join-Path $packageRoot "skills\ultron-orchestrator\SKILL.md") -Raw
$workspaceSkillPath = Join-Path $workspaceRoot ".github\skills\ultron-orchestrator\SKILL.md"
if ((Test-Path (Join-Path $workspaceAgentRoot ".ultron-orchestrator-agents")) -and (Test-Path $workspaceSkillPath)) {
    $workspaceSkill = Get-Content $workspaceSkillPath -Raw
    Assert-True ((($packagedSkill -replace "`r`n", "`n").TrimEnd()) -ceq (($workspaceSkill -replace "`r`n", "`n").TrimEnd())) "Packaged and workspace skill definitions differ."
}
Assert-True ($packagedSkill -match "No Progress Narration") "Orchestrator skill is missing the silent execution policy."
Assert-True ($packagedSkill -match [regex]::Escape($codePreflight)) "Orchestrator skill must require the gated Luna code-analysis preflight."
Assert-True ($packagedSkill -match [regex]::Escape($researchPreflight)) "Orchestrator skill must require the gated Luna research preflight."
Assert-True ($packagedSkill -match 'responds only with `0`') "Orchestrator skill must enforce binary success output."
Assert-True ($packagedSkill -match 'or `1` when completion is impossible') "Orchestrator skill must enforce binary failure output."
Assert-True ($packagedSkill -match "multiple subagents in one parallel batch") "Orchestrator skill must permit safe parallel delegation."
Assert-True ($packagedSkill -match "exactly one detailed, narrowly scoped task") "Orchestrator skill must enforce one narrow task per subagent."
Assert-True ($packagedSkill -match "Subagents never orchestrate, spawn agents") "Orchestrator skill must forbid recursive delegation."
Assert-True ($packagedSkill -match "Engineering Quality") "Orchestrator skill must preserve engineering quality."
Assert-True ($packagedSkill -match "use high reasoning for code analysis and medium reasoning for research and implementation") "Orchestrator skill must route Luna reasoning by role."
Assert-True ($packagedSkill -match "available browser or Playwright tools") "Orchestrator skill must require browser validation when applicable."
Assert-True ($packagedSkill -match "## Explain Mode") "Orchestrator skill is missing explain mode guidance."
Assert-True ($packagedSkill -match "normally one") "Orchestrator skill must use the minimum worker count."
Assert-True ($packagedSkill -match "plan milestone names exactly one Luna role, count, owned scope, dependencies, executable check, and escalation condition") "Orchestrator skill must define milestone role contracts."
Assert-True ($packagedSkill -match "native browser tooling first") "Orchestrator skill must define browser fallback routing."
Assert-True ($packagedSkill -match "host-supplied image capability") "Orchestrator skill must define image-tool fallback behavior."

$packagedExplainPrompt = Get-Content (Join-Path $promptRoot "explain.prompt.md") -Raw
$workspaceExplainPromptPath = Join-Path $workspaceRoot ".github\prompts\explain.prompt.md"
if ((Test-Path (Join-Path $workspaceAgentRoot ".ultron-orchestrator-agents")) -and (Test-Path $workspaceExplainPromptPath)) {
    $workspaceExplainPrompt = Get-Content $workspaceExplainPromptPath -Raw
    Assert-True ((($packagedExplainPrompt -replace "`r`n", "`n").TrimEnd()) -ceq (($workspaceExplainPrompt -replace "`r`n", "`n").TrimEnd())) "Packaged and workspace explain prompts differ."
}
Assert-True ($packagedExplainPrompt -match "(?m)^name:\s*explain\s*$") "Explain prompt must register the /explain command."
Assert-True ($packagedExplainPrompt -notmatch "(?m)^agent:") "Explain prompt must preserve the currently selected agent."
Assert-True ($packagedExplainPrompt -notmatch "(?m)^model:") "Explain prompt must preserve the current agent model."
Assert-True ($packagedExplainPrompt -match "private chain-of-thought") "Explain prompt must protect private reasoning."

$nativeAgents = @{
    "ultron.toml" = "gpt-6-astra"
    "jarvis.toml" = "gpt-5.6-sol"
    "luna_code_analyst.toml" = "gpt-5.6-luna"
    "luna_researcher.toml" = "gpt-5.6-luna"
    "luna_worker.toml" = "gpt-5.6-luna"
}
foreach ($nativeAgent in $nativeAgents.Keys) {
    $content = Get-Content (Join-Path $codexPackageRoot "agents\$nativeAgent") -Raw
    Assert-True ($content -match ('(?m)^model = "' + [regex]::Escape($nativeAgents[$nativeAgent]) + '"\r?$')) "Invalid native model in $nativeAgent."
}
$launchers = @{
    "start-edith.ps1" = @{ Model = "gpt-5.6-luna"; Effort = "xhigh" }
    "start-ultron.ps1" = @{ Model = "gpt-6-astra"; Effort = "medium" }
    "start-jarvis.ps1" = @{ Model = "gpt-5.6-sol"; Effort = "high" }
    "start-edith.sh" = @{ Model = "gpt-5.6-luna"; Effort = "xhigh" }
    "start-ultron.sh" = @{ Model = "gpt-6-astra"; Effort = "medium" }
    "start-jarvis.sh" = @{ Model = "gpt-5.6-sol"; Effort = "high" }
}
foreach ($launcherName in $launchers.Keys) {
    $content = Get-Content (Join-Path $PSScriptRoot $launcherName) -Raw
    Assert-True ($content -notmatch 'long_context|--model auto') "Forbidden routing found in $launcherName."
    if ($launcherName -like "*.ps1") {
        Assert-True ($content -match ('"--model",\s*"' + [regex]::Escape($launchers[$launcherName].Model) + '"')) "Invalid model in $launcherName."
        Assert-True ($content -match ('"--reasoning-effort",\s*"' + [regex]::Escape($launchers[$launcherName].Effort) + '"')) "Invalid reasoning effort in $launcherName."
        Assert-True ($content -match '\$arguments \+= @\("-i", \$Prompt\)') "$launcherName must pass its initial prompt through Copilot interactive mode."
    } else {
        Assert-True ($content -match ('--model\s+' + [regex]::Escape($launchers[$launcherName].Model))) "Invalid model in $launcherName."
        Assert-True ($content -match ('--reasoning-effort\s+' + [regex]::Escape($launchers[$launcherName].Effort))) "Invalid reasoning effort in $launcherName."
    }
    Assert-True ($content -match 'allow-all-tools') "$launcherName must preserve restricted tool access."
    Assert-True ($content -match 'allow-all-urls') "$launcherName must preserve restricted web access."
    Assert-True ($content -match 'disallow-temp-dir') "$launcherName must preserve restricted temporary-directory access."
    Assert-True ($content -match '--allow-all') "$launcherName must default to full system access."
    Assert-True ($content -notmatch '--context|--sandbox|--no-sandbox') "$launcherName contains unsupported context or sandbox flags."
    Assert-True ($content -notmatch 'allow-all-paths') "$launcherName must use Copilot's supported full-access flag."
}

foreach ($launcherName in @("start-edith.ps1", "start-ultron.ps1", "start-jarvis.ps1")) {
    $content = Get-Content (Join-Path $PSScriptRoot $launcherName) -Raw
    Assert-True ($content -match '\[CmdletBinding\(PositionalBinding = \$false\)\]') "$launcherName must disable positional argument binding."
    Assert-True ($content -notmatch '\[string\]\$Model|\[string\]\$Context|\$ReasoningEffort') "$launcherName permits routing overrides."
    Assert-True ($content -match '\$args\.Count -gt 0') "$launcherName does not reject unsupported arguments."
    Assert-True ($content -match '\[int\]\$MaxAiCredits') "$launcherName must pass whole, culture-independent credit limits."
    Assert-True ($content -match '\[switch\]\$AllowAll = \(\$env:COPILOT_ALLOW_ALL -ne "false"\)') "$launcherName must default to full system paths."
    Assert-True ($content -notmatch 'COPILOT_SANDBOX|\$Sandbox') "$launcherName must not use unsupported sandbox flags."
}

$launcherMockRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("copilot-ultron-launcher-test-" + [guid]::NewGuid().ToString("N"))
try {
    New-Item -ItemType Directory -Path $launcherMockRoot | Out-Null
    $fakeCopilot = Join-Path $launcherMockRoot "copilot.cmd"
    $launcherLog = Join-Path $launcherMockRoot "arguments.txt"
    @'
@echo off
> "%COPILOT_LAUNCHER_LOG%" echo %*
exit /b 0
'@ | Set-Content -Path $fakeCopilot -Encoding ASCII

    $savedPath = $env:PATH
    $savedAllowAll = $env:COPILOT_ALLOW_ALL
    try {
        $env:PATH = "$launcherMockRoot;$savedPath"
        $env:COPILOT_LAUNCHER_LOG = $launcherLog
        Remove-Item Env:COPILOT_ALLOW_ALL -ErrorAction SilentlyContinue
        & (Join-Path $PSScriptRoot "start-ultron.ps1") -WorkingDirectory $PSScriptRoot
        $fullAccessArguments = Get-Content $launcherLog -Raw
        Assert-True ($fullAccessArguments -match '(?m)(^|\s)--allow-all(\s|$)') "Launcher default must pass --allow-all."
        Assert-True ($fullAccessArguments -notmatch '(?m)(^|\s)--allow-all-tools(\s|$)') "Launcher default must not use restricted tool flags."

        $env:COPILOT_ALLOW_ALL = "false"
        Remove-Item $launcherLog -Force
        & (Join-Path $PSScriptRoot "start-ultron.ps1") -WorkingDirectory $PSScriptRoot
        $restrictedArguments = Get-Content $launcherLog -Raw
        Assert-True ($restrictedArguments -match '(?m)(^|\s)--allow-all-tools(\s|$)') "Restricted opt-out must preserve tool access."
        Assert-True ($restrictedArguments -match '(?m)(^|\s)--allow-all-urls(\s|$)') "Restricted opt-out must preserve URL access."
        Assert-True ($restrictedArguments -match '(?m)(^|\s)--disallow-temp-dir(\s|$)') "Restricted opt-out must preserve temporary-directory isolation."
        Assert-True ($restrictedArguments -notmatch '(?m)(^|\s)--allow-all(\s|$)') "Restricted opt-out must not pass --allow-all."
    } finally {
        if ($null -eq $savedPath) { Remove-Item Env:PATH -ErrorAction SilentlyContinue } else { $env:PATH = $savedPath }
        if ($null -eq $savedAllowAll) { Remove-Item Env:COPILOT_ALLOW_ALL -ErrorAction SilentlyContinue } else { $env:COPILOT_ALLOW_ALL = $savedAllowAll }
        Remove-Item Env:COPILOT_LAUNCHER_LOG -ErrorAction SilentlyContinue
    }
} finally {
    Remove-Item $launcherMockRoot -Recurse -Force -ErrorAction SilentlyContinue
}

foreach ($launcherName in @("start-edith.sh", "start-ultron.sh", "start-jarvis.sh")) {
    $content = Get-Content (Join-Path $PSScriptRoot $launcherName) -Raw
    Assert-True ($content -match '--model\|--model=\*\|--reasoning-effort\|--reasoning-effort=\*') "$launcherName does not reject routing overrides."
    Assert-True ($content -match '--agent\|--agent=\*\|--plugin-dir\|--plugin-dir=\*') "$launcherName permits agent or plugin routing overrides."
    Assert-True ($content -match '\$\{COPILOT_ALLOW_ALL:-true\}') "$launcherName must default to full system paths."
}

$readme = Get-Content (Join-Path $packageRoot "README.md") -Raw
Assert-True ($readme -match 'Ultron requests `gpt-6-astra` with medium reasoning') "README must document Ultron model routing."
Assert-True ($readme -match 'Jarvis requests `gpt-5\.6-sol` with high reasoning') "README must document Jarvis model routing."
Assert-True ($readme -match 'Edith requests `gpt-5\.6-luna` with maximum \(`xhigh`\) reasoning') "README must document Edith model routing."
Assert-True ($readme -match 'canonical `playwright/\*` namespace') "README must document the canonical Playwright namespace."
Assert-True ($readme -match '@mcp playwright') "README must document the VS Code Playwright MCP installation."
Assert-True ($readme -match '@playwright/mcp@0\.0\.79') "README must document the pinned Playwright MCP fallback."
Assert-True ($readme -match "install-plugin\.ps1" -and $readme -match "install-plugin\.sh") "README must document native plugin replacement scripts."
Assert-True ($readme -match "ultron-orchestrator@ultron-agent" -and $readme -match "deprecated direct-plugin installation") "README must document marketplace-based plugin replacement."
Assert-True ($readme -match "Repeat runs are managed upgrades") "README must document managed copy-install upgrades."
Assert-True ($readme -match 'supported full-access flag, `--allow-all`') "README must document the full-access launcher default."
Assert-True ($readme -match "COPILOT_ALLOW_ALL=false") "README must document the restricted launcher opt-out."

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
Assert-True ($powerShellInstaller -match 'Remove-ManagedFiles') "PowerShell installer must clean stale managed files during upgrades."
Assert-True ($shellInstaller -match 'remove_managed_files') "Shell installer must clean stale managed files during upgrades."
Assert-True ($powerShellInstaller -match '\.ultron-orchestrator-agents') "PowerShell installer must record managed agents."
Assert-True ($shellInstaller -match '\.ultron-orchestrator-agents') "Shell installer must record managed agents."

$tempCopyTest = Join-Path ([System.IO.Path]::GetTempPath()) ("copilot-ultron-copy-test-" + [guid]::NewGuid().ToString("N"))
try {
    $tempHome = Join-Path $tempCopyTest "home"
    $tempVsCodeUser = Join-Path $tempCopyTest "vscode-user"
    New-Item -ItemType Directory -Path $tempHome, $tempVsCodeUser | Out-Null
    & (Join-Path $PSScriptRoot "install.ps1") -HomePath $tempHome -VsCodeUserPath $tempVsCodeUser

    $cliAgentRoot = Join-Path $tempHome ".copilot\agents"
    $agentMarker = Join-Path $cliAgentRoot ".ultron-orchestrator-agents"
    $staleAgent = Join-Path $cliAgentRoot "retired-luna.agent.md"
    Add-Content -Path $agentMarker -Value "retired-luna.agent.md"
    Set-Content -Path $staleAgent -Value "retired"
    $unrelatedAgent = Join-Path $cliAgentRoot "personal-reviewer.agent.md"
    Set-Content -Path $unrelatedAgent -Value "personal-content"

    $vsCodePromptRoot = Join-Path $tempVsCodeUser "prompts"
    $promptMarker = Join-Path $vsCodePromptRoot ".ultron-orchestrator-prompts"
    $stalePrompt = Join-Path $vsCodePromptRoot "retired-explain.prompt.md"
    Add-Content -Path $promptMarker -Value "retired-explain.prompt.md"
    Set-Content -Path $stalePrompt -Value "retired"

    & (Join-Path $PSScriptRoot "install.ps1") -HomePath $tempHome -VsCodeUserPath $tempVsCodeUser
    Assert-True (-not (Test-Path $staleAgent)) "Repeat installation must remove stale package-managed agents."
    Assert-True ((Get-Content $agentMarker) -notcontains "retired-luna.agent.md") "Repeat installation must refresh the managed-agent marker."
    Assert-True (-not (Test-Path $stalePrompt)) "Repeat installation must remove stale package-managed prompts."
    Assert-True ((Get-Content $promptMarker) -notcontains "retired-explain.prompt.md") "Repeat installation must refresh the managed-prompt marker."
    Assert-True ((Get-Content $unrelatedAgent -Raw).Trim() -eq "personal-content") "Repeat installation must preserve unrelated files byte-for-byte."

    $skillRoot = Join-Path $tempHome ".copilot\skills\ultron-orchestrator"
    Remove-Item $skillRoot -Recurse -Force
    & (Join-Path $PSScriptRoot "install.ps1") -HomePath $tempHome -VsCodeUserPath $tempVsCodeUser
    Assert-True (Test-Path (Join-Path $skillRoot "SKILL.md")) "Managed markers must allow an upgrade when the skill directory is missing."

    $managedAgentNames = @(Get-Content $agentMarker | Where-Object { $_ -ne "edith.agent.md" })
    Set-Content -Path $agentMarker -Value $managedAgentNames -Encoding UTF8
    $unmanagedCurrentAgent = Join-Path $cliAgentRoot "edith.agent.md"
    Set-Content -Path $unmanagedCurrentAgent -Value "user-owned-edith"
    $upgradeCollisionRejected = $false
    try {
        & (Join-Path $PSScriptRoot "install.ps1") -HomePath $tempHome -VsCodeUserPath $tempVsCodeUser
    } catch {
        $upgradeCollisionRejected = $_.Exception.Message -match "Refusing partial install"
    }
    Assert-True $upgradeCollisionRejected "Repeat installation must reject a current filename that is absent from its ownership marker."
    Assert-True ((Get-Content $unmanagedCurrentAgent -Raw).Trim() -eq "user-owned-edith") "Repeat installation must preserve an unmanaged current-name collision."

    $conflictHome = Join-Path $tempCopyTest "conflict-home"
    $conflictAgentRoot = Join-Path $conflictHome ".copilot\agents"
    New-Item -ItemType Directory -Path $conflictAgentRoot | Out-Null
    $conflictAgent = Join-Path $conflictAgentRoot "ultron.agent.md"
    Set-Content -Path $conflictAgent -Value "unrelated"
    $conflictRejected = $false
    try {
        & (Join-Path $PSScriptRoot "install.ps1") -HomePath $conflictHome -VsCodeUserPath (Join-Path $tempCopyTest "conflict-vscode")
    } catch {
        $conflictRejected = $_.Exception.Message -match "Refusing partial install"
    }
    Assert-True $conflictRejected "Installer must reject an unmanaged name collision."
    Assert-True ((Get-Content $conflictAgent -Raw).Trim() -eq "unrelated") "Installer must preserve an unmanaged conflicting file."

    & (Join-Path $PSScriptRoot "install.ps1") -HomePath $conflictHome -VsCodeUserPath (Join-Path $tempCopyTest "conflict-vscode") -Force
    Assert-True ((Get-Content $conflictAgent -Raw) -match '(?m)^name:\s*ultron\s*$') "Force install must replace an unmanaged collision."
    Assert-True ((Get-Content (Join-Path $conflictAgentRoot ".ultron-orchestrator-agents")) -contains "ultron.agent.md") "Force install must record ownership of the replaced collision."

    $unsafeMarker = Join-Path $conflictAgentRoot ".ultron-orchestrator-agents"
    Add-Content -Path $unsafeMarker -Value ".."
    $parentSentinel = Join-Path $conflictHome "parent-sentinel.txt"
    Set-Content -Path $parentSentinel -Value "preserve"
    $unsafeMarkerRejected = $false
    try {
        & (Join-Path $PSScriptRoot "install.ps1") -HomePath $conflictHome -VsCodeUserPath (Join-Path $tempCopyTest "conflict-vscode")
    } catch {
        $unsafeMarkerRejected = $_.Exception.Message -match "Unsafe managed file entry"
    }
    Assert-True $unsafeMarkerRejected "Installer must reject unsafe ownership-marker entries."
    Assert-True ((Get-Content $parentSentinel -Raw).Trim() -eq "preserve") "Unsafe marker rejection must not change parent files."

    $tempProject = Join-Path $tempCopyTest "project"
    New-Item -ItemType Directory -Path $tempProject | Out-Null
    & (Join-Path $PSScriptRoot "install.ps1") -Scope Project -ProjectPath $tempProject
    $projectAgentRoot = Join-Path $tempProject ".github\agents"
    $projectAgentMarker = Join-Path $projectAgentRoot ".ultron-orchestrator-agents"
    $staleProjectAgent = Join-Path $projectAgentRoot "retired-project.agent.md"
    $unrelatedProjectAgent = Join-Path $projectAgentRoot "personal-project.agent.md"
    Add-Content -Path $projectAgentMarker -Value "retired-project.agent.md"
    Set-Content -Path $staleProjectAgent -Value "retired"
    Set-Content -Path $unrelatedProjectAgent -Value "personal"
    & (Join-Path $PSScriptRoot "install.ps1") -Scope Project -ProjectPath $tempProject
    Assert-True (-not (Test-Path $staleProjectAgent)) "Repeat project install must remove stale managed agents."
    Assert-True ((Get-Content $unrelatedProjectAgent -Raw).Trim() -eq "personal") "Repeat project install must preserve unrelated agents."

    $projectManagedNames = @(Get-Content $projectAgentMarker | Where-Object { $_ -ne "edith.agent.md" })
    [System.IO.File]::WriteAllText($projectAgentMarker, (($projectManagedNames -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
    $projectCurrentCollision = Join-Path $projectAgentRoot "edith.agent.md"
    Set-Content -Path $projectCurrentCollision -Value "project-owned-edith"
    $projectCollisionRejected = $false
    try {
        & (Join-Path $PSScriptRoot "install.ps1") -Scope Project -ProjectPath $tempProject
    } catch {
        $projectCollisionRejected = $_.Exception.Message -match "Refusing partial install"
    }
    Assert-True $projectCollisionRejected "Repeat project install must reject an unmanaged current-name collision."
    Assert-True ((Get-Content $projectCurrentCollision -Raw).Trim() -eq "project-owned-edith") "Repeat project install must preserve an unmanaged current-name collision."
} finally {
    Remove-Item $tempCopyTest -Recurse -Force -ErrorAction SilentlyContinue
}

$pluginInstaller = Join-Path $PSScriptRoot "install-plugin.ps1"
$shellPluginInstaller = Get-Content (Join-Path $PSScriptRoot "install-plugin.sh") -Raw
$tempPluginTest = Join-Path ([System.IO.Path]::GetTempPath()) ("copilot-ultron-plugin-test-" + [guid]::NewGuid().ToString("N"))
try {
    New-Item -ItemType Directory -Path $tempPluginTest | Out-Null
    $invocationLog = Join-Path $tempPluginTest "invocations.txt"
    $fakeCopilot = Join-Path $tempPluginTest "copilot.ps1"
    @'
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
Add-Content -Path $env:COPILOT_TEST_LOG -Value ($Arguments -join " ")
if (($Arguments -join " ") -eq "plugin list") {
    if ($env:COPILOT_TEST_BARE_NAMES -eq "true") {
        Write-Output "ultron-orchestrator"
    } else {
        Write-Output "Installed plugins:"
        Write-Output "  ultron-orchestrator@ultron-agent (v1.3.0)"
    }
}
if (($Arguments -join " ") -eq "plugin marketplace list") {
    if ($env:COPILOT_TEST_BARE_NAMES -eq "true") {
        Write-Output "ultron-agent"
    } else {
        Write-Output "Registered marketplaces:"
        Write-Output "  ultron-agent (Local)"
    }
}
'@ | Set-Content -Path $fakeCopilot -Encoding UTF8
    $env:COPILOT_TEST_LOG = $invocationLog
    & $pluginInstaller -CopilotCommand $fakeCopilot
    $pluginInvocations = @(Get-Content $invocationLog)
    $expectedPluginInvocations = "plugin list`nplugin uninstall ultron-orchestrator`nplugin marketplace list`nplugin marketplace remove ultron-agent`nplugin marketplace add $packageRoot`nplugin install ultron-orchestrator@ultron-agent"
    Assert-True (($pluginInvocations -join "`n") -eq $expectedPluginInvocations) "Native plugin installer must replace the old plugin and marketplace before installing the current package."

    Clear-Content $invocationLog
    $env:COPILOT_TEST_BARE_NAMES = "true"
    & $pluginInstaller -CopilotCommand $fakeCopilot
    $bareNameInvocations = @(Get-Content $invocationLog)
    Assert-True (($bareNameInvocations -join "`n") -eq $expectedPluginInvocations) "Native plugin installer must recognize bare plugin and marketplace list rows."
} finally {
    Remove-Item Env:COPILOT_TEST_LOG -ErrorAction SilentlyContinue
    Remove-Item Env:COPILOT_TEST_BARE_NAMES -ErrorAction SilentlyContinue
    Remove-Item $tempPluginTest -Recurse -Force -ErrorAction SilentlyContinue
}
Assert-True ($shellPluginInstaller -match 'plugin uninstall "\$plugin_name"') "Shell plugin installer must uninstall the previous snapshot."
Assert-True ($shellPluginInstaller -match 'plugin marketplace remove "\$marketplace_name"') "Shell plugin installer must replace the marketplace registration."
Assert-True ($shellPluginInstaller -match 'plugin marketplace add "\$package_root"') "Shell plugin installer must register the package marketplace."
Assert-True ($shellPluginInstaller -match 'plugin install "\$plugin_name@\$marketplace_name"') "Shell plugin installer must install through the marketplace."

Write-Output "Copilot Ultron package checks passed."
