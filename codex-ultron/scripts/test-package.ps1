[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$packageRoot = Split-Path -Parent $PSScriptRoot
$agentRoot = Join-Path $packageRoot "agents"
$profileRoot = Join-Path $packageRoot "profiles"
$expectedAgents = @{
    "edith.toml" = "gpt-5.6-luna"
    "ultron.toml" = "gpt-6-astra"
    "jarvis.toml" = "gpt-5.6-sol"
    "luna_code_analyst.toml" = "gpt-5.6-luna"
    "luna_researcher.toml" = "gpt-5.6-luna"
    "luna_worker.toml" = "gpt-5.6-luna"
}
$expectedAgentEfforts = @{
    "edith.toml" = "xhigh"
    "ultron.toml" = "medium"
    "jarvis.toml" = "high"
    "luna_code_analyst.toml" = "xhigh"
    "luna_researcher.toml" = "xhigh"
    "luna_worker.toml" = "xhigh"
}
$expectedProfiles = @{
    "edith.config.toml" = "gpt-5.6-luna"
    "ultron.config.toml" = "gpt-6-astra"
    "jarvis.config.toml" = "gpt-5.6-sol"
}
$expectedProfileEfforts = @{
    "edith.config.toml" = "xhigh"
    "ultron.config.toml" = "medium"
    "jarvis.config.toml" = "high"
}

function Assert-True {
    param(
        [Parameter(Mandatory)]
        [bool]$Condition,
        [Parameter(Mandatory)]
        [string]$Message
    )

    if (-not $Condition) { throw $Message }
}

Assert-True ((Get-ChildItem $agentRoot -Filter "*.toml").Count -eq 6) "Package must contain six custom agents."
foreach ($agentFile in $expectedAgents.Keys) {
    $content = (Get-Content (Join-Path $agentRoot $agentFile) -Raw) -replace "`r`n", "`n"
    Assert-True ($content -match '(?m)^name = "[^"]+"$') "$agentFile is missing a name."
    Assert-True ($content -match '(?m)^description = "[^"]+"$') "$agentFile is missing a description."
    Assert-True ($content -match '(?m)^developer_instructions = """') "$agentFile is missing developer instructions."
    $developerInstructions = [regex]::Match($content, '(?m)^developer_instructions\s*=')
    $firstTable = [regex]::Match($content, '(?m)^\[')
    Assert-True ($developerInstructions.Success -and (-not $firstTable.Success -or $developerInstructions.Index -lt $firstTable.Index)) "$agentFile must define developer instructions at the TOML root."
    Assert-True ($content -match ('(?m)^model = "' + [regex]::Escape($expectedAgents[$agentFile]) + '"$')) "Invalid model in $agentFile."
    Assert-True ($content -match ('(?m)^model_reasoning_effort = "' + [regex]::Escape($expectedAgentEfforts[$agentFile]) + '"$')) "Invalid reasoning effort in $agentFile."
    Assert-True ($content -match '(?m)^model_verbosity = "low"$') "$agentFile must minimize model verbosity."
    Assert-True ($content -match '(?m)^sandbox_mode = "danger-full-access"$') "$agentFile must default to full access."
    Assert-True ($content -match '(?m)^web_search = "live"$') "$agentFile must enable live web access."
    Assert-True ($content -match '(?m)^\[plugins\."browser@openai-bundled"\]\nenabled = true$') "$agentFile must enable the bundled Browser plugin."
}

foreach ($leadFile in @("edith.toml", "jarvis.toml", "ultron.toml")) {
    $content = (Get-Content (Join-Path $agentRoot $leadFile) -Raw) -replace "`r`n", "`n"
    Assert-True ($content -match '(?m)^approval_policy = "never"$') "$leadFile must run without approval prompts."
    Assert-True ($content -match '(?m)^sandbox_mode = "danger-full-access"$') "$leadFile must default to full access."
    Assert-True ($content -match '(?m)^web_search = "live"$') "$leadFile must enable live web access."
    Assert-True ($content -match '(?m)^\[plugins\."browser@openai-bundled"\]\nenabled = true$') "$leadFile must enable the bundled Browser plugin."
    Assert-True ($content -match 'work silently without progress, plan, reasoning, tool, or status narration') "$leadFile must use the silent output contract."
    Assert-True ($content -match 'respond only with `0`') "$leadFile must use binary success output."
    Assert-True ($content -match 'respond only with `1`') "$leadFile must use binary failure output."
    Assert-True ($content -match '(?m)^model_reasoning_summary = "none"$') "$leadFile must suppress reasoning summaries."
    Assert-True ($content -match '(?m)^personality = "pragmatic"$') "$leadFile must use the pragmatic personality."
    Assert-True ($content -match '(?m)^hide_agent_reasoning = true$') "$leadFile must hide reasoning output."
    Assert-True ($content -match '(?m)^\[agents\]\nenabled = true$') "$leadFile must enable native subagents."
    Assert-True ($content -match '(?m)^max_concurrent_threads_per_session = 6$') "$leadFile must set the supported subagent concurrency limit."
    Assert-True ($content -match '(?m)^default_subagent_model = "gpt-5\.6-luna"$') "$leadFile must default subagents to Luna."
    Assert-True ($content -match '(?m)^default_subagent_reasoning_effort = "xhigh"$') "$leadFile must default subagents to maximum Luna reasoning."
}

foreach ($lunaFile in $expectedAgents.Keys | Where-Object { $_ -like "luna_*" }) {
    $content = (Get-Content (Join-Path $agentRoot $lunaFile) -Raw) -replace "`r`n", "`n"
    Assert-True ($content -match "Never.*spawn, delegate") "$lunaFile must forbid recursive delegation."
    Assert-True ($content -match "one compact packet") "$lunaFile must return a bounded packet."
    Assert-True ($content -match '(?m)^approval_policy = "never"$') "$lunaFile must not prompt for approvals."
    Assert-True ($content -match '(?m)^\[agents\]\nenabled = false$') "$lunaFile must structurally disable recursive delegation."
}
foreach ($readOnlyFile in @("luna_code_analyst.toml", "luna_researcher.toml")) {
    $content = Get-Content (Join-Path $agentRoot $readOnlyFile) -Raw
    Assert-True ($content -match 'Runtime access is full, but the task contract remains read-only') "$readOnlyFile must preserve its read-only task contract."
}

$analystBoundary = 'Start with task-named files or symbols; if none are named, use only targeted searches to locate them. Never inventory directories or read unrelated files. Stop once evidence answers the assigned question.'
$analystOutputBoundary = 'Return one compact packet of at most 500 words, except when a blocker needs more detail'
$analyst = Get-Content (Join-Path $agentRoot "luna_code_analyst.toml") -Raw
Assert-True ($analyst -match [regex]::Escape($analystBoundary)) "luna_code_analyst must preserve its task-first evidence boundary."
Assert-True ($analyst -match [regex]::Escape($analystOutputBoundary)) "luna_code_analyst must preserve its compact output boundary."

$worker = (Get-Content (Join-Path $agentRoot "luna_worker.toml") -Raw) -replace "`r`n", "`n"
Assert-True ($worker -match '(?m)^approval_policy = "never"$') "luna_worker must run focused checks without approval prompts."
Assert-True ($worker -match '(?m)^sandbox_mode = "danger-full-access"$') "luna_worker must default to full access."
Assert-True ($worker -match '(?m)^web_search = "live"$') "luna_worker must enable live web access."
Assert-True ($worker -match '(?m)^\[plugins\."browser@openai-bundled"\]\nenabled = true$') "luna_worker must enable the bundled Browser plugin."
Assert-True ($worker -match 'Do not claim browser validation from source inspection') "luna_worker must require real browser evidence."
Assert-True ($worker -match 'project-local Playwright/dependencies') "luna_worker must attempt local browser recovery."
Assert-True ($worker -match 'install a suitable project-local Playwright/browser runtime') "luna_worker must install a project-local browser fallback."
Assert-True ($worker -match 'trivial one-packet work may proceed without a persistent plan') "luna_worker must not deadlock trivial assignments on the plan gate."
Assert-True ($worker -match 'image tool') "luna_worker must report missing image capability."

foreach ($profileFile in $expectedProfiles.Keys) {
    $content = (Get-Content (Join-Path $profileRoot $profileFile) -Raw) -replace "`r`n", "`n"
    $developerInstructions = [regex]::Match($content, '(?m)^developer_instructions\s*=')
    $firstTable = [regex]::Match($content, '(?m)^\[')
    Assert-True ($developerInstructions.Success -and (-not $firstTable.Success -or $developerInstructions.Index -lt $firstTable.Index)) "$profileFile must define developer instructions at the TOML root."
    Assert-True ($content -match ('(?m)^model = "' + [regex]::Escape($expectedProfiles[$profileFile]) + '"$')) "Invalid model in $profileFile."
    Assert-True ($content -match ('(?m)^model_reasoning_effort = "' + [regex]::Escape($expectedProfileEfforts[$profileFile]) + '"$')) "$profileFile has the wrong reasoning effort."
    Assert-True ($content -match '(?m)^model_verbosity = "low"$') "$profileFile must minimize model verbosity."
    Assert-True ($content -match '(?m)^approval_policy = "never"$') "$profileFile must run without approval prompts."
    Assert-True ($content -match '(?m)^sandbox_mode = "danger-full-access"$') "$profileFile must default to full access."
    Assert-True ($content -match '(?m)^web_search = "live"$') "$profileFile must enable live web access."
    Assert-True ($content -match '(?m)^\[plugins\."browser@openai-bundled"\]\nenabled = true$') "$profileFile must enable the bundled Browser plugin."
    Assert-True ($content -match 'respond only with `0`') "$profileFile must use binary success output."
    Assert-True ($content -match 'respond only with `1`') "$profileFile must use binary failure output."
    Assert-True ($content -match '(?m)^default_subagent_model = "gpt-5\.6-luna"$') "$profileFile must default subagents to Luna."
    Assert-True ($content -match '(?m)^default_subagent_reasoning_effort = "xhigh"$') "$profileFile must use maximum Luna reasoning by default."
    Assert-True ($content -notmatch '(?m)^\[agents\.(edith|jarvis|ultron|luna_code_analyst|luna_researcher|luna_worker)\]$') "$profileFile must not redeclare standalone custom agent roles."
}

$sharedConfig = (Get-Content (Join-Path $packageRoot "config\codex-config.example.toml") -Raw) -replace "`r`n", "`n"
Assert-True ($sharedConfig -notmatch '(?m)^\[agents\.(edith|jarvis|ultron|luna_code_analyst|luna_researcher|luna_worker)\]$') "Project config must not redeclare standalone custom agent roles."
Assert-True ($sharedConfig -match '(?m)^approval_policy = "never"$') "Example config must disable approval prompts."
Assert-True ($sharedConfig -match '(?m)^sandbox_mode = "danger-full-access"$') "Example config must default to full access."
Assert-True ($sharedConfig -match '(?m)^\[plugins\."browser@openai-bundled"\]\nenabled = true$') "Example config must enable the bundled Browser plugin."
Assert-True ($sharedConfig -match '(?m)^default_subagent_model = "gpt-5\.6-luna"$') "Example config must default subagents to Luna."
Assert-True ($sharedConfig -match '(?m)^default_subagent_reasoning_effort = "xhigh"$') "Example config must use maximum Luna reasoning by default."

$leadContracts = @{
    edith = "Edith at your service."
    jarvis = "Jarvis at your service."
    ultron = "Lowly human, let Ultron manage the rest."
}
foreach ($leadName in $leadContracts.Keys) {
    foreach ($sourcePath in @("agents\$leadName.toml", "profiles\$leadName.config.toml", "instructions\$leadName.md")) {
        $content = Get-Content (Join-Path $packageRoot $sourcePath) -Raw
        Assert-True ($content -match [regex]::Escape($leadContracts[$leadName])) "$sourcePath is missing the exact $leadName greeting."
    }
}

$codePreflight = 'Before planning or implementation for non-trivial, ambiguous, multi-file, or architectural work, first spawn exactly one bounded read-only `luna_code_analyst` task to inspect only files and symbols needed for the assigned task or question; simple local fixes may stay direct.'
$researchPreflight = 'When the user explicitly requests external/current web research, the first external-evidence action must be exactly one bounded `luna_researcher` spawn, before lead web research.'
foreach ($leadName in @("edith", "jarvis", "ultron")) {
    foreach ($sourcePath in @("agents\$leadName.toml", "profiles\$leadName.config.toml", "instructions\$leadName.md")) {
        $content = Get-Content (Join-Path $packageRoot $sourcePath) -Raw
        Assert-True ($content -match [regex]::Escape($codePreflight)) "$sourcePath is missing the gated Luna code-analysis preflight."
        Assert-True ($content -match [regex]::Escape($researchPreflight)) "$sourcePath is missing the gated Luna research preflight."
    }
}

foreach ($sourcePath in @("agents\edith.toml", "agents\jarvis.toml", "agents\ultron.toml", "profiles\edith.config.toml", "profiles\jarvis.config.toml", "profiles\ultron.config.toml", "instructions\edith.md", "instructions\jarvis.md", "instructions\ultron.md")) {
    $content = Get-Content (Join-Path $packageRoot $sourcePath) -Raw
    Assert-True ($content -match 'native Codex custom-agent') "$sourcePath must use native Codex custom agents."
    Assert-True ($content -match 'standalone custom-agent file') "$sourcePath must delegate role configuration to the standalone agent file."
    Assert-True ($content -match 'exact `agent_type`') "$sourcePath must preserve exact Codex custom-agent identifiers."
    Assert-True ($content -match 'Before the first implementation edit for any non-trivial task') "$sourcePath must create a persistent plan before implementation."
    Assert-True ($content -match 'tasks/plans/<task-slug>\.md') "$sourcePath must use the project task-plan path."
    Assert-True ($content -match 'mandatory even when no Luna worker is used') "$sourcePath must not make planning depend on delegation."
    Assert-True ($content -match 'immediately after its focused validation') "$sourcePath must update checklist status incrementally."
    Assert-True ($content -match 'session Plan mode and internal todo tracking do not replace it') "$sourcePath must not substitute transient planning state."
    Assert-True ($content -match 'repeat the (browser )?check after changes') "$sourcePath must require browser revalidation for web-facing work."
    Assert-True ($content -match 'For each plan step, record role, count') "$sourcePath must record every plan step."
    Assert-True ($content -match 'active working folder first') "$sourcePath must prioritize the working folder."
    Assert-True ($content -match 'install a suitable project-local Playwright/browser runtime') "$sourcePath must attempt project-local browser recovery."
    Assert-True ($content -match 'route one bounded task to `luna_worker`') "$sourcePath must route browser/image elaboration to Luna worker."
    Assert-True ($content -notmatch 'Codex 0\.147|fork_turns') "$sourcePath contains obsolete runtime-specific fork guidance."
    Assert-True ($content -notmatch 'primary Codex thread|does not receive the native spawn') "$sourcePath contains an obsolete primary-thread restriction."
}

$skillRoot = Join-Path $packageRoot "skills\codex-ultron"
$skill = (Get-Content (Join-Path $skillRoot "SKILL.md") -Raw) -replace "`r`n", "`n"
$metadata = (Get-Content (Join-Path $skillRoot "agents\openai.yaml") -Raw) -replace "`r`n", "`n"
Assert-True ($skill -match '(?m)^name: codex-ultron$') "Skill name is invalid."
Assert-True ($skill -match "Lead orchestration, critical") "Skill is missing the lead execution policy."
Assert-True ($skill -match "Never overlap writers") "Skill must reject overlapping writers."
Assert-True ($skill -match "native custom agents") "Skill must use native Codex custom agents."
Assert-True ($skill -match '## Persistent Plan Gate') "Skill must enforce persistent implementation planning."
Assert-True ($skill -match 'immediately after its focused validation') "Skill must require incremental plan updates."
Assert-True ($skill -notmatch 'Codex 0\.147|fork_turns') "Skill contains obsolete runtime-specific fork guidance."
Assert-True ($skill -notmatch 'primary Codex thread|does not receive the native spawn') "Skill contains an obsolete primary-thread restriction."
Assert-True ($skill -match "first external-evidence action") "Skill must require Luna research before direct external research."
Assert-True ($skill -match [regex]::Escape($codePreflight)) "Skill must require the gated Luna code-analysis preflight."
Assert-True ($skill -match [regex]::Escape($researchPreflight)) "Skill must require the gated Luna research preflight."
Assert-True ($skill -match "gpt-6-astra.*gpt-5\.6-sol.*gpt-5\.6-luna") "Skill model policy is incomplete."
Assert-True ($skill -match "bundled Browser plugin") "Skill must require browser validation for web-facing work."
Assert-True ($metadata -match 'display_name: "Codex Ultron"') "Desktop skill metadata is missing."
Assert-True ($metadata -match 'default_prompt: .*\$codex-ultron') "Desktop skill metadata must invoke the skill explicitly."

$readme = Get-Content (Join-Path $packageRoot "README.md") -Raw
Assert-True ($readme -notmatch 'Codex CLI 0\.147|fork_turns|max reasoning') "README contains obsolete runtime or model guidance."
Assert-True ($readme -match 'tasks/plans/<task-slug>\.md') "README must document persistent implementation plans."
Assert-True ($readme -match 'browser@openai-bundled') "README must document the bundled Browser plugin."
Assert-True ($readme -match 'CODEX_ULTRON_LIVE_SEARCH=false ./scripts/start-ultron\.sh') "README must document the POSIX live-search opt-out."
Assert-True ($readme -match 'CODEX_ULTRON_FULL_ACCESS=false ./scripts/start-ultron\.sh') "README must document the POSIX restricted-access opt-out."
Assert-True ($readme -match 'danger-full-access') "README must document the full-access default."

$launchers = @{
    "start-edith.ps1" = @("edith", "gpt-5.6-luna", "xhigh")
    "start-ultron.ps1" = @("ultron", "gpt-6-astra", "medium")
    "start-jarvis.ps1" = @("jarvis", "gpt-5.6-sol", "high")
    "start-edith.sh" = @("edith", "gpt-5.6-luna", "xhigh")
    "start-ultron.sh" = @("ultron", "gpt-6-astra", "medium")
    "start-jarvis.sh" = @("jarvis", "gpt-5.6-sol", "high")
    "start-edith-app.ps1" = @("edith", "gpt-5.6-luna", "xhigh")
    "start-ultron-app.ps1" = @("ultron", "gpt-6-astra", "medium")
    "start-jarvis-app.ps1" = @("jarvis", "gpt-5.6-sol", "high")
    "start-edith-app.sh" = @("edith", "gpt-5.6-luna", "xhigh")
    "start-ultron-app.sh" = @("ultron", "gpt-6-astra", "medium")
    "start-jarvis-app.sh" = @("jarvis", "gpt-5.6-sol", "high")
}
foreach ($launcher in $launchers.Keys) {
    $content = Get-Content (Join-Path $PSScriptRoot $launcher) -Raw
    $role = $launchers[$launcher][0]
    $model = $launchers[$launcher][1]
    $effort = $launchers[$launcher][2]
    if ($launcher -like "*.ps1") {
        Assert-True ($content -match ('model="' + [regex]::Escape($model) + '"|"--model",\s*"' + [regex]::Escape($model) + '"')) "$launcher does not select its model."
        Assert-True ($content -match ('model_reasoning_effort="' + [regex]::Escape($effort) + '"')) "$launcher does not select the expected reasoning effort."
        Assert-True ($content -match ([regex]::Escape($role) + '\.md|"--profile",\s*"' + [regex]::Escape($role) + '"')) "$launcher does not select its role."
    } else {
        Assert-True ($content -match ('model="?' + [regex]::Escape($model) + '"?|--model\s+' + [regex]::Escape($model))) "$launcher does not select its model."
        Assert-True ($content -match ('model_reasoning_effort=\\?"' + [regex]::Escape($effort) + '\\?"')) "$launcher does not select the expected reasoning effort."
        Assert-True ($content -match ([regex]::Escape($role) + '\.md|--profile\s+' + [regex]::Escape($role))) "$launcher does not select its role."
    }
    Assert-True ($content -notmatch 'nickname_candidates') "$launcher must not redeclare custom agent roles."
    if ($launcher -match '-app\.(ps1|sh)$') {
        Assert-True ($content -match 'approval_policy=.*never') "$launcher must disable approval prompts."
        Assert-True ($content -match 'danger-full-access') "$launcher must default to full access."
        Assert-True ($content -match 'workspace-write') "$launcher must preserve the restricted opt-out."
        Assert-True ($content -match 'sandbox_workspace_write.network_access=true') "$launcher must enable network access within the workspace sandbox."
        Assert-True ($content -match 'web_search=.*live') "$launcher must enable live web search."
        Assert-True ($content -match 'browser@openai-bundled') "$launcher must enable the bundled Browser plugin."
    } else {
        Assert-True ($content -match '--search') "$launcher must enable live search by default."
        Assert-True ($content -match 'dangerously-bypass-approvals-and-sandbox') "$launcher must default to full access."
        Assert-True ($content -match 'CODEX_ULTRON_FULL_ACCESS.*(ne "false"|:-true)') "$launcher must preserve the restricted opt-out."
        Assert-True ($content -match 'sandbox_mode="workspace-write"') "$launcher must explicitly force restricted mode."
    }
}
$cliGreetings = @{
    "start-edith.ps1" = "Edith at your service."
    "start-jarvis.ps1" = "Jarvis at your service."
    "start-ultron.ps1" = "Lowly human, let Ultron manage the rest."
    "start-edith.sh" = "Edith at your service."
    "start-jarvis.sh" = "Jarvis at your service."
    "start-ultron.sh" = "Lowly human, let Ultron manage the rest."
    "start-codex.ps1" = "Jarvis at your service."
    "start-codex.sh" = "Jarvis at your service."
}
foreach ($launcher in $cliGreetings.Keys) {
    $content = Get-Content (Join-Path $PSScriptRoot $launcher) -Raw
    $greeting = [regex]::Escape($cliGreetings[$launcher])
    Assert-True ($content -match ('(?s)' + $greeting + '.*(?:& codex|exec codex)')) "$launcher must emit its greeting before starting Codex."
}
$unifiedCli = Get-Content (Join-Path $PSScriptRoot "start-codex.ps1") -Raw
Assert-True ($unifiedCli -match "Choose a Codex lead:") "Unified CLI launcher is missing its lead menu."
foreach ($mapping in @(
    'edith = @{ Profile = "edith"; Model = "gpt-5\.6-luna"; Effort = "xhigh"',
    'jarvis = @{ Profile = "jarvis"; Model = "gpt-5\.6-sol"; Effort = "high"',
    'ultron = @{ Profile = "ultron"; Model = "gpt-6-astra"; Effort = "medium"'
)) {
    Assert-True ($unifiedCli -match $mapping) "Unified CLI launcher has an invalid role mapping: $mapping"
}
$unifiedApp = Get-Content (Join-Path $PSScriptRoot "start-codex-app.ps1") -Raw
Assert-True ($unifiedApp -match "Choose a Codex lead for the desktop app:") "Unified app launcher is missing its lead menu."
foreach ($mapping in @(
    'edith = @{ Model = "gpt-5\.6-luna"; Effort = "xhigh"; Instructions = "edith\.md"',
    'jarvis = @{ Model = "gpt-5\.6-sol"; Effort = "high"; Instructions = "jarvis\.md"',
    'ultron = @{ Model = "gpt-6-astra"; Effort = "medium"; Instructions = "ultron\.md"'
)) {
    Assert-True ($unifiedApp -match $mapping) "Unified app launcher has an invalid role mapping: $mapping"
}
$unifiedShell = Get-Content (Join-Path $PSScriptRoot "start-codex.sh") -Raw
$unifiedAppShell = Get-Content (Join-Path $PSScriptRoot "start-codex-app.sh") -Raw
foreach ($mapping in @(
    'edith\) profile="edith"; model="gpt-5\.6-luna"; effort="xhigh"',
    'jarvis\) profile="jarvis"; model="gpt-5\.6-sol"; effort="high"',
    'ultron\) profile="ultron"; model="gpt-6-astra"; effort="medium"'
)) {
    Assert-True ($unifiedShell -match $mapping) "Unified shell launcher has an invalid role mapping: $mapping"
}
foreach ($mapping in @(
    'edith\) model="gpt-5\.6-luna"; effort="xhigh"; instructions_file="edith\.md"',
    'jarvis\) model="gpt-5\.6-sol"; effort="high"; instructions_file="jarvis\.md"',
    'ultron\) model="gpt-6-astra"; effort="medium"; instructions_file="ultron\.md"'
)) {
    Assert-True ($unifiedAppShell -match $mapping) "Unified app shell launcher has an invalid role mapping: $mapping"
}
foreach ($launcher in @("start-edith.sh", "start-ultron.sh", "start-jarvis.sh")) {
    $content = Get-Content (Join-Path $PSScriptRoot $launcher) -Raw
    Assert-True ($content -match '--model.*--profile.*--config') "$launcher must reject routing overrides."
}

foreach ($script in Get-ChildItem $PSScriptRoot -Filter "*.ps1") {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
    Assert-True ($parseErrors.Count -eq 0) "PowerShell parse errors in $($script.Name): $($parseErrors.Message -join '; ')"
}

$forbiddenPackageText = @(
    Get-ChildItem (Join-Path $packageRoot "agents") -File -Recurse
    Get-ChildItem (Join-Path $packageRoot "profiles") -File -Recurse
    Get-ChildItem (Join-Path $packageRoot "config") -File -Recurse
    Get-ChildItem (Join-Path $packageRoot "skills") -File -Recurse
) | ForEach-Object { Get-Content $_.FullName -Raw }
$forbiddenPackageText = $forbiddenPackageText -join "`n"
Assert-True ($forbiddenPackageText -notmatch '(?i)auth\.json|api[_-]?key|bearer[_-]?token|installation_id') "Package contains credential or machine-state references."

$powerShellInstaller = Get-Content (Join-Path $PSScriptRoot "install.ps1") -Raw
$shellInstaller = Get-Content (Join-Path $PSScriptRoot "install.sh") -Raw
Assert-True ($powerShellInstaller -match '\.codex-ultron-agents' -and $shellInstaller -match '\.codex-ultron-agents') "Both installers must record managed agents."
Assert-True ($powerShellInstaller -match 'codex-ultron\.example\.toml' -and $shellInstaller -match 'codex-ultron\.example\.toml') "Both installers must use a package-specific project config example."
Assert-True ($powerShellInstaller -notmatch 'Destination = Join-Path \$resolvedProject "\.codex\\config\.toml"') "PowerShell installer must not replace project config.toml."
Assert-True ($shellInstaller -notmatch 'copy_package_file .*config\.toml"') "Shell installer must not replace project config.toml."

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('.codex-ultron-test-' + [guid]::NewGuid())
$tempHome = Join-Path $tempRoot "home"
$tempProject = Join-Path $tempRoot "project"
New-Item -ItemType Directory -Path $tempHome, $tempProject -Force | Out-Null
$oldCodexHome = $env:CODEX_HOME
try {
    $env:CODEX_HOME = Join-Path $tempHome ".codex"
    & (Join-Path $PSScriptRoot "install.ps1") -HomePath $tempHome

    $mockBin = Join-Path $tempRoot "mock-bin"
    New-Item -ItemType Directory -Path $mockBin -Force | Out-Null
    Set-Content -Path (Join-Path $mockBin "codex.cmd") -Value "@echo off`r`necho %*"
    $oldPath = $env:PATH
    $oldFullAccess = $env:CODEX_ULTRON_FULL_ACCESS
    $env:PATH = "$mockBin;$oldPath"
    $agentRoot = Join-Path $env:CODEX_HOME "agents"
    Remove-Item Env:CODEX_ULTRON_FULL_ACCESS -ErrorAction SilentlyContinue
    $defaultCliInvocation = (& (Join-Path $PSScriptRoot "start-ultron.ps1") -Prompt "mock") -join "`n"
    Assert-True ($defaultCliInvocation -match 'dangerously-bypass-approvals-and-sandbox') "CLI launcher must default to full access."
    Assert-True ($defaultCliInvocation -match 'gpt-6-astra') "CLI launcher mock must preserve Ultron routing."
    $env:CODEX_ULTRON_FULL_ACCESS = "false"
    $restrictedCliInvocation = (& (Join-Path $PSScriptRoot "start-ultron.ps1") -Prompt "mock") -join "`n"
    Assert-True ($restrictedCliInvocation -match 'sandbox_mode="workspace-write"') "CLI restricted opt-out must force workspace-write."
    Remove-Item Env:CODEX_ULTRON_FULL_ACCESS -ErrorAction SilentlyContinue
    $defaultAppInvocation = (& (Join-Path $PSScriptRoot "start-ultron-app.ps1") -WorkingDirectory $tempProject) -join "`n"
    Assert-True ($defaultAppInvocation -match 'sandbox_mode="danger-full-access"') "Desktop launcher must default to full access."
    Assert-True ($defaultAppInvocation -match 'agents\.enabled=true') "Desktop launcher must enable native subagents."
    Assert-True ($defaultAppInvocation -match 'agents\.max_concurrent_threads_per_session=6') "Desktop launcher must set the supported subagent concurrency limit."
    Assert-True ($defaultAppInvocation -match 'agents\.default_subagent_model="gpt-5\.6-luna"') "Desktop launcher must default subagents to Luna."
    Assert-True ($defaultAppInvocation -match 'agents\.default_subagent_reasoning_effort="xhigh"') "Desktop launcher must default subagents to maximum Luna reasoning."
    $missingLunaPath = Join-Path $agentRoot "luna_researcher.toml"
    $missingLunaContent = Get-Content $missingLunaPath -Raw
    Remove-Item $missingLunaPath -Force
    $missingLunaRejected = $false
    try { & (Join-Path $PSScriptRoot "start-ultron-app.ps1") -WorkingDirectory $tempProject } catch { $missingLunaRejected = $_.Exception.Message -match "luna_researcher.toml" }
    Assert-True $missingLunaRejected "Desktop launcher must reject an incomplete Luna installation."
    Set-Content -Path $missingLunaPath -Value $missingLunaContent -Encoding UTF8
    $env:CODEX_ULTRON_FULL_ACCESS = "false"
    $restrictedAppInvocation = (& (Join-Path $PSScriptRoot "start-ultron-app.ps1") -WorkingDirectory $tempProject) -join "`n"
    Assert-True ($restrictedAppInvocation -match 'sandbox_mode="workspace-write"') "Desktop restricted opt-out must force workspace-write."
    $env:PATH = $oldPath
    if ($null -eq $oldFullAccess) { Remove-Item Env:CODEX_ULTRON_FULL_ACCESS -ErrorAction SilentlyContinue } else { $env:CODEX_ULTRON_FULL_ACCESS = $oldFullAccess }

    $userFiles = @(Get-ChildItem $tempHome -File -Force -Recurse)
    Assert-True ($userFiles.Count -eq 13) "User install must create eleven package files and two ownership markers; found $($userFiles.Count)."

    $agentMarker = Join-Path $agentRoot ".codex-ultron-agents"
    $profileMarker = Join-Path $env:CODEX_HOME ".codex-ultron-profiles"
    $staleAgent = Join-Path $agentRoot "retired_luna.toml"
    $staleProfile = Join-Path $env:CODEX_HOME "retired.config.toml"
    $unrelatedAgent = Join-Path $agentRoot "personal_reviewer.toml"
    Add-Content -Path $agentMarker -Value "retired_luna.toml"
    Add-Content -Path $profileMarker -Value "retired.config.toml"
    Set-Content -Path $staleAgent -Value "retired"
    Set-Content -Path $staleProfile -Value "retired"
    Set-Content -Path $unrelatedAgent -Value "personal-content"

    & (Join-Path $PSScriptRoot "install.ps1") -HomePath $tempHome
    Assert-True (-not (Test-Path $staleAgent)) "Repeat user install must remove stale managed agents."
    Assert-True (-not (Test-Path $staleProfile)) "Repeat user install must remove stale managed profiles."
    Assert-True ((Get-Content $unrelatedAgent -Raw).Trim() -eq "personal-content") "Repeat user install must preserve unrelated files."

    Remove-Item $agentMarker, $profileMarker -Force
    & (Join-Path $PSScriptRoot "install.ps1") -HomePath $tempHome
    Assert-True (Test-Path $agentMarker) "A legacy pre-marker install must upgrade and create the agent marker."
    Assert-True (Test-Path $profileMarker) "A legacy pre-marker install must upgrade and create the profile marker."

    $managedAgentNames = @(Get-Content $agentMarker | Where-Object { $_ -ne "edith.toml" })
    Set-Content -Path $agentMarker -Value $managedAgentNames -Encoding UTF8
    $unmanagedCurrentAgent = Join-Path $agentRoot "edith.toml"
    Set-Content -Path $unmanagedCurrentAgent -Value "user-owned-edith"
    $upgradeCollisionRejected = $false
    try { & (Join-Path $PSScriptRoot "install.ps1") -HomePath $tempHome } catch { $upgradeCollisionRejected = $_.Exception.Message -match "Refusing partial install" }
    Assert-True $upgradeCollisionRejected "Repeat user install must reject a current filename absent from its ownership marker."
    Assert-True ((Get-Content $unmanagedCurrentAgent -Raw).Trim() -eq "user-owned-edith") "Repeat user install must preserve an unmanaged current-name collision."

    $conflictHome = Join-Path $tempRoot "conflict-home"
    $env:CODEX_HOME = Join-Path $conflictHome ".codex"
    $conflictAgentRoot = Join-Path $env:CODEX_HOME "agents"
    New-Item -ItemType Directory -Path $conflictAgentRoot -Force | Out-Null
    $conflictAgent = Join-Path $conflictAgentRoot "ultron.toml"
    Set-Content -Path $conflictAgent -Value "unrelated"
    $conflictRejected = $false
    try { & (Join-Path $PSScriptRoot "install.ps1") -HomePath $conflictHome } catch { $conflictRejected = $_.Exception.Message -match "Refusing partial install" }
    Assert-True $conflictRejected "Fresh user install must reject unmanaged conflicts before writing."
    Assert-True ((Get-Content $conflictAgent -Raw).Trim() -eq "unrelated") "Fresh user install must preserve an unmanaged conflict."

    & (Join-Path $PSScriptRoot "install.ps1") -HomePath $conflictHome -Force
    Assert-True ((Get-Content $conflictAgent -Raw) -match '(?m)^name = "ultron"\r?$') "Force install must replace an unmanaged collision."
    $conflictAgentMarker = Join-Path $conflictAgentRoot ".codex-ultron-agents"
    Assert-True ((Get-Content $conflictAgentMarker) -contains "ultron.toml") "Force install must record ownership of the replaced collision."

    Add-Content -Path $conflictAgentMarker -Value ".."
    $parentSentinel = Join-Path $conflictHome "parent-sentinel.txt"
    Set-Content -Path $parentSentinel -Value "preserve"
    $unsafeMarkerRejected = $false
    try { & (Join-Path $PSScriptRoot "install.ps1") -HomePath $conflictHome } catch { $unsafeMarkerRejected = $_.Exception.Message -match "Unsafe managed file entry" }
    Assert-True $unsafeMarkerRejected "Installer must reject unsafe ownership-marker entries."
    Assert-True ((Get-Content $parentSentinel -Raw).Trim() -eq "preserve") "Unsafe marker rejection must not change parent files."

    $projectConfigRoot = Join-Path $tempProject ".codex"
    New-Item -ItemType Directory -Path $projectConfigRoot -Force | Out-Null
    $projectConfig = Join-Path $projectConfigRoot "config.toml"
    Set-Content -Path $projectConfig -Value 'model = "user-owned"'
    & (Join-Path $PSScriptRoot "install.ps1") -Scope Project -ProjectPath $tempProject
    Assert-True ((Get-Content $projectConfig -Raw).Trim() -eq 'model = "user-owned"') "Project install must preserve config.toml."
    Assert-True (Test-Path (Join-Path $projectConfigRoot "codex-ultron.example.toml")) "Project install must write the package config example."
    Assert-True (Test-Path (Join-Path $projectConfigRoot ".codex-ultron-config")) "Project install must record config-example ownership."

    $projectAgentRoot = Join-Path $projectConfigRoot "agents"
    $projectAgentMarker = Join-Path $projectAgentRoot ".codex-ultron-agents"
    $staleProjectAgent = Join-Path $projectAgentRoot "retired_luna.toml"
    Add-Content -Path $projectAgentMarker -Value "retired_luna.toml"
    Set-Content -Path $staleProjectAgent -Value "retired"
    & (Join-Path $PSScriptRoot "install.ps1") -Scope Project -ProjectPath $tempProject
    Assert-True (-not (Test-Path $staleProjectAgent)) "Repeat project install must remove stale managed agents."
    Assert-True ((Get-Content $projectConfig -Raw).Trim() -eq 'model = "user-owned"') "Repeat project install must preserve config.toml."

    $env:CODEX_HOME = Join-Path $tempHome ".codex"
    if ($null -ne (Get-Command codex -ErrorAction SilentlyContinue)) {
        & codex debug prompt-input --help 2>&1 | Out-Null
        $supportsPromptInput = $LASTEXITCODE -eq 0
        $profileGreetings = @{
            ultron = "Lowly human, let Ultron manage the rest."
            jarvis = "Jarvis at your service."
            edith = "Edith at your service."
        }
        foreach ($profileName in $profileGreetings.Keys) {
            if ($supportsPromptInput) {
                $profilePrompt = & codex --profile $profileName debug prompt-input "package validation" 2>&1
                Assert-True ($LASTEXITCODE -eq 0) "Codex failed to resolve the $profileName profile."
                if (($profilePrompt -join "`n") -notmatch [regex]::Escape($profileGreetings[$profileName])) {
                    Write-Warning "Codex debug prompt-input did not expose the $profileName profile instructions; static profile checks remain authoritative."
                }
            }
            & codex --profile $profileName mcp list | Out-Null
            Assert-True ($LASTEXITCODE -eq 0) "Codex failed to load the $profileName profile."
        }
        if (-not $supportsPromptInput) {
            Write-Warning "Codex debug prompt-input is unavailable; skipped effective instruction rendering checks."
        }
        $desktopInstructions = Get-Content (Join-Path $packageRoot "instructions\ultron.md") -Raw | ConvertTo-Json -Compress
        & codex --config 'model="gpt-6-astra"' --config 'model_reasoning_effort="medium"' --config 'approval_policy="never"' --config 'sandbox_mode="danger-full-access"' --config 'web_search="live"' --config 'plugins."browser@openai-bundled".enabled=true' --config "developer_instructions=$desktopInstructions" mcp list | Out-Null
        Assert-True ($LASTEXITCODE -eq 0) "Codex failed to load desktop-style Ultron configuration."
    } else {
        Write-Warning "Codex CLI not found; skipped executable profile checks."
    }
} finally {
    if ($null -eq $oldCodexHome) {
        Remove-Item Env:CODEX_HOME -ErrorAction SilentlyContinue
    } else {
        $env:CODEX_HOME = $oldCodexHome
    }
    if (Test-Path $tempRoot) { Remove-Item $tempRoot -Recurse -Force }
}

Write-Output "Codex Ultron package checks passed."
