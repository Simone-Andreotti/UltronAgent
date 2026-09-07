# UltronAgent

UltronAgent is a portable multi-agent workflow for Codex and GitHub Copilot. Ultron uses Astra medium, Jarvis uses Sol high, and Edith keeps Luna maximum reasoning. Leads orchestrate bounded Luna agents for analysis, research, implementation, browser testing, and image work; they handle the most difficult or critical work directly only when needed. Non-trivial plans under `tasks/plans/` assign each step a Luna role, count, scope, dependencies, validation, and escalation condition. Use the fewest workers needed and parallelize only independent work.

## Packages

- `codex-ultron/`: Codex CLI and desktop app agents, profiles, skills, and launchers.
- `copilot-ultron/`: Copilot CLI plugin, VS Code custom agents, skills, prompts, and launchers.

Each package includes its own installation and validation instructions in its README.

Direct selection differs by host: Codex CLI starts a lead through `--profile`; Copilot uses its agent picker or `--agent`. Selecting a skill alone cannot switch an active model. Agent metadata requests the configured model and available tools, but account availability, session overrides, and host policy determine what can actually run. See the package READMEs for direct-selection details.

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

The supplied launchers default to full system access and live web access. Agents prefer writes inside the working folder and write elsewhere only when the task requires it. Luna handles browser testing, screenshots, and image work, escalating only when its capabilities are insufficient. It checks native browser tools first, repairs or installs a suitable fallback when needed, and verifies that the browser works. Copilot also bundles a pinned Playwright MCP fallback. Package READMEs document explicit restricted launch options; host and administrator policy still take precedence, including VS Code permissions. Installing these files does not change an already-running session's permissions or models.

## Validation

Run the package checks from the repository root:

```powershell
.\codex-ultron\scripts\test-package.ps1
.\copilot-ultron\scripts\test-package.ps1
```

Repository implementation checklists live in `tasks/plans/`; they document development work and are not copied by either package installer.
