# UltronAgent

UltronAgent is a portable multi-agent workflow for Codex and GitHub Copilot. It provides lead agents for different levels of work and bounded Luna agents for focused analysis, research, and implementation.

## Packages

- `codex-ultron/`: Codex CLI and desktop app agents, profiles, skills, and launchers.
- `copilot-ultron/`: Copilot CLI plugin, VS Code custom agents, skills, prompts, and launchers.

Each package includes its own installation and validation instructions in its README.

## Installation

Choose `codex-ultron`, `copilot-ultron`, or both. Run the commands from the repository root.

Global installation applies the package to your user profile. Project installation applies it only to the project path you provide. Existing files are protected unless a force option is explicitly supplied.

### Windows

Use PowerShell for either package.

Global installation:

```powershell
.\codex-ultron\scripts\install.ps1
.\copilot-ultron\scripts\install.ps1
```

Project installation:

```powershell
.\codex-ultron\scripts\install.ps1 -Scope Project -ProjectPath C:\path\to\project
.\copilot-ultron\scripts\install.ps1 -Scope Project -ProjectPath C:\path\to\project
```

Add `-Force` to replace files that are already installed.

### Linux and macOS

Use the POSIX shell installers.

Global installation:

```sh
sh ./codex-ultron/scripts/install.sh
sh ./copilot-ultron/scripts/install.sh
```

Project installation:

```sh
sh ./codex-ultron/scripts/install.sh --scope project --project-path /path/to/project
sh ./copilot-ultron/scripts/install.sh --scope project --project-path /path/to/project
```

Add `--force` to replace files that are already installed. The scripts detect Linux and macOS user configuration paths automatically.

The Codex installer places global files under `~/.codex` and `~/.agents`, or project files under `.codex` and `.agents`. The Copilot installer places global files under `~/.copilot` and the VS Code user profile, or project files under `.github/agents`, `.github/prompts`, and `.github/skills`.

## Validation

Run the package checks from the repository root:

```powershell
.\codex-ultron\scripts\test-package.ps1
.\copilot-ultron\scripts\test-package.ps1
```

The repository intentionally excludes local workspace instructions, practice reviews, and planning notes from version control. These remain useful during development but are not part of the distributable packages.