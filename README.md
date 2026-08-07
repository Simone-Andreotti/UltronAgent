# UltronAgent

UltronAgent is a portable multi-agent workflow for Codex and GitHub Copilot. It provides lead agents for different levels of work and bounded Luna agents for focused analysis, research, and implementation.

## Packages

- `codex-ultron/`: Codex CLI and desktop app agents, profiles, skills, and launchers.
- `copilot-ultron/`: Copilot CLI plugin, VS Code custom agents, skills, prompts, and launchers.

Each package includes its own installation and validation instructions in its README.

## Quick Start

Choose the package for the tool you use, then run its installer from that package directory.

```powershell
cd codex-ultron
.\scripts\install.ps1
```

```powershell
cd copilot-ultron
.\scripts\install.ps1
```

The installers protect existing user files unless a force option is explicitly supplied. Review the package README before installing into a shared or project-specific configuration.

## Validation

Run the package checks from the repository root:

```powershell
.\codex-ultron\scripts\test-package.ps1
.\copilot-ultron\scripts\test-package.ps1
```

The repository intentionally excludes local workspace instructions, practice reviews, and planning notes from version control. These remain useful during development but are not part of the distributable packages.