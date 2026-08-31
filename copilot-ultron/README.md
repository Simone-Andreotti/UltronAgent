# Copilot Ultron

Portable Copilot CLI and VS Code custom-agent package mirroring the source Codex Ultron, Jarvis, Edith, and Luna orchestration setup.

Nothing in this folder installs itself. The included installer only runs when you explicitly execute it.

## Fixed Model Policy

The package never uses Copilot Auto. Ultron uses `gpt-5.6-sol` with high reasoning, Jarvis uses `gpt-5.6-terra` with medium reasoning, and Edith uses `gpt-5.6-luna` with low reasoning. Every Luna role stays on `gpt-5.6-luna`: code analysis uses high reasoning, while research and implementation use medium. All roles stay on the `default` context tier and never use `long_context`. Copilot CLI honors the agent `reasoningEffort` field and the launchers pin it explicitly. VS Code pins the agent model; clients that do not expose effort in custom-agent frontmatter use the host's selected reasoning level instead.

Simple, well-scoped work stays in the lead agent. Plans and Luna subagents are reserved for complex work where isolation or parallelism is necessary. Every subagent assignment must have a narrow scope and output bound.

Each lead identifies itself once when a chat starts: Edith says `Edith at your service.`, Ultron says `Lowly human, let Ultron manage the rest.`, and Jarvis says `Jarvis at your service.` All roles then work silently while tools are running: no progress updates, plan narration, reasoning, or routine status messages. Silence affects chat only, never implementation, review, or validation quality. Luna roles return one bounded packet to their lead. Edith, Ultron, and Jarvis respond only with `0` after success or `1` when completion is impossible; a genuinely blocking question uses the fewest words possible.

Use `/explain <task>` with any selected lead to turn on concise progress updates and high-level decision rationale for that request. The command preserves the selected lead and its configured model. It provides a user-facing explanation rather than private chain-of-thought or tool-internal reasoning.

Todo tracking remains available to all three leads. They use it only when it improves execution, with action-only labels of 2-5 words and silent status updates; written plan checklists are not duplicated in todo.

All leads and `luna-worker` can test rendered applications. VS Code uses the built-in `browser` tool set. Newer Copilot CLI releases can expose the built-in `playwright/*` namespace; this plugin also provides `ultron-playwright/*` through pinned `@playwright/mcp@0.0.79` for releases such as Copilot CLI 1.0.68 that do not enumerate the built-in server. For web-facing acceptance, the roles start or locate the app, exercise the requested flow, inspect page and console evidence, and repeat the browser check after changes.

For CLI sessions, use `--max-ai-credits` to set a hard session limit. The minimum accepted limit is 30 credits, and one in-flight call can exceed the limit before the next call is blocked.

## Package Layout

- `plugin.json`: native Copilot CLI plugin manifest
- `.github/plugin/marketplace.json`: versioned `ultron-agent` marketplace manifest for supported installs and upgrades
- `.mcp.json`: pinned `ultron-playwright` browser automation fallback for Copilot CLI
- `skills/ultron-orchestrator/SKILL.md`: single chat skill entry point, `/ultron-orchestrator`
- `agents/`: Edith, Ultron, Jarvis, and three bounded Luna custom agents
- `prompts/explain.prompt.md`: `/explain` slash command for the selected lead
- `scripts/start-ultron.*`: start Copilot CLI with Ultron on Windows, Linux, or macOS
- `scripts/start-jarvis.*`: start Copilot CLI with Jarvis on Windows, Linux, or macOS
- `scripts/start-edith.*`: start Copilot CLI with Edith on Windows, Linux, or macOS
- `scripts/install-plugin.*`: replace an existing native CLI plugin snapshot with the current package
- `scripts/install.*`: optional user-level or project-level installer for all three operating systems
- `config/copilot-config.example.json`: optional CLI configuration reference
- `scripts/test-package.ps1`: dependency-free package contract checks

## Try Locally Without Installing

Windows PowerShell, from this folder:

