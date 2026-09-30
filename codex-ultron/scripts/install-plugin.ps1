[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$CodexCommand = "codex",
    [string]$HomePath = $HOME
)

$ErrorActionPreference = "Stop"
$packageRoot = Split-Path -Parent $PSScriptRoot
$roles = @("ultron", "jarvis", "edith")
$pluginIds = @($roles | ForEach-Object { "$_@ultron-codex" })
if (-not (Get-Command $CodexCommand -ErrorAction SilentlyContinue)) {
    throw "Codex CLI was not found. Install it before installing the plugin."
}

if (-not $PSCmdlet.ShouldProcess(($pluginIds -join ", "), "Build and install role plugins")) {
    return
}

$buildRoot = Join-Path $packageRoot ".plugin-build"
$templateRoot = Join-Path $packageRoot "plugins"
$skillsRoot = Join-Path $packageRoot "skills"
foreach ($role in $roles) {
    $pluginRoot = Join-Path $buildRoot $role
    $skillRoot = Join-Path $pluginRoot "skills\$role"
    $referencesRoot = Join-Path $skillRoot "references"
    $agentsRoot = Join-Path $skillRoot "agents"
    New-Item -ItemType Directory -Force -Path $referencesRoot, $agentsRoot | Out-Null

    Copy-Item -LiteralPath (Join-Path $templateRoot "$role\plugin.json") -Destination $pluginRoot -Force
    Copy-Item -LiteralPath (Join-Path $skillsRoot "$role\SKILL.md") -Destination $skillRoot -Force
    Copy-Item -LiteralPath (Join-Path $skillsRoot "$role\agents\openai.yaml") -Destination $agentsRoot -Force
    Copy-Item -LiteralPath (Join-Path $packageRoot "instructions\$role.md") -Destination (Join-Path $referencesRoot "lead.md") -Force
    Copy-Item -LiteralPath (Join-Path $skillsRoot "codex-ultron\SKILL.md") -Destination (Join-Path $referencesRoot "workflow.md") -Force
    Copy-Item -LiteralPath (Join-Path $skillsRoot "codex-ultron\references\chat-activation.md") -Destination (Join-Path $referencesRoot "chat-activation.md") -Force
}

& (Join-Path $PSScriptRoot "install.ps1") -Scope User -HomePath $HomePath -SkipSkill

& $CodexCommand plugin marketplace add $packageRoot --json
if ($LASTEXITCODE -ne 0) { throw "Unable to register the Ultron Codex marketplace." }
foreach ($pluginId in $pluginIds) {
    & $CodexCommand plugin add $pluginId --json
    if ($LASTEXITCODE -ne 0) { throw "Unable to install $pluginId. The existing standalone skill and combined plugin were preserved." }
}

$pluginListJson = & $CodexCommand plugin list --json | Out-String
if ($LASTEXITCODE -ne 0) { throw "Unable to list installed Codex plugins; the combined plugin and standalone skill were preserved." }
try {
    $pluginList = ConvertFrom-Json -InputObject $pluginListJson -ErrorAction Stop
} catch {
    throw "Codex returned invalid plugin-list JSON; the combined plugin and standalone skill were preserved. $($_.Exception.Message)"
}
if ($null -eq $pluginList -or $null -eq $pluginList.PSObject.Properties["installed"]) {
    throw "Codex plugin-list JSON did not contain installed plugins; the combined plugin and standalone skill were preserved."
}

$legacyPluginId = "codex-ultron@ultron-codex"
$legacyInstalled = @($pluginList.installed | Where-Object { $_.pluginId -ceq $legacyPluginId }).Count -gt 0
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HomePath ".codex" }
$legacyCachePath = Join-Path $codexHome "plugins\cache\ultron-codex\codex-ultron"
if ($legacyInstalled -or (Test-Path -LiteralPath $legacyCachePath)) {
    & $CodexCommand plugin remove $legacyPluginId --json
    if ($LASTEXITCODE -ne 0) { throw "Unable to remove the obsolete $legacyPluginId plugin." }
}

$standaloneSkillRoot = [System.IO.Path]::GetFullPath((Join-Path $HomePath ".agents\skills\codex-ultron"))
$standaloneSkillPath = Join-Path $standaloneSkillRoot "SKILL.md"
if ((Test-Path -LiteralPath $standaloneSkillPath) -and ((Get-Content -LiteralPath $standaloneSkillPath -Raw) -match '(?m)^name:\s*codex-ultron\s*$')) {
    # Remove only the two package-owned files; preserve unrelated additions.
    foreach ($relativePath in @("SKILL.md", "agents\openai.yaml")) {
        $target = Join-Path $standaloneSkillRoot $relativePath
        if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Force }
    }
}

Write-Output "Installed role plugins: $($pluginIds -join ', '). Restart Codex to load them in new chats."
