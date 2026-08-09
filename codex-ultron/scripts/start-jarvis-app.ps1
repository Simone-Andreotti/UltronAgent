[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$WorkingDirectory = (Get-Location).Path
)

$ErrorActionPreference = "Stop"
if ($args.Count -gt 0) { throw "Unsupported launcher arguments. Jarvis routing is fixed." }

$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME ".codex" }
if (-not (Test-Path (Join-Path $codexHome "agents\luna_worker.toml"))) {
    throw "Codex Ultron agents are not installed. Run install.ps1 first."
}

$packageRoot = Split-Path -Parent $PSScriptRoot
$instructions = Get-Content (Join-Path $packageRoot "instructions\jarvis.md") -Raw
$encodedInstructions = $instructions | ConvertTo-Json -Compress
& codex app --config 'model="gpt-5.6-terra"' --config 'model_reasoning_effort="high"' --config "developer_instructions=$encodedInstructions" $WorkingDirectory
exit $LASTEXITCODE