```powershell
.\scripts\start-ultron.ps1
.\scripts\start-jarvis.ps1
.\scripts\start-edith.ps1
```

Pass an initial prompt if needed:

```powershell
.\scripts\start-ultron.ps1 -Prompt "Design and implement the requested system"
```

Set a session credit limit when needed:

```powershell
.\scripts\start-ultron.ps1 -MaxAiCredits 100
```

Linux or macOS:

```sh
chmod +x scripts/*.sh
./scripts/start-ultron.sh
./scripts/start-jarvis.sh
./scripts/start-edith.sh
./scripts/start-ultron.sh -i "Design and implement the requested system"
```

POSIX launchers allow additional CLI options but reject agent, plugin, model, reasoning-effort, and context overrides:

```sh
./scripts/start-ultron.sh --max-ai-credits 100
```

The launchers use only files in this package and do not copy them into your profile.

Launchers enable Copilot's local OS sandbox, all tools, and all URLs by default, while retaining the working-directory path boundary and disabling its system temporary directory. This lets Playwright and local development servers run without approval while keeping file access scoped to the workspace. On Windows, local sandboxing requires a supported Windows Insiders build; use `-Sandbox:$false` or `COPILOT_SANDBOX=false` only when that host feature is unavailable. An explicit `-AllowAll`/`COPILOT_ALLOW_ALL=true` opt-in disables the sandbox and enables system-wide paths for exceptional trusted tasks:

```powershell
.\scripts\start-ultron.ps1 -AllowAll
```

```sh
COPILOT_ALLOW_ALL=true ./scripts/start-ultron.sh
```

In VS Code, select Bypass Approvals or Autopilot for equivalent uninterrupted execution. Keep `workbench.browser.enableChatTools` enabled. Organization policy can still block browser tools or bypass permissions and cannot be overridden by an agent file.

## Optional Installation

### Copilot CLI Plugin

Anyone can copy or clone this complete folder and install or upgrade the native plugin with the replacement script:

```powershell
.\scripts\install-plugin.ps1
```

```sh
sh scripts/install-plugin.sh
```

The script removes only an existing `ultron-orchestrator` installation and `ultron-agent` registration, registers this package as a local marketplace, and installs `ultron-orchestrator@ultron-agent`. Repeat runs therefore replace the prior version without using deprecated direct-plugin installation. For a remote registered marketplace, use `copilot plugin update ultron-orchestrator@ultron-agent` instead.

Native plugin installs and the supplied launchers load the packaged Playwright fallback. The manual copy installer is primarily for VS Code and unnamespaced agents; older CLI versions need the plugin or `--plugin-dir` launcher path for browser automation.

Restart Copilot CLI after installation. Plugin agents are namespaced. Their model frontmatter applies automatically, so no model flag is required:

```sh
copilot --agent ultron-orchestrator:ultron
copilot --agent ultron-orchestrator:jarvis
copilot --agent ultron-orchestrator:edith
```

In interactive CLI chat, use `/ultron-orchestrator`, or open `/agent` and select the required lead.

### Windows And VS Code

Install for both Copilot CLI's manual customization paths and the VS Code user profile:

```powershell
.\scripts\install.ps1
```

Install into the current repository instead:

```powershell
.\scripts\install.ps1 -Scope Project -ProjectPath C:\path\to\repo
```

### Linux, macOS, And VS Code

User-level installation:

```sh
sh scripts/install.sh
```

Project-level installation:

```sh
sh scripts/install.sh --scope project --project-path /path/to/repo
```

Repeat runs are managed upgrades. The installer recognizes its skill and marker files, replaces current package files, and removes package-managed agent or prompt files retired by a newer version. Unrelated files remain untouched. An unrecognized same-name collision is rejected; use `-Force` or `--force` only when intentionally taking ownership of that collision.

After user-level installation:

- CLI manual installation: run `copilot --agent ultron`.
- VS Code: select `edith`, `ultron`, or `jarvis` from the custom-agent picker.
- Chat: invoke `/ultron-orchestrator` in Copilot Chat when skills are enabled.

