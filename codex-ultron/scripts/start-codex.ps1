[CmdletBinding(PositionalBinding = $false)]
param(
    [ValidateSet("edith", "jarvis", "ultron")]
    [string]$Agent,
    [string]$Prompt,
    [string]$WorkingDirectory = (Get-Location).Path,
    [switch]$Search,
    [switch]$FullAccess
)

$ErrorActionPreference = "Stop"
if ($args.Count -gt 0) {
    throw "Unsupported launcher arguments: $($args -join ' '). Use -Agent, -Prompt, -WorkingDirectory, -Search, or -FullAccess."
}

$leadDefinitions = @{
    edith = @{ Profile = "edith"; Model = "gpt-5.6-luna"; Label = "Edith" }
    jarvis = @{ Profile = "jarvis"; Model = "gpt-5.6-terra"; Label = "Jarvis" }
    ultron = @{ Profile = "ultron"; Model = "gpt-5.6-sol"; Label = "Ultron" }
}

if (-not $Agent) {
    Write-Host "Choose a Codex lead:"
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
$profilePath = Join-Path $codexHome "$($selectedLead.Profile).config.toml"
if (-not (Test-Path $profilePath)) {
    throw "$($selectedLead.Label) profile is not installed. Run install.ps1 first."
}

$arguments = @(
    "--profile", $selectedLead.Profile,
    "--model", $selectedLead.Model,
    "--config", 'model_reasoning_effort="high"',
    "--cd", $WorkingDirectory
)
if ($Search) { $arguments += "--search" }
if ($FullAccess) { $arguments += "--dangerously-bypass-approvals-and-sandbox" }
if ($Prompt) { $arguments += $Prompt }

& codex @arguments
exit $LASTEXITCODE