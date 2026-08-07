# Codex Ultron

Portable Ultron, Jarvis, Edith, and Luna setup for Codex CLI and the Codex surface in the ChatGPT desktop app.

## Model Routing

- Ultron: `gpt-5.6-sol`, high reasoning
- Jarvis: `gpt-5.6-terra`, high reasoning
- Edith: `gpt-5.6-luna`, high reasoning
- Every Luna role: `gpt-5.6-luna`, max reasoning

The CLI and desktop launchers select the requested lead profile and model automatically. Custom Luna agent files select their own model automatically when spawned. Generic Codex chats do not permit a skill to replace the model of an already-running thread, so use the matching launcher when deterministic lead routing matters.

Small and well-scoped work stays in the lead. Luna is used only for bounded analysis, research, or implementation when isolation or independent parallelism materially reduces lead cost or context. Leads own architecture, shared files, integration, validation, and user communication.

## Install

Windows user installation:

```powershell
.\scripts\install.ps1
```

Linux or macOS user installation:

```sh
sh scripts/install.sh
```

The user installer writes:

- agents to `$CODEX_HOME/agents` or `~/.codex/agents`;
- `ultron.config.toml`, `jarvis.config.toml`, and `edith.config.toml` beside `~/.codex/config.toml`;
- the shared skill to `~/.agents/skills/codex-ultron`.

These locations are shared by Codex CLI and the desktop app. Existing files are protected. Use `-Force` or `--force` only when intentionally replacing a previous installation. Restart Codex after installation if the skill or agents do not appear immediately.

Project-scoped installation is available for repositories that should share agents and the skill:

```powershell
.\scripts\install.ps1 -Scope Project -ProjectPath C:\path\to\repo
```

```sh
sh scripts/install.sh --scope project --project-path /path/to/repo
```

Project scope writes `.codex/agents`, `.codex/config.toml`, and `.agents/skills/codex-ultron`. Codex loads project configuration only for trusted projects. Lead profiles are user-level Codex configuration, so install user scope once before using the deterministic launchers.

## Codex CLI

Windows:

```powershell
.\scripts\start-ultron.ps1
.\scripts\start-jarvis.ps1
.\scripts\start-edith.ps1
.\scripts\start-ultron.ps1 -Prompt "Design and implement the requested system"
```

Linux or macOS:

```sh
chmod +x scripts/*.sh
./scripts/start-ultron.sh
./scripts/start-jarvis.sh
./scripts/start-edith.sh
./scripts/start-ultron.sh "Design and implement the requested system"
```

The launchers reject profile, model, provider, reasoning, and arbitrary config overrides. Direct equivalents are:

```sh
codex --profile ultron --model gpt-5.6-sol
codex --profile jarvis --model gpt-5.6-terra
```

In any Codex CLI session, mention `$codex-ultron` to invoke the shared workflow explicitly.

## Desktop App

Install user scope, then launch the required lead into a workspace.

Windows:

```powershell
.\scripts\start-ultron-app.ps1 -WorkingDirectory C:\path\to\repo
.\scripts\start-jarvis-app.ps1 -WorkingDirectory C:\path\to\repo
.\scripts\start-edith-app.ps1 -WorkingDirectory C:\path\to\repo
```

Linux or macOS:

```sh
./scripts/start-ultron-app.sh /path/to/repo
./scripts/start-jarvis-app.sh /path/to/repo
./scripts/start-edith-app.sh /path/to/repo
```

The launcher passes the model, reasoning settings, and matching lead instructions while opening the desktop workspace. Codex currently accepts `--profile` for runtime CLI commands but not `codex app`, so desktop launchers inject the equivalent profile settings explicitly. In the desktop skill picker, `Codex Ultron` provides the same orchestration workflow. Agent activity appears as inspectable subagent threads.

## Package Layout

- `agents/`: six custom Codex agent TOMLs
- `profiles/`: Edith, Ultron, and Jarvis primary-session profiles
- `instructions/`: Edith, Ultron, and Jarvis lead instructions injected by desktop launchers
- `skills/codex-ultron/`: shared CLI and desktop skill with app metadata
- `config/codex-config.example.toml`: safe project-level multi-agent defaults
- `scripts/install.*`: atomic user/project installers
- `scripts/start-*`: locked CLI and desktop launchers
- `scripts/test-package.ps1`: package and disposable-install checks

The package deliberately excludes credentials, trust records, MCP servers, plugins, notifications, machine paths, sandbox preferences, and approval policy. Those remain owned by the user's existing Codex configuration.

## Validate

```powershell
.\scripts\test-package.ps1
```

The check validates role TOMLs, model routing, silent-output contracts, skill metadata, launcher locks, PowerShell syntax, disposable user/project installs, conflict protection, and profile loading through the installed Codex CLI.

## References

- [Codex subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents)
- [Codex configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference)
- [Build skills](https://learn.chatgpt.com/docs/build-skills)
- [ChatGPT desktop app](https://learn.chatgpt.com/docs/app)