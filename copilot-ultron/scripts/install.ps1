[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet("User", "Project")]
    [string]$Scope = "User",
    [string]$ProjectPath = (Get-Location).Path,
    [string]$HomePath = $HOME,
    [string]$VsCodeUserPath = (Join-Path $env:APPDATA "Code\User"),
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$packageRoot = Split-Path -Parent $PSScriptRoot
$sourceAgents = Join-Path $packageRoot "agents"
$sourcePrompts = Join-Path $packageRoot "prompts"

if ($Scope -eq "User") {
    $skillRoot = Join-Path $HomePath ".copilot\skills\ultron-orchestrator"
    $agentRoots = @(
        (Join-Path $HomePath ".copilot\agents"),
        (Join-Path $VsCodeUserPath "prompts")
    )
    $promptRoots = @((Join-Path $VsCodeUserPath "prompts"))
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
        if ((Test-Path $managedPath) -and $PSCmdlet.ShouldProcess($managedPath, "Remove stale Copilot customization")) {
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
    if ($PSCmdlet.ShouldProcess($markerPath, "Record managed Copilot customizations")) {
        $markerContent = (($Names | Sort-Object -Unique) -join "`n") + "`n"
        [System.IO.File]::WriteAllText($markerPath, $markerContent, (New-Object System.Text.UTF8Encoding($false)))
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

$agentMarkerName = ".ultron-orchestrator-agents"
$promptMarkerName = ".ultron-orchestrator-prompts"
$skillFile = Join-Path $skillRoot "SKILL.md"
$skillIdentifiesPackage = (Test-Path $skillFile) -and ((Get-Content $skillFile -Raw) -match '(?m)^name:\s*ultron-orchestrator\s*$')
$managedDestinations = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
if ($skillIdentifiesPackage) {
    [void]$managedDestinations.Add([System.IO.Path]::GetFullPath($skillFile))
}

$legacyAgentNames = @(
    "edith.agent.md",
    "jarvis.agent.md",
    "luna-code-analyst.agent.md",
    "luna-researcher.agent.md",
    "luna-worker.agent.md",
    "ultron.agent.md"
)
$legacyPromptNames = @("explain.prompt.md")

foreach ($agentRoot in $agentRoots) {
    $markerPath = Join-Path $agentRoot $agentMarkerName
    if (Test-Path $markerPath) {
        foreach ($managedName in Get-Content $markerPath) {
            if (-not $managedName -or $managedName -in @(".", "..") -or [System.IO.Path]::GetFileName($managedName) -ne $managedName) {
                throw "Unsafe managed file entry '$managedName' in $markerPath."
            }
            [void]$managedDestinations.Add([System.IO.Path]::GetFullPath((Join-Path $agentRoot $managedName)))
        }
    } elseif ($skillIdentifiesPackage) {
        foreach ($legacyName in $legacyAgentNames) {
            [void]$managedDestinations.Add([System.IO.Path]::GetFullPath((Join-Path $agentRoot $legacyName)))
        }
    }
}

foreach ($promptRoot in $promptRoots) {
    $markerPath = Join-Path $promptRoot $promptMarkerName
    if (Test-Path $markerPath) {
        foreach ($managedName in Get-Content $markerPath) {
            if (-not $managedName -or $managedName -in @(".", "..") -or [System.IO.Path]::GetFileName($managedName) -ne $managedName) {
                throw "Unsafe managed file entry '$managedName' in $markerPath."
            }
            [void]$managedDestinations.Add([System.IO.Path]::GetFullPath((Join-Path $promptRoot $managedName)))
        }
    } elseif ($skillIdentifiesPackage) {
        foreach ($legacyName in $legacyPromptNames) {
            [void]$managedDestinations.Add([System.IO.Path]::GetFullPath((Join-Path $promptRoot $legacyName)))
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

if (($skillIdentifiesPackage -or $Force) -and (Test-Path $skillRoot) -and $PSCmdlet.ShouldProcess($skillRoot, "Remove previous Copilot skill version")) {
    Remove-Item $skillRoot -Recurse -Force
}
foreach ($agentRoot in $agentRoots) {
    Remove-ManagedFiles -Root $agentRoot -MarkerName $agentMarkerName
}
foreach ($promptRoot in $promptRoots) {
    Remove-ManagedFiles -Root $promptRoot -MarkerName $promptMarkerName
}

foreach ($installFile in $installFiles) {
    Copy-PackageFile -Source $installFile.Source -Destination $installFile.Destination
}

foreach ($agentRoot in $agentRoots) {
    Write-ManagedFiles -Root $agentRoot -MarkerName $agentMarkerName -Names $sourceAgentFiles.Name
}
foreach ($promptRoot in $promptRoots) {
    Write-ManagedFiles -Root $promptRoot -MarkerName $promptMarkerName -Names $sourcePromptFiles.Name
}

if ($WhatIfPreference) {
    Write-Host "Validated Copilot Ultron package installation for scope '$Scope'."
} else {
    Write-Host "Installed Copilot Ultron package for scope '$Scope'."
}