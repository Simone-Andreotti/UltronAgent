[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$WorkingDirectory = (Get-Location).Path
)

$ErrorActionPreference = "Stop"
if ($args.Count -gt 0) { throw "Unsupported launcher arguments. Jarvis routing is fixed." }

$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME ".codex" }
foreach ($lunaAgent in @("luna_code_analyst.toml", "luna_researcher.toml", "luna_worker.toml")) {
    if (-not (Test-Path (Join-Path $codexHome "agents\$lunaAgent"))) {
        throw "Codex Ultron agent '$lunaAgent' is not installed. Run install.ps1 first."
    }
}

$packageRoot = Split-Path -Parent $PSScriptRoot
$instructions = Get-Content (Join-Path $packageRoot "instructions\jarvis.md") -Raw
$encodedInstructions = $instructions | ConvertTo-Json -Compress
$sandboxMode = if ($env:CODEX_ULTRON_FULL_ACCESS -eq "false") { "workspace-write" } else { "danger-full-access" }
& codex app --config 'model="gpt-5.6-sol"' --config 'model_reasoning_effort="high"' --config 'model_verbosity="low"' --config 'approval_policy="never"' --config ('sandbox_mode="' + $sandboxMode + '"') --config 'sandbox_workspace_write.network_access=true' --config 'web_search="live"' --config 'plugins."browser@openai-bundled".enabled=true' --config 'agents.enabled=true' --config 'agents.max_concurrent_threads_per_session=6' --config 'agents.default_subagent_model="gpt-5.6-luna"' --config 'agents.default_subagent_reasoning_effort="xhigh"' --config "developer_instructions=$encodedInstructions" $WorkingDirectory
exit $LASTEXITCODE
