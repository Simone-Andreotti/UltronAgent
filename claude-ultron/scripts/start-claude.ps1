[CmdletBinding(PositionalBinding = $false)]
param(
    [ValidateSet("edith", "jarvis", "ultron")]
    [string]$Agent,
    [string]$Prompt,
    [string]$WorkingDirectory = (Get-Location).Path
)

$ErrorActionPreference = "Stop"

$leadDefinitions = @{
    edith = @{ Model = "claude-haiku-5-5"; Effort = "max"; Greeting = "Edith at your service." }
    jarvis = @{ Model = "claude-sonnet-5-5"; Effort = "xhigh"; Greeting = "Jarvis at your service." }
    ultron = @{ Model = "claude-opus-5-5"; Effort = "xhigh"; Greeting = "Lowly human, let Ultron manage the rest." }
}

if (-not $Agent) {
    Write-Host "Choose a Claude lead:"
    Write-Host "  1. Edith - simpler implementation and maintenance (Haiku 5.5)"
    Write-Host "  2. Jarvis - medium-complexity implementation and integration (Sonnet 5.5)"
    Write-Host "  3. Ultron - complex and architectural work (Opus 5.5)"
    $choice = Read-Host "Lead"
    $Agent = switch ($choice) {
        "1" { "edith"; break }
        "2" { "jarvis"; break }
        "3" { "ultron"; break }
        default { throw "Choose 1, 2, or 3." }
    }
}

$Agent = $Agent.ToLowerInvariant()
$selectedLead = $leadDefinitions[$Agent]
$permissionMode = if ($env:CLAUDE_ULTRON_PERMISSION_MODE) { $env:CLAUDE_ULTRON_PERMISSION_MODE } else { "auto" }
$arguments = @(
    "--agent", "leads:$Agent",
    "--model", $selectedLead.Model,
    "--effort", $selectedLead.Effort,
    "--permission-mode", $permissionMode
)
if ($Prompt) {
    # Before 7.3 PowerShell hands quotes to native programs unescaped, and adds its own
    # only around whitespace outside them, which a leading space forces.
    if ($PSVersionTable.PSVersion -lt [version]"7.3") {
        $Prompt = ' ' + (($Prompt -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1')
    }
    $arguments += "--", $Prompt
}

Write-Host $selectedLead.Greeting
Push-Location -LiteralPath $WorkingDirectory
try {
    & claude @arguments
    $exitCode = $LASTEXITCODE
} finally {
    Pop-Location
}
exit $exitCode
