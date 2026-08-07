[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$packageRoot = Split-Path -Parent $PSScriptRoot
$agentRoot = Join-Path $packageRoot "agents"
$profileRoot = Join-Path $packageRoot "profiles"
$expectedAgents = @{
    "ultron.toml" = "gpt-5.6-sol"
    "jarvis.toml" = "gpt-5.6-terra"
    "luna_code_analyst.toml" = "gpt-5.6-luna"
    "luna_researcher.toml" = "gpt-5.6-luna"
    "luna_worker.toml" = "gpt-5.6-luna"
}
$expectedProfiles = @{
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

Assert-True ((Get-ChildItem $agentRoot -Filter "*.toml").Count -eq 5) "Package must contain five custom agents."
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
}

$skillRoot = Join-Path $packageRoot "skills\codex-ultron"
$skill = (Get-Content (Join-Path $skillRoot "SKILL.md") -Raw) -replace "`r`n", "`n"
$metadata = (Get-Content (Join-Path $skillRoot "agents\openai.yaml") -Raw) -replace "`r`n", "`n"
Assert-True ($skill -match '(?m)^name: codex-ultron$') "Skill name is invalid."
Assert-True ($skill -match "Execute small, well-scoped work directly") "Skill is missing the direct execution path."
Assert-True ($skill -match "Never overlap writers") "Skill must reject overlapping writers."
Assert-True ($skill -match "gpt-5\.6-sol.*gpt-5\.6-terra.*gpt-5\.6-luna") "Skill model policy is incomplete."
Assert-True ($metadata -match 'display_name: "Codex Ultron"') "Desktop skill metadata is missing."

$launchers = @{
    "start-ultron.ps1" = @("ultron", "gpt-5.6-sol")
    "start-jarvis.ps1" = @("jarvis", "gpt-5.6-terra")
    "start-ultron.sh" = @("ultron", "gpt-5.6-sol")
    "start-jarvis.sh" = @("jarvis", "gpt-5.6-terra")
    "start-ultron-app.ps1" = @("ultron", "gpt-5.6-sol")
    "start-jarvis-app.ps1" = @("jarvis", "gpt-5.6-terra")
    "start-ultron-app.sh" = @("ultron", "gpt-5.6-sol")
    "start-jarvis-app.sh" = @("jarvis", "gpt-5.6-terra")
}
foreach ($launcher in $launchers.Keys) {
    $content = Get-Content (Join-Path $PSScriptRoot $launcher) -Raw
    Assert-True ($content -match [regex]::Escape($launchers[$launcher][0])) "$launcher does not select its profile."
    Assert-True ($content -match [regex]::Escape($launchers[$launcher][1])) "$launcher does not select its model."
    Assert-True ($content -match 'model_reasoning_effort') "$launcher does not select reasoning effort."
}
foreach ($launcher in @("start-ultron.sh", "start-jarvis.sh")) {
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
    Assert-True ($userFiles.Count -eq 9) "User install must create nine files; found $($userFiles.Count)."

    $conflictRejected = $false
    try { & (Join-Path $PSScriptRoot "install.ps1") -HomePath $tempHome } catch { $conflictRejected = $_.Exception.Message -match "Refusing partial install" }
    Assert-True $conflictRejected "User installer must reject conflicts before writing."

    & (Join-Path $PSScriptRoot "install.ps1") -Scope Project -ProjectPath $tempProject
    $projectFiles = @(Get-ChildItem $tempProject -File -Force -Recurse)
    Assert-True ($projectFiles.Count -eq 8) "Project install must create eight files; found $($projectFiles.Count)."

    Assert-True ($null -ne (Get-Command codex -ErrorAction SilentlyContinue)) "Codex CLI is required for profile validation."
    & codex --profile ultron mcp list | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) "Codex failed to load the Ultron profile."
    & codex --profile jarvis mcp list | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) "Codex failed to load the Jarvis profile."
    $desktopInstructions = Get-Content (Join-Path $packageRoot "instructions\ultron.md") -Raw | ConvertTo-Json -Compress
    & codex --config 'model="gpt-5.6-sol"' --config 'model_reasoning_effort="high"' --config "developer_instructions=$desktopInstructions" mcp list | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) "Codex failed to load desktop-style Ultron configuration."
} finally {
    $env:CODEX_HOME = $oldCodexHome
    if (Test-Path $tempRoot) { Remove-Item $tempRoot -Recurse -Force }
}

Write-Output "Codex Ultron package checks passed."