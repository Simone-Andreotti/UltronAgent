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
        Copy-Item -Path $Source -Destination $Destination -Force
    }
}

function Remove-ManagedFiles {
    param(
        [Parameter(Mandatory)]
        [string]$Root,
        [Parameter(Mandatory)]
        [string]$MarkerName
    )

    $markerPath = Join-Path $Root $MarkerName
    if (-not (Test-Path $markerPath)) {
        return
    }

    foreach ($managedName in Get-Content $markerPath) {
        if (-not $managedName -or $managedName -in @(".", "..") -or [System.IO.Path]::GetFileName($managedName) -ne $managedName) {
            throw "Unsafe managed file entry '$managedName' in $markerPath."
        }
        $managedPath = Join-Path $Root $managedName
        if ((Test-Path $managedPath) -and $PSCmdlet.ShouldProcess($managedPath, "Remove stale Codex Ultron customization")) {
            Remove-Item $managedPath -Force
        }
    }
}

function Write-ManagedFiles {
    param(
        [Parameter(Mandatory)]
        [string]$Root,
        [Parameter(Mandatory)]
        [string]$MarkerName,
        [Parameter(Mandatory)]
        [string[]]$Names
    )

    $markerPath = Join-Path $Root $MarkerName
    if ($PSCmdlet.ShouldProcess($markerPath, "Record managed Codex Ultron customizations")) {
        New-Item -ItemType Directory -Path $Root -Force | Out-Null
        $markerContent = (($Names | Sort-Object -Unique) -join "`n") + "`n"
        [System.IO.File]::WriteAllText($markerPath, $markerContent, (New-Object System.Text.UTF8Encoding($false)))
    }
}

$sourceAgentFiles = @(Get-ChildItem -Path $sourceAgents -Filter "*.toml")
$sourceProfileFiles = @(Get-ChildItem -Path $sourceProfiles -Filter "*.config.toml")
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

foreach ($sourceAgent in $sourceAgentFiles) {
    $installFiles += [pscustomobject]@{
        Source = $sourceAgent.FullName
        Destination = Join-Path $agentRoot $sourceAgent.Name
    }
}

if ($Scope -eq "User") {
    foreach ($sourceProfile in $sourceProfileFiles) {
        $installFiles += [pscustomobject]@{
            Source = $sourceProfile.FullName
            Destination = Join-Path $codexHome $sourceProfile.Name
        }
    }
} else {
    $configRoot = Join-Path $resolvedProject ".codex"
    $installFiles += [pscustomobject]@{
        Source = Join-Path $packageRoot "config\codex-config.example.toml"
        Destination = Join-Path $configRoot "codex-ultron.example.toml"
    }
}

$agentMarkerName = ".codex-ultron-agents"
$profileMarkerName = ".codex-ultron-profiles"
$configMarkerName = ".codex-ultron-config"
$skillFile = Join-Path $skillRoot "SKILL.md"
$skillIdentifiesPackage = (Test-Path $skillFile) -and ((Get-Content $skillFile -Raw) -match '(?m)^name:\s*codex-ultron\s*$')
$managedDestinations = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
if ($skillIdentifiesPackage) {
    $fullSkillRoot = [System.IO.Path]::GetFullPath($skillRoot)
    foreach ($skillDestination in $installFiles.Destination) {
        $fullSkillDestination = [System.IO.Path]::GetFullPath($skillDestination)
        if ($fullSkillDestination.StartsWith($fullSkillRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            [void]$managedDestinations.Add($fullSkillDestination)
        }
    }
}

$managedRoots = @(
    [pscustomobject]@{
        Root = $agentRoot
        Marker = $agentMarkerName
        LegacyNames = @("edith.toml", "jarvis.toml", "luna_code_analyst.toml", "luna_researcher.toml", "luna_worker.toml", "ultron.toml")
    }
)
if ($Scope -eq "User") {
    $managedRoots += [pscustomobject]@{
        Root = $codexHome
        Marker = $profileMarkerName
        LegacyNames = @("edith.config.toml", "jarvis.config.toml", "ultron.config.toml")
    }
} else {
    $managedRoots += [pscustomobject]@{
        Root = $configRoot
        Marker = $configMarkerName
        LegacyNames = @()
    }
}

foreach ($managedRoot in $managedRoots) {
    $markerPath = Join-Path $managedRoot.Root $managedRoot.Marker
    if (Test-Path $markerPath) {
        foreach ($managedName in Get-Content $markerPath) {
            if (-not $managedName -or $managedName -in @(".", "..") -or [System.IO.Path]::GetFileName($managedName) -ne $managedName) {
                throw "Unsafe managed file entry '$managedName' in $markerPath."
            }
            [void]$managedDestinations.Add([System.IO.Path]::GetFullPath((Join-Path $managedRoot.Root $managedName)))
        }
    } elseif ($skillIdentifiesPackage) {
        foreach ($legacyName in $managedRoot.LegacyNames) {
            [void]$managedDestinations.Add([System.IO.Path]::GetFullPath((Join-Path $managedRoot.Root $legacyName)))
        }
    }
}

$conflicts = @($installFiles | Where-Object {
    (Test-Path $_.Destination) -and -not $managedDestinations.Contains([System.IO.Path]::GetFullPath($_.Destination))
})
if ($conflicts -and -not $Force) {
    $conflictList = ($conflicts.Destination | ForEach-Object { "  $_" }) -join [Environment]::NewLine
    throw "Refusing partial install because these files exist:$([Environment]::NewLine)$conflictList$([Environment]::NewLine)Re-run with -Force to replace them."
}

if (($skillIdentifiesPackage -or $Force) -and (Test-Path $skillRoot) -and $PSCmdlet.ShouldProcess($skillRoot, "Remove previous Codex Ultron skill version")) {
    Remove-Item $skillRoot -Recurse -Force
}
foreach ($managedRoot in $managedRoots) {
    Remove-ManagedFiles -Root $managedRoot.Root -MarkerName $managedRoot.Marker
}

foreach ($installFile in $installFiles) {
    Copy-PackageFile -Source $installFile.Source -Destination $installFile.Destination
}

Write-ManagedFiles -Root $agentRoot -MarkerName $agentMarkerName -Names $sourceAgentFiles.Name
if ($Scope -eq "User") {
    Write-ManagedFiles -Root $codexHome -MarkerName $profileMarkerName -Names $sourceProfileFiles.Name
} else {
    Write-ManagedFiles -Root $configRoot -MarkerName $configMarkerName -Names @("codex-ultron.example.toml")
}

if ($WhatIfPreference) {
    Write-Host "Validated Codex Ultron package installation for scope '$Scope'."
} else {
    Write-Host "Installed Codex Ultron package for scope '$Scope'."
}