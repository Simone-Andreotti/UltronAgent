[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$packageRoot = Split-Path -Parent $PSScriptRoot
$agentRoot = Join-Path $packageRoot "agents"
$profileRoot = Join-Path $packageRoot "profiles"
$expectedAgents = @{
    "edith.toml" = "gpt-5.6-luna"
    "ultron.toml" = "gpt-5.6-sol"
    "jarvis.toml" = "gpt-5.6-terra"
    "luna_code_analyst.toml" = "gpt-5.6-luna"
    "luna_researcher.toml" = "gpt-5.6-luna"
    "luna_worker.toml" = "gpt-5.6-luna"
}
$expectedProfiles = @{
    "edith.config.toml" = "gpt-5.6-luna"
    "ultron.config.toml" = "gpt-5.6-sol"
    "jarvis.config.toml" = "gpt-5.6-terra"
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
    Assert-True ($content -match ('(?m)^model = "' + [regex]::Escape($expectedAgents[$agentFile]) + '"$')) "Invalid model in $agentFile."
}

foreach ($lunaFile in $expectedAgents.Keys | Where-Object { $_ -like "luna_*" }) {
    $content = (Get-Content (Join-Path $agentRoot $lunaFile) -Raw) -replace "`r`n", "`n"
    Assert-True ($content -match '(?m)^model_reasoning_effort = "max"$') "$lunaFile must use max reasoning."
    Assert-True ($content -match "Never.*spawn, delegate") "$lunaFile must forbid recursive delegation."
    Assert-True ($content -match "one compact packet") "$lunaFile must return a bounded packet."
}

foreach ($profileFile in $expectedProfiles.Keys) {
    $content = (Get-Content (Join-Path $profileRoot $profileFile) -Raw) -replace "`r`n", "`n"
    Assert-True ($content -match ('(?m)^model = "' + [regex]::Escape($expectedProfiles[$profileFile]) + '"$')) "Invalid model in $profileFile."
    Assert-True ($content -match '(?m)^model_reasoning_effort = "high"$') "$profileFile must use high reasoning."
    Assert-True ($content -match '(?m)^model_verbosity = "low"$') "$profileFile must minimize model verbosity."
    Assert-True ($content -match 'respond only with `0`') "$profileFile must use binary success output."
    Assert-True ($content -match 'respond only with `1`') "$profileFile must use binary failure output."
    Assert-True ($content -match '(?m)^default_subagent_model = "gpt-5\.6-luna"$') "$profileFile must default subagents to Luna."
    Assert-True ($content -match '(?m)^default_subagent_reasoning_effort = "max"$') "$profileFile must use max Luna reasoning."
    Assert-True ($content -notmatch '(?m)^\[agents\.(edith|jarvis|ultron|luna_code_analyst|luna_researcher|luna_worker)\]$') "$profileFile must not redeclare standalone custom agent roles."
}

$sharedConfig = (Get-Content (Join-Path $packageRoot "config\codex-config.example.toml") -Raw) -replace "`r`n", "`n"
Assert-True ($sharedConfig -notmatch '(?m)^\[agents\.(edith|jarvis|ultron|luna_code_analyst|luna_researcher|luna_worker)\]$') "Project config must not redeclare standalone custom agent roles."

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

foreach ($sourcePath in @("agents\ultron.toml", "profiles\ultron.config.toml", "instructions\ultron.md")) {
    $content = Get-Content (Join-Path $packageRoot $sourcePath) -Raw
    Assert-True ($content -match 'first external-evidence action must be a `luna_researcher` spawn') "$sourcePath is missing the mandatory research handoff."
}

foreach ($sourcePath in @("agents\edith.toml", "agents\jarvis.toml", "agents\ultron.toml", "profiles\edith.config.toml", "profiles\jarvis.config.toml", "profiles\ultron.config.toml", "instructions\edith.md", "instructions\jarvis.md", "instructions\ultron.md")) {
    $content = Get-Content (Join-Path $packageRoot $sourcePath) -Raw
    Assert-True ($content -match 'Spawn a fresh child thread') "$sourcePath must require a fresh Codex child thread."
    Assert-True ($content -match 'fork_turns.*none') "$sourcePath must disable full-history context for custom-agent spawns."
    Assert-True ($content -match 'full-history fork') "$sourcePath must reject incompatible full-history role forks."
    Assert-True ($content -match 'exact underscore identifier') "$sourcePath must preserve exact Codex custom-agent identifiers."
}

$skillRoot = Join-Path $packageRoot "skills\codex-ultron"
$skill = (Get-Content (Join-Path $skillRoot "SKILL.md") -Raw) -replace "`r`n", "`n"
$metadata = (Get-Content (Join-Path $skillRoot "agents\openai.yaml") -Raw) -replace "`r`n", "`n"
Assert-True ($skill -match '(?m)^name: codex-ultron$') "Skill name is invalid."
Assert-True ($skill -match "Execute small, well-scoped work directly") "Skill is missing the direct execution path."
Assert-True ($skill -match "Never overlap writers") "Skill must reject overlapping writers."
Assert-True ($skill -match "primary Codex thread") "Skill must document the primary-thread delegation boundary."
Assert-True ($skill -match "first external-evidence action") "Skill must require Luna research before direct external research."
Assert-True ($skill -match "gpt-5\.6-sol.*gpt-5\.6-terra.*gpt-5\.6-luna") "Skill model policy is incomplete."
Assert-True ($metadata -match 'display_name: "Codex Ultron"') "Desktop skill metadata is missing."

$launchers = @{
    "start-edith.ps1" = @("edith", "gpt-5.6-luna")
    "start-ultron.ps1" = @("ultron", "gpt-5.6-sol")
    "start-jarvis.ps1" = @("jarvis", "gpt-5.6-terra")
    "start-edith.sh" = @("edith", "gpt-5.6-luna")
    "start-ultron.sh" = @("ultron", "gpt-5.6-sol")
    "start-jarvis.sh" = @("jarvis", "gpt-5.6-terra")
    "start-edith-app.ps1" = @("edith", "gpt-5.6-luna")
    "start-ultron-app.ps1" = @("ultron", "gpt-5.6-sol")
    "start-jarvis-app.ps1" = @("jarvis", "gpt-5.6-terra")
    "start-edith-app.sh" = @("edith", "gpt-5.6-luna")
    "start-ultron-app.sh" = @("ultron", "gpt-5.6-sol")
    "start-jarvis-app.sh" = @("jarvis", "gpt-5.6-terra")
    "start-codex.ps1" = @("edith", "gpt-5.6-luna")
    "start-codex-app.ps1" = @("edith", "gpt-5.6-luna")
    "start-codex.sh" = @("edith", "gpt-5.6-luna")
    "start-codex-app.sh" = @("edith", "gpt-5.6-luna")
}
foreach ($launcher in $launchers.Keys) {
    $content = Get-Content (Join-Path $PSScriptRoot $launcher) -Raw
    Assert-True ($content -match [regex]::Escape($launchers[$launcher][0])) "$launcher does not select its profile."
    Assert-True ($content -match [regex]::Escape($launchers[$launcher][1])) "$launcher does not select its model."
    Assert-True ($content -match 'model_reasoning_effort') "$launcher does not select reasoning effort."
    Assert-True ($content -notmatch 'nickname_candidates') "$launcher must not redeclare custom agent roles."
}
$unifiedCli = Get-Content (Join-Path $PSScriptRoot "start-codex.ps1") -Raw
Assert-True ($unifiedCli -match "Choose a Codex lead:") "Unified CLI launcher is missing its lead menu."
Assert-True ($unifiedCli -match 'Profile = "edith"' -and $unifiedCli -match 'Profile = "jarvis"' -and $unifiedCli -match 'Profile = "ultron"') "Unified CLI launcher must expose all three leads."
$unifiedApp = Get-Content (Join-Path $PSScriptRoot "start-codex-app.ps1") -Raw
Assert-True ($unifiedApp -match "Choose a Codex lead for the desktop app:") "Unified app launcher is missing its lead menu."
Assert-True ($unifiedApp -match 'Instructions = "edith.md"' -and $unifiedApp -match 'Instructions = "jarvis.md"' -and $unifiedApp -match 'Instructions = "ultron.md"') "Unified app launcher must expose all three leads."
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

$tempRoot = Join-Path $packageRoot ('.test-' + [guid]::NewGuid())
$tempHome = Join-Path $tempRoot "home"
$tempProject = Join-Path $tempRoot "project"
New-Item -ItemType Directory -Path $tempHome, $tempProject -Force | Out-Null
$oldCodexHome = $env:CODEX_HOME
try {
    $env:CODEX_HOME = Join-Path $tempHome ".codex"
    & (Join-Path $PSScriptRoot "install.ps1") -HomePath $tempHome
    $userFiles = @(Get-ChildItem $tempHome -File -Force -Recurse)
    Assert-True ($userFiles.Count -eq 11) "User install must create eleven files; found $($userFiles.Count)."

    $conflictRejected = $false
    try { & (Join-Path $PSScriptRoot "install.ps1") -HomePath $tempHome } catch { $conflictRejected = $_.Exception.Message -match "Refusing partial install" }
    Assert-True $conflictRejected "User installer must reject conflicts before writing."

    & (Join-Path $PSScriptRoot "install.ps1") -Scope Project -ProjectPath $tempProject
    $projectFiles = @(Get-ChildItem $tempProject -File -Force -Recurse)
    Assert-True ($projectFiles.Count -eq 9) "Project install must create nine files; found $($projectFiles.Count)."

    Assert-True ($null -ne (Get-Command codex -ErrorAction SilentlyContinue)) "Codex CLI is required for profile validation."
    & codex --profile ultron mcp list | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) "Codex failed to load the Ultron profile."
    & codex --profile jarvis mcp list | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) "Codex failed to load the Jarvis profile."
    & codex --profile edith mcp list | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) "Codex failed to load the Edith profile."
    $desktopInstructions = Get-Content (Join-Path $packageRoot "instructions\ultron.md") -Raw | ConvertTo-Json -Compress
    & codex --config 'model="gpt-5.6-sol"' --config 'model_reasoning_effort="high"' --config "developer_instructions=$desktopInstructions" mcp list | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) "Codex failed to load desktop-style Ultron configuration."
} finally {
    $env:CODEX_HOME = $oldCodexHome
    if (Test-Path $tempRoot) { Remove-Item $tempRoot -Recurse -Force }
}

Write-Output "Codex Ultron package checks passed."