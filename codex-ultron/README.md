# Codex Ultron

Portable Ultron, Jarvis, Edith, and Luna setup for Codex CLI and the Codex surface in the ChatGPT desktop app.

## Model Routing

- Ultron: `gpt-6-astra`, medium reasoning
- Jarvis: `gpt-5.6-sol`, high reasoning
- Edith: `gpt-5.6-luna`, maximum (`xhigh`) reasoning
- Every Luna subagent: `gpt-5.6-luna`, maximum (`xhigh`) reasoning

The CLI and desktop launchers select the requested lead profile and model automatically. Custom Luna agent files select their own model automatically when spawned. Generic Codex chats do not permit a skill to replace the model of an already-running thread, so use the matching launcher when deterministic lead routing matters.

Leads own orchestration, critical decisions, integration acceptance, and user communication. Routine implementation is delegated to bounded Luna assignments when useful, including one serialized shared-file integration step. Each delegated plan step records role, count (usually one), owned scope/files, dependencies, focused check, and escalation; only independent steps run in parallel and Luna roles never recurse. Low model verbosity and role-specific effort avoid spending deep-reasoning tokens on repeatable work.

For requests that explicitly ask for internet or web research, external references, current documentation, library comparisons, or proven patterns, Ultron makes a fresh `luna_researcher` child its first external-evidence action. The lead waits for that bounded evidence packet before planning and only researches directly afterward to fill a specific gap. Profiles and launchers enable live web search by default.

Codex loads the three Luna specialties as first-class custom agents from `~/.codex/agents` or a trusted project's `.codex/agents`. Leads select the exact underscore role name through the native subagent workflow. Each standalone Luna TOML owns its model, reasoning effort, sandbox, and instructions; omitted plugin and tool integrations inherit from the parent. Assignments name only the required plan and files instead of copying full parent history. Luna work remains bounded and non-orchestrating.

Before the first implementation edit for non-trivial work, every lead entry path creates `tasks/plans/<task-slug>.md`. The file records Current Architecture, Intended Design, Preserved Interfaces, checkbox Milestones, and Validation. One milestone is marked in progress and checked immediately after focused validation before the next begins. Session Plan mode and internal todo state do not replace this repository artifact; `luna_worker` requires a ready plan milestone for non-trivial assignments while allowing trivial one-packet work to proceed.

Profiles, lead agents, project config, and desktop launchers enable `browser@openai-bundled`, live search, and approval-free execution with `danger-full-access` by default. Agents use the active working folder first and broaden writes only when necessary under host policy. Set `CODEX_ULTRON_FULL_ACCESS=false` for an explicit `workspace-write` opt-out; launchers pass that restricted mode explicitly. For web-facing work, agents check native browser availability, reuse existing project-local Playwright/dependencies, install a suitable project-local Playwright/browser runtime when needed, launch and retest, then exercise the rendered flow and inspect page, console, network, and screenshot evidence before claiming success. Image work uses available image tools; missing hosted capability is reported and escalated without global installation.

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
- `ultron.config.toml`, `jarvis.config.toml`, and `edith.config.toml` under `$CODEX_HOME` (default `~/.codex`);
- the shared skill to `~/.agents/skills/codex-ultron`.

These locations are shared by Codex CLI and the desktop app. Repeat runs replace only files recorded in `.codex-ultron-agents` and `.codex-ultron-profiles`, remove stale managed files, and preserve unrelated customizations. An unmanaged same-name collision is rejected; use `-Force` or `--force` only when intentionally taking ownership of it. Restart Codex after installation if the skill or agents do not appear immediately.

The installed lead profiles intentionally use `approval_policy = "never"`, `sandbox_mode = "danger-full-access"`, and live web plus Browser plugin access. They can work autonomously while starting with the active working folder. The CLI and desktop launchers default to full access; set `CODEX_ULTRON_FULL_ACCESS=false` to force `sandbox_mode = "workspace-write"` for a restricted session.

Project-scoped installation is available for repositories that should share agents and the skill:

```powershell
.\scripts\install.ps1 -Scope Project -ProjectPath C:\path\to\repo
```

```sh
sh scripts/install.sh --scope project --project-path /path/to/repo
```

Project scope writes `.codex/agents`, `.codex/codex-ultron.example.toml`, and `.agents/skills/codex-ultron`. It never replaces an existing `.codex/config.toml`; merge the documented defaults from the example when the primary project session needs them. Codex loads project configuration only for trusted projects. Lead profiles are user-level Codex configuration, so install user scope once before using the deterministic launchers.

## Codex CLI

The supported primary-agent choices are profiles. Use the unified launcher for an interactive Edith/Jarvis/Ultron menu:

Windows:

