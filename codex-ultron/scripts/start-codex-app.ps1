[CmdletBinding(PositionalBinding = $false)]
param(
    [ValidateSet("edith", "jarvis", "ultron")]
    [string]$Agent,
    [string]$WorkingDirectory = (Get-Location).Path
)

$ErrorActionPreference = "Stop"
if ($args.Count -gt 0) {
    throw "Unsupported launcher arguments: $($args -join ' '). Use -Agent or -WorkingDirectory."
}

$leadDefinitions = @{
    edith = @{ Model = "gpt-6-luna"; Effort = "max"; Instructions = "edith.md"; Label = "Edith" }
    jarvis = @{ Model = "gpt-6.1-sol"; Effort = "high"; Instructions = "jarvis.md"; Label = "Jarvis" }
    ultron = @{ Model = "gpt-6.1-sol"; Effort = "high"; Instructions = "ultron.md"; Label = "Ultron" }
}

if (-not $Agent) {
    Write-Host "Choose a Codex lead for the desktop app:"
    Write-Host "  1. Edith - simpler implementation and maintenance"
    Write-Host "  2. Jarvis - medium-complexity implementation and integration"
    Write-Host "  3. Ultron - complex and architectural work"
    $choice = Read-Host "Lead"
    $Agent = switch ($choice) {
        "1" { "edith"; break }
        "2" { "jarvis"; break }
        "3" { "ultron"; break }
        default { throw "Choose 1, 2, or 3." }
    }
}

$selectedLead = $leadDefinitions[$Agent]
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME ".codex" }
$requiredAgents = @("luna_code_analyst.toml", "luna_researcher.toml", "luna_worker.toml")
if ($Agent -in @("jarvis", "ultron")) { $requiredAgents += "sol_worker.toml" }
if ($Agent -eq "ultron") { $requiredAgents += "astra_specialist.toml" }
foreach ($requiredAgent in $requiredAgents) {
    if (-not (Test-Path (Join-Path $codexHome "agents\$requiredAgent"))) {
        throw "Codex Ultron agent '$requiredAgent' is not installed. Run install.ps1 first."
    }
}

$packageRoot = Split-Path -Parent $PSScriptRoot
$instructions = Get-Content (Join-Path $packageRoot "instructions\$($selectedLead.Instructions)") -Raw
$encodedInstructions = $instructions | ConvertTo-Json -Compress
$sandboxMode = if ($env:CODEX_ULTRON_FULL_ACCESS -eq "false") { "workspace-write" } else { "danger-full-access" }
$arguments = @(
    "app",
    "--config", ('model="' + $selectedLead.Model + '"'),
    "--config", ('model_reasoning_effort="' + $selectedLead.Effort + '"'),
    "--config", 'model_verbosity="low"',
    "--config", 'approval_policy="never"',
    "--config", ('sandbox_mode="' + $sandboxMode + '"'),
    "--config", 'sandbox_workspace_write.network_access=true',
    "--config", 'web_search="live"',
    "--config", 'plugins."browser@openai-bundled".enabled=true',
    "--config", 'agents.enabled=true',
    "--config", 'agents.max_concurrent_threads_per_session=6',
    "--config", 'agents.default_subagent_model="gpt-6-luna"',
    "--config", 'agents.default_subagent_reasoning_effort="max"',
    "--config", "developer_instructions=$encodedInstructions",
    $WorkingDirectory
)

& codex @arguments
exit $LASTEXITCODE
