[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$Prompt,
    [string]$WorkingDirectory = (Get-Location).Path,
    [switch]$Search = ($env:CODEX_ULTRON_LIVE_SEARCH -ne "false"),
    [switch]$FullAccess = ($env:CODEX_ULTRON_FULL_ACCESS -ne "false")
)

$ErrorActionPreference = "Stop"
if ($args.Count -gt 0) {
    throw "Unsupported launcher arguments: $($args -join ' '). Profile, model, and reasoning effort are fixed."
}

$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME ".codex" }
if (-not (Test-Path (Join-Path $codexHome "jarvis.config.toml"))) {
    throw "Jarvis profile is not installed. Run install.ps1 first."
}

$arguments = @(
    "--profile", "jarvis",
    "--model", "gpt-5.6-sol",
    "--config", 'model_reasoning_effort="high"',
    "--cd", $WorkingDirectory
)
if ($Search) { $arguments += "--search" }
if ($FullAccess) {
    $arguments += "--dangerously-bypass-approvals-and-sandbox"
} else {
    $arguments += "--config", 'sandbox_mode="workspace-write"', "--config", 'sandbox_workspace_write.network_access=true'
}
if ($Prompt) { $arguments += $Prompt }

Write-Output "Jarvis at your service."
& codex @arguments
exit $LASTEXITCODE