```powershell
.\scripts\start-codex.ps1
.\scripts\start-codex.ps1 -Agent jarvis -WorkingDirectory C:\path\to\repo
.\scripts\start-ultron.ps1
.\scripts\start-jarvis.ps1
.\scripts\start-edith.ps1
.\scripts\start-ultron.ps1 -Prompt "Design and implement the requested system"
```

Linux or macOS:

```sh
chmod +x scripts/*.sh
./scripts/start-codex.sh
./scripts/start-codex.sh --agent jarvis
./scripts/start-ultron.sh
./scripts/start-jarvis.sh
./scripts/start-edith.sh
./scripts/start-ultron.sh "Design and implement the requested system"
```

The launchers reject profile, model, provider, reasoning, and arbitrary config overrides. Direct equivalents are:

```sh
codex --profile ultron --model gpt-6-astra
codex --profile jarvis --model gpt-5.6-sol
```

Codex CLI has no native `--agent` primary-session switch. Launcher `-Agent`/`--agent` selects one of these profiles; standalone agent TOMLs apply when Codex selects a custom agent through its native subagent workflow. Mentioning `$codex-ultron` cannot replace the model of an already-running thread, and model, plugin, browser, and network availability still depend on the installed Codex runtime and host policy.

CLI launchers enable live search and full access by default. Disable search or opt into an explicit restricted workspace session with:

```powershell
.\scripts\start-ultron.ps1 -Search:$false
```

```sh
CODEX_ULTRON_LIVE_SEARCH=false ./scripts/start-ultron.sh
```

```sh
CODEX_ULTRON_FULL_ACCESS=false ./scripts/start-ultron.sh
```

Each CLI launcher prints the selected lead's exact startup greeting before invoking Codex. This handshake is emitted by the launcher rather than left to model response timing, so it remains visible even when the first model response is only the configured completion status.

In any Codex CLI session, mention `$codex-ultron` to invoke the shared workflow explicitly.

## Desktop App

Install user scope, then use the unified launcher to choose a lead and open a workspace. Codex does not currently expose a native primary custom-agent picker for `codex app`; the launcher is the supported choice layer.

Windows:

```powershell
.\scripts\start-codex-app.ps1
.\scripts\start-codex-app.ps1 -Agent jarvis -WorkingDirectory C:\path\to\repo
.\scripts\start-ultron-app.ps1 -WorkingDirectory C:\path\to\repo
.\scripts\start-jarvis-app.ps1 -WorkingDirectory C:\path\to\repo
.\scripts\start-edith-app.ps1 -WorkingDirectory C:\path\to\repo
```

Linux or macOS:

```sh
./scripts/start-codex-app.sh
./scripts/start-codex-app.sh --agent jarvis /path/to/repo
./scripts/start-ultron-app.sh /path/to/repo
./scripts/start-jarvis-app.sh /path/to/repo
./scripts/start-edith-app.sh /path/to/repo
```

The launcher passes the selected model, role-specific reasoning, low verbosity, live search, full-access (or explicit restricted) execution, Browser plugin enablement, and matching lead instructions while opening the desktop workspace. Codex accepts `--profile` for runtime CLI commands but not `codex app`, so desktop launchers inject the equivalent settings explicitly. In the desktop skill picker, `Codex Ultron` provides the same orchestration workflow. Agent activity appears as inspectable subagent threads.

## Package Layout

- `agents/`: six custom Codex agent TOMLs
- `profiles/`: Edith, Ultron, and Jarvis primary-session profiles
- `instructions/`: Edith, Ultron, and Jarvis lead instructions injected by desktop launchers
- `skills/codex-ultron/`: shared CLI and desktop skill with app metadata
- `config/codex-config.example.toml`: portable project-level multi-agent, browser, search, and permission defaults
- `scripts/install.*`: managed user/project installers with stale-file cleanup and conflict protection
- `scripts/start-*`: locked individual launchers plus unified Edith/Jarvis/Ultron CLI and desktop choosers
- `scripts/test-package.ps1`: package and disposable-install checks

The package deliberately excludes credentials, trust records, notifications, machine paths, and machine-specific MCP runtime entries. It includes only portable Browser plugin, live-search, sandbox, and approval defaults. User or administrator requirements can still restrict these capabilities.

## Validate

```powershell
.\scripts\test-package.ps1
```

The check validates role TOMLs, model effort, Browser and network access, persistent planning, silent-output contracts, skill metadata, launcher permissions, PowerShell syntax, disposable user/project installs, conflict protection, and profile loading through the installed Codex CLI.

## References

- [Codex subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents)
- [Codex models](https://learn.chatgpt.com/docs/models)
- [Codex configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference)
- [Build skills](https://learn.chatgpt.com/docs/build-skills)
- [ChatGPT desktop app](https://learn.chatgpt.com/docs/app)
