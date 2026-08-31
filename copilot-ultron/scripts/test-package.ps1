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
    "ultron" = "high"
    "jarvis" = "medium"
    "edith" = "low"
    "luna-code-analyst" = "high"
    "luna-researcher" = "medium"
    "luna-worker" = "medium"
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
Assert-True ($config.model -eq "gpt-5.6-sol") "Example config must default to GPT-5.6 Sol."
Assert-True ($config.contextTier -eq "default") "Example config must use default context."
foreach ($lunaName in $expectedAgents | Where-Object { $_ -like "luna-*" }) {
    $lunaConfig = $config.subagents.agents.$lunaName
    Assert-True ($lunaConfig.model -eq "gpt-5.6-luna") "$lunaName must use GPT-5.6 Luna."
    Assert-True ($lunaConfig.effortLevel -eq $expectedEfforts[$lunaName]) "$lunaName has the wrong reasoning effort."
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
    Assert-True ($content -notmatch "(?m)^model:\s*") "$($agentFile.Name) must leave model selection to the host."
    Assert-True ($content -notmatch "(?m)^reasoningEffort:\s*") "$($agentFile.Name) must leave reasoning selection to the host."
    Assert-True ($content -notmatch "(?m)^tools:.*ultron-playwright/\*") "$($agentFile.Name) must not expose the CLI-only fallback namespace to VS Code."
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
    Assert-True ($content -match "(?m)^tools:.*\bbrowser\b") "$leadName must expose VS Code browser tools."
    Assert-True ($content -match "(?m)^tools:.*playwright/\*") "$leadName must expose Copilot Playwright tools."
    Assert-True ($content -notmatch "(?m)^tools:.*ultron-playwright/\*") "$leadName must not expose the CLI-only fallback namespace to VS Code."
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
    Assert-True ($content -match "high reasoning for code analysis and medium reasoning for research and implementation") "$leadName must route Luna reasoning by role."
    Assert-True ($content -match "repeat the browser check") "$leadName must require browser revalidation."
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
Assert-True ($workerContent -match "(?m)^tools:.*\bbrowser\b") "luna-worker must expose VS Code browser tools."
Assert-True ($workerContent -match "(?m)^tools:.*playwright/\*") "luna-worker must expose Copilot Playwright tools."
Assert-True ($workerContent -notmatch "(?m)^tools:.*ultron-playwright/\*") "luna-worker must not expose the CLI-only fallback namespace to VS Code."

$workspaceAgentRoot = Join-Path $workspaceRoot ".github\agents"
if (Test-Path $workspaceAgentRoot) {
    foreach ($agentName in $expectedAgents) {
        $packagedAgent = Get-Content (Join-Path $agentRoot "$agentName.agent.md") -Raw
        $workspaceAgent = Get-Content (Join-Path $workspaceAgentRoot "$agentName.agent.md") -Raw
        Assert-True ((($packagedAgent -replace "`r`n", "`n").TrimEnd()) -ceq (($workspaceAgent -replace "`r`n", "`n").TrimEnd())) "Packaged and workspace definitions differ for $agentName."
    }
}

$packagedSkill = Get-Content (Join-Path $packageRoot "skills\ultron-orchestrator\SKILL.md") -Raw
$workspaceSkillPath = Join-Path $workspaceRoot ".github\skills\ultron-orchestrator\SKILL.md"
if (Test-Path $workspaceSkillPath) {
    $workspaceSkill = Get-Content $workspaceSkillPath -Raw
    Assert-True ((($packagedSkill -replace "`r`n", "`n").TrimEnd()) -ceq (($workspaceSkill -replace "`r`n", "`n").TrimEnd())) "Packaged and workspace skill definitions differ."
}
Assert-True ($packagedSkill -match "No Progress Narration") "Orchestrator skill is missing the silent execution policy."
Assert-True ($packagedSkill -match 'responds only with `0`') "Orchestrator skill must enforce binary success output."
Assert-True ($packagedSkill -match 'or `1` when completion is impossible') "Orchestrator skill must enforce binary failure output."
Assert-True ($packagedSkill -match "multiple subagents in one parallel batch") "Orchestrator skill must permit safe parallel delegation."
Assert-True ($packagedSkill -match "exactly one detailed, narrowly scoped task") "Orchestrator skill must enforce one narrow task per subagent."
Assert-True ($packagedSkill -match "Subagents never orchestrate, spawn agents") "Orchestrator skill must forbid recursive delegation."
Assert-True ($packagedSkill -match "Engineering Quality") "Orchestrator skill must preserve engineering quality."
Assert-True ($packagedSkill -match "high reasoning for code analysis and medium reasoning for research and implementation") "Orchestrator skill must route Luna reasoning by role."
Assert-True ($packagedSkill -match "available browser or Playwright tools") "Orchestrator skill must require browser validation when applicable."
Assert-True ($packagedSkill -match "## Explain Mode") "Orchestrator skill is missing explain mode guidance."

$packagedExplainPrompt = Get-Content (Join-Path $promptRoot "explain.prompt.md") -Raw
$workspaceExplainPromptPath = Join-Path $workspaceRoot ".github\prompts\explain.prompt.md"
if (Test-Path $workspaceExplainPromptPath) {
    $workspaceExplainPrompt = Get-Content $workspaceExplainPromptPath -Raw
    Assert-True ((($packagedExplainPrompt -replace "`r`n", "`n").TrimEnd()) -ceq (($workspaceExplainPrompt -replace "`r`n", "`n").TrimEnd())) "Packaged and workspace explain prompts differ."
}
Assert-True ($packagedExplainPrompt -match "(?m)^name:\s*explain\s*$") "Explain prompt must register the /explain command."
Assert-True ($packagedExplainPrompt -notmatch "(?m)^agent:") "Explain prompt must preserve the currently selected agent."
Assert-True ($packagedExplainPrompt -notmatch "(?m)^model:") "Explain prompt must preserve the current agent model."
Assert-True ($packagedExplainPrompt -match "private chain-of-thought") "Explain prompt must protect private reasoning."

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
    Assert-True ($content -notmatch 'Give `luna_code_analyst` one tightly scoped') "$leadName native role must not require analysis delegation for every implementation task."
}

