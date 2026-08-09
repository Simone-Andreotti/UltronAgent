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
    edith = @{ Model = "gpt-5.6-luna"; Instructions = "edith.md"; Label = "Edith" }
    jarvis = @{ Model = "gpt-5.6-terra"; Instructions = "jarvis.md"; Label = "Jarvis" }
    ultron = @{ Model = "gpt-5.6-sol"; Instructions = "ultron.md"; Label = "Ultron" }
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
if (-not (Test-Path (Join-Path $codexHome "agents\luna_worker.toml"))) {
    throw "Codex Ultron agents are not installed. Run install.ps1 first."
}

$packageRoot = Split-Path -Parent $PSScriptRoot
$instructions = Get-Content (Join-Path $packageRoot "instructions\$($selectedLead.Instructions)") -Raw
$encodedInstructions = $instructions | ConvertTo-Json -Compress
$arguments = @(
    "app",
    "--config", ('model="' + $selectedLead.Model + '"'),
    "--config", 'model_reasoning_effort="high"',
    "--config", 'model_verbosity="low"',
    "--config", "developer_instructions=$encodedInstructions",
    $WorkingDirectory
)

& codex @arguments
exit $LASTEXITCODE