[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$CopilotCommand = "copilot"
)

$ErrorActionPreference = "Stop"
$packageRoot = Split-Path -Parent $PSScriptRoot
$pluginName = "ultron-orchestrator"
$marketplaceName = "ultron-agent"

if (-not (Get-Command $CopilotCommand -ErrorAction SilentlyContinue)) {
    throw "Copilot CLI was not found. Install it before installing the plugin."
}

$global:LASTEXITCODE = 0
$installedPlugins = & $CopilotCommand plugin list 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "Unable to list installed Copilot plugins.`n$($installedPlugins -join [Environment]::NewLine)"
}

$installedPluginText = (($installedPlugins -join "`n") -replace "`e\[[0-9;]*[A-Za-z]", "")
if ($installedPluginText -match "(?m)^\s*(?:\S+\s+)?ultron-orchestrator(?:@[A-Za-z0-9._-]+)?(?:\s|\(|$)") {
    if ($PSCmdlet.ShouldProcess($pluginName, "Uninstall previous Copilot plugin snapshot")) {
        $global:LASTEXITCODE = 0
        & $CopilotCommand plugin uninstall $pluginName
        if ($LASTEXITCODE -ne 0) {
            throw "Unable to uninstall the previous $pluginName plugin."
        }
    }
}

$global:LASTEXITCODE = 0
$registeredMarketplaces = & $CopilotCommand plugin marketplace list 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "Unable to list Copilot plugin marketplaces.`n$($registeredMarketplaces -join [Environment]::NewLine)"
}

$registeredMarketplaceText = (($registeredMarketplaces -join "`n") -replace "`e\[[0-9;]*[A-Za-z]", "")
if ($registeredMarketplaceText -match "(?m)^\s*(?:\S+\s+)?ultron-agent(?:\s|\(|$)") {
    if ($PSCmdlet.ShouldProcess($marketplaceName, "Remove previous Copilot marketplace registration")) {
        $global:LASTEXITCODE = 0
        & $CopilotCommand plugin marketplace remove $marketplaceName
        if ($LASTEXITCODE -ne 0) {
            throw "Unable to remove the previous $marketplaceName marketplace registration."
        }
    }
}

if ($PSCmdlet.ShouldProcess($packageRoot, "Register current Copilot plugin marketplace")) {
    $global:LASTEXITCODE = 0
    & $CopilotCommand plugin marketplace add $packageRoot
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to register the current $marketplaceName marketplace."
    }
}

$pluginSpecification = "$pluginName@$marketplaceName"
if ($PSCmdlet.ShouldProcess($pluginSpecification, "Install current Copilot marketplace plugin")) {
    $global:LASTEXITCODE = 0
    & $CopilotCommand plugin install $pluginSpecification
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to install the current $pluginName plugin."
    }
}

if ($WhatIfPreference) {
    Write-Host "Validated marketplace replacement of the $pluginName Copilot plugin."
} else {
    Write-Host "Installed the current $pluginSpecification Copilot plugin."
}