$launchers = @{
    "start-edith.ps1" = @{ Model = "gpt-5.6-luna"; Effort = "low" }
    "start-ultron.ps1" = @{ Model = "gpt-5.6-sol"; Effort = "high" }
    "start-jarvis.ps1" = @{ Model = "gpt-5.6-terra"; Effort = "medium" }
    "start-edith.sh" = @{ Model = "gpt-5.6-luna"; Effort = "low" }
    "start-ultron.sh" = @{ Model = "gpt-5.6-sol"; Effort = "high" }
    "start-jarvis.sh" = @{ Model = "gpt-5.6-terra"; Effort = "medium" }
}
foreach ($launcherName in $launchers.Keys) {
    $content = Get-Content (Join-Path $PSScriptRoot $launcherName) -Raw
    Assert-True ($content -notmatch 'long_context|--model auto') "Forbidden routing found in $launcherName."
    if ($launcherName -like "*.ps1") {
        Assert-True ($content -match ('"--model",\s*"' + [regex]::Escape($launchers[$launcherName].Model) + '"')) "Invalid model in $launcherName."
        Assert-True ($content -match ('"--reasoning-effort",\s*"' + [regex]::Escape($launchers[$launcherName].Effort) + '"')) "Invalid reasoning effort in $launcherName."
        Assert-True ($content -match '"--context",\s*"default"') "Missing default context in $launcherName."
        Assert-True ($content -match '\$arguments \+= @\("-i", \$Prompt\)') "$launcherName must pass its initial prompt through Copilot interactive mode."
    } else {
        Assert-True ($content -match ('--model\s+' + [regex]::Escape($launchers[$launcherName].Model))) "Invalid model in $launcherName."
        Assert-True ($content -match ('--reasoning-effort\s+' + [regex]::Escape($launchers[$launcherName].Effort))) "Invalid reasoning effort in $launcherName."
        Assert-True ($content -match '--context\s+default') "Missing default context in $launcherName."
    }
    Assert-True ($content -match 'allow-all-tools') "$launcherName must allow tools without widening path access."
    Assert-True ($content -match 'allow-all-urls') "$launcherName must allow web access without widening path access."
    Assert-True ($content -match 'disallow-temp-dir') "$launcherName must exclude the system temporary directory by default."
    Assert-True ($content -match '--sandbox') "$launcherName must enable the local OS sandbox by default."
    Assert-True ($content -notmatch 'allow-all-paths') "$launcherName must not widen access beyond the working directory."
}

