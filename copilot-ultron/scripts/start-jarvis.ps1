[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$Prompt,
    [string]$WorkingDirectory = (Get-Location).Path,
    [int]$MaxAiCredits = 0,
    [switch]$AllowAll = ($env:COPILOT_ALLOW_ALL -ne "false")
)

$ErrorActionPreference = "Stop"
if ($args.Count -gt 0) {
    throw "Unsupported launcher arguments: $($args -join ' '). Model and reasoning effort are fixed."
}

if ($MaxAiCredits -gt 0 -and $MaxAiCredits -lt 30) {
    throw "MaxAiCredits must be 0 (disabled) or at least 30."
}

$packageRoot = Split-Path -Parent $PSScriptRoot
$arguments = @(
    "--plugin-dir", $packageRoot,
    "--agent", "ultron-orchestrator:jarvis",
    "--model", "gpt-5.6-sol",
    "--reasoning-effort", "high",
    "-C", $WorkingDirectory
)

if ($MaxAiCredits -gt 0) {
    $arguments += @("--max-ai-credits", $MaxAiCredits)
}

if ($AllowAll) {
    $arguments += "--allow-all"
} else {
    $arguments += @("--allow-all-tools", "--allow-all-urls", "--disallow-temp-dir")
}

if ($Prompt) {
    $arguments += @("-i", $Prompt)
}

& copilot @arguments
exit $LASTEXITCODE
