# Copilot Ultron

Portable Copilot CLI and VS Code custom-agent package mirroring the source Codex Ultron, Jarvis, Edith, and Luna orchestration setup.

Nothing in this folder installs itself. The included installer only runs when you explicitly execute it.

## Fixed Model Policy

Effort metadata includes both current `reasoningEffort` and the legacy `reasoning-effort` key read by CLI 1.0.68, with identical values. That CLI ignores the current spelling with a warning; retaining its legacy key prevents direct selection from inheriting an unintended effort. Hosts may warn about the spelling they do not recognize. VS Code controls effort through its model picker.

The package never uses Copilot Auto in its launchers. Ultron requests `gpt-6-astra` with medium reasoning, Jarvis requests `gpt-5.6-sol` with high reasoning, and Edith requests `gpt-5.6-luna` with maximum (`xhigh`) reasoning. Every Luna role requests `gpt-5.6-luna`: code analysis uses high reasoning, while research and implementation use medium. Agent frontmatter uses the supported `model` field and CLI `reasoningEffort` field; VS Code applies the model request while its session picker controls effort. The example CLI settings use namespaced subagent keys and request the `default` context tier. Launchers leave context selection to the host's default because some CLI prompt modes reject the context flag. Account, model availability, host picker, and organization policy can replace an unavailable request with the active session model or effort; the package never promises an unavailable slug.

Older Copilot CLI builds may ignore newer agent metadata and use the session model or effort; update the CLI when per-agent routing is required.

Leads keep orchestration, critical or difficult decisions, and final acceptance. Routine implementation, focused checks, and serialized integration go to the exact existing Luna role that owns them. Use the fewest workers needed, normally one; parallelize only independent work. Every subagent assignment must have a narrow scope and output bound.

Each lead identifies itself once when a chat starts: Edith says `Edith at your service.`, Ultron says `Lowly human, let Ultron manage the rest.`, and Jarvis says `Jarvis at your service.` All roles then work silently while tools are running: no progress updates, plan narration, reasoning, or routine status messages. Silence affects chat only, never implementation, review, or validation quality. Luna roles return one bounded packet to their lead. Edith, Ultron, and Jarvis respond only with `0` after success or `1` when completion is impossible; a genuinely blocking question uses the fewest words possible.

Use `/explain <task>` with any selected lead to turn on concise progress updates and high-level decision rationale for that request. The command preserves the selected lead and its configured model. It provides a user-facing explanation rather than private chain-of-thought or tool-internal reasoning.

Todo tracking remains available to all three leads. They use it only when it improves execution, with action-only labels of 2-5 words and silent status updates; written plan checklists are not duplicated in todo.

All agents inherit the host's full available tool set, including web and browser capabilities; read-only Luna contracts remain instruction-enforced. Shared agents use the canonical `playwright/*` namespace for tools. Route browser tests, screenshots, and image elaboration through `luna-worker`. Check native browser tooling first; if absent or broken, use existing project-local Playwright dependencies, then repair and install the pinned fallback through the package when permitted, then repeat the browser check after changes. Use a host-supplied image capability or existing project-local tooling; never invent a hosted tool. Prefer project-local installation, and install outside the working folder only when necessary and permitted by host policy. Report the exact host or policy blocker after feasible recovery. In VS Code, install the Playwright MCP server from Extensions by searching `@mcp playwright`, or configure a user MCP server with that name; otherwise VS Code correctly reports the server as missing. The native Copilot CLI plugin also bundles a pinned `ultron-playwright` fallback through `@playwright/mcp@0.0.79`.

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
- `scripts/test-package.ps1`: package contract checks using PowerShell and Python with PyYAML for frontmatter parsing

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

POSIX launchers allow additional CLI options but reject agent, plugin, model, and reasoning-effort overrides:

```sh
./scripts/start-ultron.sh --max-ai-credits 100
```

The launchers use only files in this package and do not copy them into your profile.

