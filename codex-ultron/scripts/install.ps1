[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet("User", "Project")]
    [string]$Scope = "User",
    [string]$ProjectPath = (Get-Location).Path,
    [string]$HomePath = $HOME,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$packageRoot = Split-Path -Parent $PSScriptRoot
$sourceAgents = Join-Path $packageRoot "agents"
$sourceProfiles = Join-Path $packageRoot "profiles"

if ($Scope -eq "User") {
    $codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HomePath ".codex" }
    $agentRoot = Join-Path $codexHome "agents"
    $skillRoot = Join-Path $HomePath ".agents\skills\codex-ultron"
} else {
    $resolvedProject = (Resolve-Path $ProjectPath).Path
    $agentRoot = Join-Path $resolvedProject ".codex\agents"
    $skillRoot = Join-Path $resolvedProject ".agents\skills\codex-ultron"
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
    if ($PSCmdlet.ShouldProcess($Destination, "Install Codex Ultron customization")) {
        Copy-Item -Path $Source -Destination $Destination -Force:$Force
    }
}

$installFiles = @(
    [pscustomobject]@{
        Source = Join-Path $packageRoot "skills\codex-ultron\SKILL.md"
        Destination = Join-Path $skillRoot "SKILL.md"
    },
    [pscustomobject]@{
        Source = Join-Path $packageRoot "skills\codex-ultron\agents\openai.yaml"
        Destination = Join-Path $skillRoot "agents\openai.yaml"
    }
)

foreach ($sourceAgent in Get-ChildItem -Path $sourceAgents -Filter "*.toml") {
    $installFiles += [pscustomobject]@{
        Source = $sourceAgent.FullName
        Destination = Join-Path $agentRoot $sourceAgent.Name
    }
}

if ($Scope -eq "User") {
    foreach ($sourceProfile in Get-ChildItem -Path $sourceProfiles -Filter "*.config.toml") {
        $installFiles += [pscustomobject]@{
            Source = $sourceProfile.FullName
            Destination = Join-Path $codexHome $sourceProfile.Name
        }
    }
} else {
    $installFiles += [pscustomobject]@{
        Source = Join-Path $packageRoot "config\codex-config.example.toml"
        Destination = Join-Path $resolvedProject ".codex\config.toml"
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
    Write-Host "Validated Codex Ultron package installation for scope '$Scope'."
} else {
    Write-Host "Installed Codex Ultron package for scope '$Scope'."
}