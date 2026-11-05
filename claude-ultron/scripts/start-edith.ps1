[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$Prompt,
    [string]$WorkingDirectory = (Get-Location).Path
)

$ErrorActionPreference = "Stop"
if ($args.Count -gt 0) {
    throw "Unsupported launcher arguments: $($args -join ' '). Model and effort are fixed."
}

& (Join-Path $PSScriptRoot "start-claude.ps1") -Agent edith -Prompt $Prompt -WorkingDirectory $WorkingDirectory
exit $LASTEXITCODE