Reload the VS Code window after installing. The user installer writes agents to `~/.copilot/agents` and the platform's VS Code user prompts directory. The project installer writes portable files under `.github/agents` and `.github/skills`, so committing those directories shares the setup with repository collaborators.

The copy installers record package ownership in `.ultron-orchestrator-agents` and `.ultron-orchestrator-prompts` marker files inside shared customization roots. Do not edit those generated marker files manually.

## Sharing The Package

1. Share the entire `copilot-ultron` directory as a repository, archive, or normal folder. Preserve its directory structure.
2. The recipient must have Copilot CLI or the VS Code Copilot extension and access to GPT-5.6 Sol, GPT-5.6 Terra, and GPT-5.6 Luna.
3. For CLI-only use, the recipient runs `scripts/install-plugin.ps1` or `scripts/install-plugin.sh` from the folder.
4. For CLI plus VS Code, the recipient runs the platform installer above, then restarts Copilot CLI and reloads VS Code.
5. For one repository only, use project scope and commit the generated `.github/agents` and `.github/skills` directories.

## Architecture

Edith, Ultron, and Jarvis are user-invocable leads. They can call only the three hidden Luna roles:

- `luna-code-analyst`: read-only repository analysis
- `luna-researcher`: read-only documentation and evidence research
- `luna-worker`: narrow implementation after a written plan milestone exists

Edith owns simpler work; Jarvis owns medium-complexity work; Ultron owns complex work. Each lead executes routine work directly and owns planning, architectural decisions, shared-file changes, integration, validation, and the binary completion response. Luna roles cannot delegate, stay on GPT-5.6 Luna and default context, and use high reasoning only for code analysis; research and implementation use medium. Complex work uses only the minimum subagents needed for material independent tracks.

Before the first implementation edit for non-trivial work, the lead creates `tasks/plans/<task-slug>.md` with Current Architecture, Intended Design, Preserved Interfaces, checkbox Milestones, and Validation. One milestone is marked in progress; it is checked immediately after focused validation before the next starts. Todo state is not a substitute. Independent, non-overlapping subagent tasks may run in parallel, and every Luna invocation receives exactly one narrow assignment.

## Differences From Codex

- Copilot custom agents use Markdown with YAML frontmatter rather than Codex TOML.
- Copilot tool aliases expose VS Code's integrated browser, newer CLI Playwright tools, and the packaged `ultron-playwright` fallback; permission mode remains a host/session control.
- Copilot does not expose Codex service tier, desktop plugin, notice, or sandbox configuration through these files.
- Fixed role-model assignments replace Copilot Auto: Edith and Luna subagents use Luna, Ultron uses Sol, and Jarvis uses Terra. Every role remains on default context.

## Validation

From the repository root:

```powershell
.\copilot-ultron\scripts\test-package.ps1
```

The check validates JSON, marketplace and plugin version parity, the pinned Playwright MCP fallback, package paths, model effort, browser tools, planning, silent-output contracts, failure signaling, skill parity, launcher permissions, managed user/project upgrades, a mocked marketplace replacement lifecycle, and PowerShell syntax. It never modifies the user's real Copilot plugin registry.

## References

- [Optimize AI credit usage in VS Code](https://code.visualstudio.com/docs/agents/guides/optimize-usage)
- [Custom agents in VS Code](https://code.visualstudio.com/docs/agent-customization/custom-agents)
- [Agent skills in VS Code](https://code.visualstudio.com/docs/agent-customization/agent-skills)
- [Subagents in VS Code](https://code.visualstudio.com/docs/agents/run/subagents)
- [Browser tools in VS Code](https://code.visualstudio.com/docs/agents/run/browser-tools)
- [Approvals and permissions in VS Code](https://code.visualstudio.com/docs/agents/run/approvals)
- [Copilot CLI plugin reference](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-plugin-reference)
- [GitHub Awesome Copilot](https://github.com/github/awesome-copilot)