foreach ($launcherName in @("start-edith.ps1", "start-ultron.ps1", "start-jarvis.ps1")) {
    $content = Get-Content (Join-Path $PSScriptRoot $launcherName) -Raw
    Assert-True ($content -match '\[CmdletBinding\(PositionalBinding = \$false\)\]') "$launcherName must disable positional argument binding."
    Assert-True ($content -notmatch '\[string\]\$Model|\[string\]\$Context|\$ReasoningEffort') "$launcherName permits routing overrides."
    Assert-True ($content -match '\$args\.Count -gt 0') "$launcherName does not reject unsupported arguments."
    Assert-True ($content -match '\[int\]\$MaxAiCredits') "$launcherName must pass whole, culture-independent credit limits."
    Assert-True ($content -match '\[switch\]\$AllowAll = \(\$env:COPILOT_ALLOW_ALL -eq "true"\)') "$launcherName must keep system-wide paths opt-in."
    Assert-True ($content -match '\[switch\]\$Sandbox = \(\$env:COPILOT_SANDBOX -ne "false"\)') "$launcherName must enable sandboxing by default."
}

foreach ($launcherName in @("start-edith.sh", "start-ultron.sh", "start-jarvis.sh")) {
    $content = Get-Content (Join-Path $PSScriptRoot $launcherName) -Raw
    Assert-True ($content -match '--model\|--model=\*\|--context\|--context=\*\|--reasoning-effort\|--reasoning-effort=\*') "$launcherName does not reject routing overrides."
    Assert-True ($content -match '--agent\|--agent=\*\|--plugin-dir\|--plugin-dir=\*') "$launcherName permits agent or plugin routing overrides."
    Assert-True ($content -match '\$\{COPILOT_ALLOW_ALL:-false\}') "$launcherName must keep system-wide paths opt-in."
    Assert-True ($content -match '\$\{COPILOT_SANDBOX:-true\}') "$launcherName must enable sandboxing by default."
}

$readme = Get-Content (Join-Path $packageRoot "README.md") -Raw
Assert-True ($readme -match 'Ultron uses `gpt-5\.6-sol` with high reasoning') "README must document Ultron model routing."
Assert-True ($readme -match 'Jarvis uses `gpt-5\.6-terra` with medium reasoning') "README must document Jarvis model routing."
Assert-True ($readme -match 'Edith uses `gpt-5\.6-luna` with low reasoning') "README must document Edith model routing."
Assert-True ($readme -notmatch "max reasoning") "README must not advertise blanket maximum reasoning."
Assert-True ($readme -match 'canonical `playwright/\*` namespace') "README must document the canonical Playwright namespace."
Assert-True ($readme -match '@mcp playwright') "README must document the VS Code Playwright MCP installation."
Assert-True ($readme -match '@playwright/mcp@0\.0\.79') "README must document the pinned Playwright MCP fallback."
Assert-True ($readme -match "install-plugin\.ps1" -and $readme -match "install-plugin\.sh") "README must document native plugin replacement scripts."
Assert-True ($readme -match "ultron-orchestrator@ultron-agent" -and $readme -match "deprecated direct-plugin installation") "README must document marketplace-based plugin replacement."
Assert-True ($readme -match "Repeat runs are managed upgrades") "README must document managed copy-install upgrades."
Assert-True ($readme -match "local OS sandbox") "README must document the workspace sandbox default."

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
