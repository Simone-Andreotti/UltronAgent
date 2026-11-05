[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet("User", "Project", "Local")]
    [string]$Scope = "User",
    [string]$ProjectPath = (Get-Location).Path,
    [string]$ClaudeCommand = "claude"
)

$ErrorActionPreference = "Stop"
$packageRoot = Split-Path -Parent $PSScriptRoot
$pluginId = "leads@ultron-claude"
if (-not (Get-Command $ClaudeCommand -ErrorAction SilentlyContinue)) {
    throw "Claude Code CLI was not found. Install it before installing the plugin."
}
if (-not $PSCmdlet.ShouldProcess($pluginId, "Register the marketplace and install at $Scope scope")) {
    return
}

# The marketplace is a local folder, so sessions read the plugin from this checkout.
# Adding it again is harmless and points it here after the checkout moves.
& $ClaudeCommand plugin marketplace add $packageRoot
if ($LASTEXITCODE -ne 0) { throw "Unable to register the ultron-claude marketplace." }

Push-Location -LiteralPath $ProjectPath
try {
    & $ClaudeCommand plugin install $pluginId --scope $Scope.ToLowerInvariant()
    if ($LASTEXITCODE -ne 0) { throw "Unable to install $pluginId." }
} finally {
    Pop-Location
}

Write-Output "Installed $pluginId at $Scope scope. Run /reload-plugins or start a new session to load it."
