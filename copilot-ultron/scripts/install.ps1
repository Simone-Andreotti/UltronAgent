[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet("User", "Project")]
    [string]$Scope = "User",
    [string]$ProjectPath = (Get-Location).Path,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$packageRoot = Split-Path -Parent $PSScriptRoot
$sourceAgents = Join-Path $packageRoot "agents"
$sourcePrompts = Join-Path $packageRoot "prompts"

if ($Scope -eq "User") {
    $skillRoot = Join-Path $HOME ".copilot\skills\ultron-orchestrator"
    $agentRoots = @(
        (Join-Path $HOME ".copilot\agents"),
        (Join-Path $env:APPDATA "Code\User\prompts")
    )
    $promptRoots = @((Join-Path $env:APPDATA "Code\User\prompts"))
} else {
    $resolvedProject = (Resolve-Path $ProjectPath).Path
    $skillRoot = Join-Path $resolvedProject ".github\skills\ultron-orchestrator"
    $agentRoots = @((Join-Path $resolvedProject ".github\agents"))
    $promptRoots = @((Join-Path $resolvedProject ".github\prompts"))
}

function Copy-PackageFile {
    param(
        [Parameter(Mandatory)]
        [string]$Source,
        [Parameter(Mandatory)]
        [string]$Destination
    )

    $destinationDirectory = Split-Path -Parent $Destination
    if ($PSCmdlet.ShouldProcess($destinationDirectory, "Create directory")) {
        New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
    }
    if ($PSCmdlet.ShouldProcess($Destination, "Install Copilot customization")) {
        Copy-Item -Path $Source -Destination $Destination -Force:$Force
    }
}

$sourceAgentFiles = @(Get-ChildItem -Path $sourceAgents -Filter "*.agent.md")
$sourcePromptFiles = @(Get-ChildItem -Path $sourcePrompts -Filter "*.prompt.md")
$installFiles = @(
    [pscustomobject]@{
        Source = Join-Path $packageRoot "skills\ultron-orchestrator\SKILL.md"
        Destination = Join-Path $skillRoot "SKILL.md"
    }
)

foreach ($agentRoot in $agentRoots) {
    foreach ($sourceAgent in $sourceAgentFiles) {
        $installFiles += [pscustomobject]@{
            Source = $sourceAgent.FullName
            Destination = Join-Path $agentRoot $sourceAgent.Name
        }
    }
}

foreach ($promptRoot in $promptRoots) {
    foreach ($sourcePrompt in $sourcePromptFiles) {
        $installFiles += [pscustomobject]@{
            Source = $sourcePrompt.FullName
            Destination = Join-Path $promptRoot $sourcePrompt.Name
        }
    }
}

$conflicts = @($installFiles | Where-Object { Test-Path $_.Destination })
if ($conflicts -and -not $Force) {
    $conflictList = ($conflicts.Destination | ForEach-Object { "  $_" }) -join [Environment]::NewLine
    throw "Refusing partial install because these files exist:$([Environment]::NewLine)$conflictList$([Environment]::NewLine)Re-run with -Force to replace them."
}

foreach ($installFile in $installFiles) {
    Copy-PackageFile -Source $installFile.Source -Destination $installFile.Destination
}

if ($WhatIfPreference) {
    Write-Host "Validated Copilot Ultron package installation for scope '$Scope'."
} else {
    Write-Host "Installed Copilot Ultron package for scope '$Scope'."
}