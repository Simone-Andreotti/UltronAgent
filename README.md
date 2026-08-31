# UltronAgent

UltronAgent is a portable multi-agent workflow for Codex and GitHub Copilot. It provides role-routed Sol, Terra, and Luna leads plus bounded Luna agents for focused analysis, research, and implementation. Both packages persist non-trivial implementation plans under `tasks/plans/`, expose browser testing, and keep small work on a direct low-token path.

## Packages

- `codex-ultron/`: Codex CLI and desktop app agents, profiles, skills, and launchers.
- `copilot-ultron/`: Copilot CLI plugin, VS Code custom agents, skills, prompts, and launchers.

Each package includes its own installation and validation instructions in its README.

## Installation

Choose `codex-ultron`, `copilot-ultron`, or both. Run the commands from the repository root.

Global installation applies the package to your user profile. Project installation applies it only to the project path you provide. Both packages recognize their own marker-managed files on repeat runs, replace them, remove stale managed files, and preserve unrelated customizations. An unmanaged same-name collision still requires an explicit force option.

### Windows

Use PowerShell for either package.

Global installation:

```powershell
.\codex-ultron\scripts\install.ps1
.\copilot-ultron\scripts\install.ps1
```

For a native Copilot CLI plugin install or upgrade, use the replacement installer instead of the manual copy installer. It registers the package's versioned `ultron-agent` marketplace and avoids deprecated direct-plugin installation:

```powershell
.\copilot-ultron\scripts\install-plugin.ps1
```

Project installation:

```powershell
.\codex-ultron\scripts\install.ps1 -Scope Project -ProjectPath C:\path\to\project
.\copilot-ultron\scripts\install.ps1 -Scope Project -ProjectPath C:\path\to\project
```

Use `-Force` only to take ownership of an unmanaged same-name collision.

### Linux and macOS

Use the POSIX shell installers.

Global installation:

```sh
sh ./codex-ultron/scripts/install.sh
sh ./copilot-ultron/scripts/install.sh
```

Native Copilot CLI plugin install or upgrade:

```sh
sh ./copilot-ultron/scripts/install-plugin.sh
```

Project installation:

```sh
sh ./codex-ultron/scripts/install.sh --scope project --project-path /path/to/project
sh ./copilot-ultron/scripts/install.sh --scope project --project-path /path/to/project
```

Use `--force` only to take ownership of an unmanaged same-name collision. The scripts detect Linux and macOS user configuration paths automatically.

The Codex installer places global files under `~/.codex` and `~/.agents`, or project agents, a non-destructive config example, and skills under `.codex` and `.agents`. The Copilot installer places global files under `~/.copilot` and the VS Code user profile, or project files under `.github/agents`, `.github/prompts`, and `.github/skills`.

The supplied launchers intentionally default to live browser/network access, approval-free execution inside the active workspace, and no automatic filesystem access outside it. Copilot also bundles a pinned Playwright MCP fallback for CLI releases that do not yet expose their built-in browser server. Use explicit full-access overrides only for exceptional trusted tasks. Administrator-managed policy still takes precedence.

## Validation

Run the package checks from the repository root:

```powershell
.\codex-ultron\scripts\test-package.ps1
.\copilot-ultron\scripts\test-package.ps1
```

Repository implementation checklists live in `tasks/plans/`; they document development work and are not copied by either package installer.
