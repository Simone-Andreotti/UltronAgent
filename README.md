# UltronAgent

UltronAgent is a portable multi-agent workflow for Codex, GitHub Copilot, and Claude Code. In the Claude package, Ultron leads on Opus 5.5, Jarvis on Sonnet 5.5, and Edith on Haiku 5.5, as described in its README. In the Codex package, Ultron and Jarvis use Sol 6.1 high, Edith keeps Luna maximum reasoning, and Ultron alone may assign an exceptionally difficult, critical single task to an Astra high specialist. The Copilot package keeps its separately documented host-specific routing. Outside the Claude package, leads orchestrate bounded Luna agents for analysis, research, implementation, browser testing, and image work. Non-trivial plans under `tasks/plans/` assign each step a role, count, scope, dependencies, validation, and escalation condition. Use the fewest workers needed and parallelize only independent work.

Use `luna-code-analyst` for bounded code analysis and `luna-researcher` for research. Use `luna-worker` for testing, simple checks, simple fixes, simple implementations, and routine integration. Only Jarvis and Ultron may invoke `sol-worker` on `gpt-6.1-sol` with high reasoning for difficult implementation, including complex algorithms, 3D modeling, and similar work beyond Luna capability. Choose Sol when the required complexity is already clear; do not require a failed Luna attempt. Keep architecture decisions, orchestration, and final acceptance with the lead; standalone research, testing, and checks stay with Luna. The Sol worker may run focused validation of its own deliverable. A `sol-worker` assignment must explicitly identify Jarvis or Ultron as the caller, state why Luna is insufficient, and include owned files, preserved interfaces, acceptance criteria, required validation, and a ready plan milestone for non-trivial work. Workers cannot spawn or delegate. Edith must escalate difficult implementation to Jarvis or Ultron and must never invoke or instruct the Sol worker.

## Packages

- `codex-ultron/`: Codex CLI and desktop app agents, profiles, skills, and launchers.
- `copilot-ultron/`: Copilot CLI plugin, VS Code custom agents, skills, prompts, and launchers.
- `claude-ultron/`: Claude Code plugin with the leads, workers, and lead runtime for the terminal, the desktop app, and the VS Code extension, plus launchers for the terminal.

Each package includes its own installation and validation instructions in its README.

Direct selection differs by host: Codex CLI starts a lead through `--profile`; Copilot uses its agent picker or `--agent`; Claude Code takes `@ultron` or `/ultron` in any chat, or `--agent` on a terminal. On Codex and Copilot, selecting a skill alone cannot switch an active model. Agent metadata requests the configured model and available tools, but account availability, session overrides, and host policy determine what can actually run. See the package READMEs for direct-selection details.

## Installation

Choose `codex-ultron`, `copilot-ultron`, `claude-ultron`, or any combination. Run the commands from the repository root.

Global installation applies the package to your user profile. Project installation applies it only to the project path you provide. The Codex and Copilot packages recognize their own marker-managed files on repeat runs, replace them, remove stale managed files, and preserve unrelated customizations. An unmanaged same-name collision still requires an explicit force option.

`claude-ultron` installs through its own plugin installer on every platform, run from its own folder; see [its README](claude-ultron/README.md).

### Windows

Use PowerShell for either of the other packages.

Global installation:

```powershell
.\codex-ultron\scripts\install.ps1
.\copilot-ultron\scripts\install.ps1
```

For a native Copilot CLI plugin install or upgrade, use the replacement installer instead of the manual copy installer. It registers the package's versioned `ultron-agent` marketplace and avoids deprecated direct-plugin installation:

```powershell
.\copilot-ultron\scripts\install-plugin.ps1
```

For the Codex desktop app, use its plugin installer instead of the standalone-skill installer:

```powershell
.\codex-ultron\scripts\install-plugin.ps1
```

It installs the **Ultron**, **Jarvis**, and **Edith** plugins and retains native model-specific agents and lead profiles. In the chat composer, type `@ultron`, `@jarvis`, or `@edith`, select that role's plugin, and describe your task in the same message. No activation sentence or terminal command is needed, and the selected lead stays active for follow-up messages. Restart Codex once only if the plugins do not appear. Plugin selection keeps the current chat model; native lead launchers still choose a deterministic model.

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

Codex desktop plugin install or upgrade:

```sh
sh ./codex-ultron/scripts/install-plugin.sh
```

Project installation:

```sh
sh ./codex-ultron/scripts/install.sh --scope project --project-path /path/to/project
sh ./copilot-ultron/scripts/install.sh --scope project --project-path /path/to/project
```

Use `--force` only to take ownership of an unmanaged same-name collision. The scripts detect Linux and macOS user configuration paths automatically.

The Codex installer places global files under `~/.codex` and `~/.agents`, or project agents, a non-destructive config example, and skills under `.codex` and `.agents`. The Copilot installer places global files under `~/.copilot` and the VS Code user profile, or project files under `.github/agents`, `.github/prompts`, and `.github/skills`.

The Codex and Copilot launchers default to full system access and live web access; `claude-ultron`'s default to `--permission-mode auto`, and its README covers the rest of its behavior. In the Codex and Copilot packages, agents prefer writes inside the working folder and write elsewhere only when the task requires it. Luna handles browser testing, screenshots, and image work, escalating only when its capabilities are insufficient. It checks native browser tools first, repairs or installs a suitable fallback when needed, and verifies that the browser works. Copilot also bundles a pinned Playwright MCP fallback. Package READMEs document explicit restricted launch options; host and administrator policy still take precedence, including VS Code permissions. Installing these files does not change an already-running session's permissions or models.

## Validation

Run the package checks from the repository root:

```powershell
.\codex-ultron\scripts\test-package.ps1
.\copilot-ultron\scripts\test-package.ps1
.\claude-ultron\scripts\test-package.ps1
```

The Codex plugin's offline runtime check uses the installed Codex CLI and Python 3.11+:

```powershell
python .\codex-ultron\scripts\test-plugin.py
```

The Claude plugin's runtime check drives the installed Claude Code CLI against a local fake API and spends no tokens:

```powershell
python .\claude-ultron\scripts\test-runtime.py
```

Repository implementation checklists live in `tasks/plans/`; they document development work and are not copied by any package installer.
