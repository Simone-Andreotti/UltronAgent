[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$Prompt,
    [string]$WorkingDirectory = (Get-Location).Path,
    [int]$MaxAiCredits = 0,
    [switch]$AllowAll = ($env:COPILOT_ALLOW_ALL -eq "true"),
    [switch]$Sandbox = ($env:COPILOT_SANDBOX -ne "false")
)

$ErrorActionPreference = "Stop"
if ($args.Count -gt 0) {
    throw "Unsupported launcher arguments: $($args -join ' '). Model, reasoning effort, and context are fixed."
}

if ($MaxAiCredits -gt 0 -and $MaxAiCredits -lt 30) {
    throw "MaxAiCredits must be 0 (disabled) or at least 30."
}

$packageRoot = Split-Path -Parent $PSScriptRoot
$arguments = @(
    "--plugin-dir", $packageRoot,
    "--agent", "ultron-orchestrator:edith",
    "--model", "gpt-5.6-luna",
    "--reasoning-effort", "low",
    "--context", "default",
    "-C", $WorkingDirectory
)

if ($MaxAiCredits -gt 0) {
    $arguments += @("--max-ai-credits", $MaxAiCredits)
}

if ($AllowAll) {
    $arguments += @("--allow-all", "--no-sandbox")
} else {
    $arguments += @("--allow-all-tools", "--allow-all-urls", "--disallow-temp-dir")
    if ($Sandbox) { $arguments += "--sandbox" }
}

if ($Prompt) {
    $arguments += @("-i", $Prompt)
}

& copilot @arguments
exit $LASTEXITCODE