Launchers default to Copilot's supported full-access flag, `--allow-all`, so tools, URLs, and system paths are available for trusted sessions. Copilot CLI does not expose an OS sandbox switch; this package does not invent one. Agents still prefer writes inside the working folder and write elsewhere only when the task requires it. Use `-AllowAll:$false` or `COPILOT_ALLOW_ALL=false` for an explicit restricted session; it uses `--allow-all-tools --allow-all-urls --disallow-temp-dir`, which keeps CLI tool, URL, and temporary-directory permissions scoped. Host, organization, and administrator policy still takes precedence and can narrow either mode:

```powershell
.\scripts\start-ultron.ps1 -AllowAll:$false
```

```sh
COPILOT_ALLOW_ALL=false ./scripts/start-ultron.sh
```

In VS Code, agent files request a model, while the session model picker controls reasoning effort; agent files cannot bypass approvals or override account and organization policy. The picker and host permissions can replace unavailable requests; select Bypass Approvals or Autopilot only when the host offers it. Keep `workbench.browser.enableChatTools` enabled. Organization policy can still block browser tools or bypass permissions and cannot be overridden by an agent file.

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

Native plugin installs and the supplied launchers load the packaged Playwright fallback. The manual copy installer is primarily for VS Code and unnamespaced agents; older CLI versions need the plugin or `--plugin-dir` launcher path for browser automation. VS Code separately needs its Playwright MCP server installed or configured because it does not load a Copilot plugin's private MCP namespace.

Restart Copilot CLI after installation. Plugin agents are namespaced. Their `model` and `reasoningEffort` frontmatter requests apply automatically when the runtime supports the requested values, so no model flag is required:

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
2. The recipient must have Copilot CLI or the VS Code Copilot extension and runtime access to `gpt-6-astra`, `gpt-5.6-sol`, and `gpt-5.6-luna`; account and organization policy may limit availability.
3. For CLI-only use, the recipient runs `scripts/install-plugin.ps1` or `scripts/install-plugin.sh` from the folder.
4. For CLI plus VS Code, the recipient runs the platform installer above, then restarts Copilot CLI and reloads VS Code.
5. For one repository only, use project scope and commit the generated `.github/agents` and `.github/skills` directories.

## Architecture

Edith, Ultron, and Jarvis are user-invocable leads. They can call only the three hidden Luna roles:

- `luna-code-analyst`: read-only repository analysis
- `luna-researcher`: read-only documentation and evidence research
- `luna-worker`: one narrow implementation or focused check; non-trivial edits require a ready written plan milestone

Edith owns simpler work; Jarvis owns medium-complexity work; Ultron owns complex work. Leads orchestrate and own critical decisions, integration, validation, and the binary completion response; routine work goes to the exact Luna role that owns it. Luna roles cannot delegate, request GPT-5.6 Luna and default context, and use high reasoning only for code analysis; research and implementation use medium. Use the minimum worker count, normally one, and parallelize only independent tracks. Host policy controls actual permissions, model selection, effort, and browser availability.

Before the first implementation edit for non-trivial work, the lead creates `tasks/plans/<task-slug>.md` with Current Architecture, Intended Design, Preserved Interfaces, checkbox Milestones, and Validation. Each milestone names exactly one Luna role, worker count, owned scope, dependencies, executable check, and escalation condition. One milestone is marked in progress; it is checked immediately after focused validation before the next starts. Todo state is not a substitute. Independent, non-overlapping subagent tasks may run in parallel, and every Luna invocation receives exactly one narrow assignment. A trivial bounded worker assignment may use its complete packet without a plan.

## Differences From Codex

- Copilot custom agents use Markdown with YAML frontmatter rather than Codex TOML.
- Copilot agents inherit the host's available tools, including VS Code's integrated browser, newer CLI Playwright tools, and the packaged `ultron-playwright` fallback; permission mode remains a host/session control.
- Copilot does not expose Codex service tier, desktop plugin, notice, or host permission configuration through these files.
- Fixed CLI launcher assignments replace Copilot Auto: Edith uses Luna, Ultron uses Astra, and Jarvis uses Sol. VS Code receives the model requests from frontmatter, while its session picker controls effort subject to account policy; the example settings request default context.

## Validation

These checks require PowerShell, Python, and PyYAML (`python -m pip install PyYAML` if missing). From the repository root:

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
