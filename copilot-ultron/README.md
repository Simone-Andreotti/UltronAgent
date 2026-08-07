# Copilot Ultron

Portable Copilot CLI and VS Code custom-agent package mirroring the source Codex Ultron, Jarvis, Edith, and Luna orchestration setup.

Nothing in this folder installs itself. The included installer only runs when you explicitly execute it.

## Fixed Model Policy

The package never uses Copilot Auto. Selecting Edith in chat or CLI automatically selects `gpt-5.6-luna` from its agent metadata; selecting Ultron automatically selects `gpt-5.6-sol`; selecting Jarvis automatically selects `gpt-5.6-terra`. Every Luna role selects `gpt-5.6-luna` at max reasoning. All roles stay on the `default` context tier and never use `long_context`. The launchers also pass the lead model explicitly so CLI arguments cannot inherit or resume the wrong model. VS Code custom-agent metadata does not support setting Thinking Effort; select High in the model picker once for each lead model, and VS Code retains that selection for the session.

Simple, well-scoped work stays in the lead agent. Plans and Luna subagents are reserved for complex work where isolation or parallelism is necessary. Every subagent assignment must have a narrow scope and output bound.

Each lead identifies itself once when a chat starts: Edith says `Edith at your service.`, Ultron says `Lowly human, let Ultron manage the rest.`, and Jarvis says `Jarvis at your service.` All roles then work silently while tools are running: no progress updates, plan narration, reasoning, or routine status messages. Silence affects chat only, never implementation, review, or validation quality. Luna roles return one bounded packet to their lead. Edith, Ultron, and Jarvis respond only with `0` after success or `1` when completion is impossible; a genuinely blocking question uses the fewest words possible.

Use `/explain <task>` with any selected lead to turn on concise progress updates and high-level decision rationale for that request. The command preserves the selected lead and its configured model. It provides a user-facing explanation rather than private chain-of-thought or tool-internal reasoning.

Todo tracking remains available to both leads. They use it only when it improves execution, with action-only labels of 2-5 words and silent status updates; written plan checklists are not duplicated in todo.

For CLI sessions, use `--max-ai-credits` to set a hard session limit. The minimum accepted limit is 30 credits, and one in-flight call can exceed the limit before the next call is blocked.

## Package Layout

- `plugin.json`: native Copilot CLI plugin manifest
- `skills/ultron-orchestrator/SKILL.md`: single chat skill entry point, `/ultron-orchestrator`
- `agents/`: Edith, Ultron, Jarvis, and three bounded Luna custom agents
- `prompts/explain.prompt.md`: `/explain` slash command for the selected lead
- `scripts/start-ultron.*`: start Copilot CLI with Ultron on Windows, Linux, or macOS
- `scripts/start-jarvis.*`: start Copilot CLI with Jarvis on Windows, Linux, or macOS
- `scripts/start-edith.*`: start Copilot CLI with Edith on Windows, Linux, or macOS
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

## Optional Installation

### Copilot CLI Plugin

Anyone can copy or clone this complete folder, open a terminal in it, and install the native plugin with:

```sh
copilot plugin install .
```

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

Existing files are protected. Use `--force` only when replacing a previous installation intentionally.

After user-level installation:

- CLI plugin: run `copilot --agent ultron-orchestrator:ultron` or use the launchers.
- CLI manual installation: run `copilot --agent ultron`.
- VS Code: select `edith`, `ultron`, or `jarvis` from the custom-agent picker.
- Chat: invoke `/ultron-orchestrator` in Copilot Chat when skills are enabled.

Reload the VS Code window after installing. The user installer writes agents to `~/.copilot/agents` and the platform's VS Code user prompts directory. The project installer writes portable files under `.github/agents` and `.github/skills`, so committing those directories shares the setup with repository collaborators.

The installers deliberately do not overwrite existing files unless `-Force` or `--force` is supplied. The native plugin command follows Copilot CLI's own plugin cache and update behavior.

## Sharing The Package

1. Share the entire `copilot-ultron` directory as a repository, archive, or normal folder. Preserve its directory structure.
2. The recipient must have Copilot CLI or the VS Code Copilot extension and access to GPT-5.6 Sol, GPT-5.6 Terra, and GPT-5.6 Luna.
3. For CLI-only use, the recipient runs `copilot plugin install .` from the folder.
4. For CLI plus VS Code, the recipient runs the platform installer above, then restarts Copilot CLI and reloads VS Code.
5. For one repository only, use project scope and commit the generated `.github/agents` and `.github/skills` directories.

## Architecture

Edith, Ultron, and Jarvis are user-invocable leads. They can call only the three hidden Luna roles:

- `luna-code-analyst`: read-only repository analysis
- `luna-researcher`: read-only documentation and evidence research
- `luna-worker`: narrow implementation after a written plan milestone exists

Edith owns simpler work; Jarvis owns medium-complexity work; Ultron owns complex work. Each lead executes routine work directly and owns planning, architectural decisions, shared-file changes, integration, validation, and the binary completion response. Luna roles cannot delegate, always use GPT-5.6 Luna at max reasoning, and remain on default context. Complex work may use a concise plan and only the minimum subagents needed for material independent tracks.

For non-trivial implementation, the lead records the current architecture, intended design, preserved interfaces, milestone ownership, and validation in `tasks/plans/`. Independent, non-overlapping subagent tasks may run in parallel. Every Luna invocation receives exactly one detailed narrow assignment, and implementation workers must preserve the existing architecture, conventions, contracts, and focused tests.

## Differences From Codex

- Copilot custom agents use Markdown with YAML frontmatter rather than Codex TOML.
- Copilot tools and permission controls replace Codex `sandbox_mode` fields.
- Copilot does not expose Codex service tier, desktop plugin, notice, or runtime-specific browser configuration through these files.
- Fixed role-model assignments replace Copilot Auto: Edith and Luna subagents use Luna, Ultron uses Sol, and Jarvis uses Terra. Every role remains on default context.

## Validation

From the repository root:

```powershell
.\copilot-ultron\scripts\test-package.ps1
```

The check validates JSON, package paths, agent names and permissions, silent-output contracts, failure signaling, skill parity, cost defaults, installer layout, and PowerShell syntax.

## References

- [Optimize AI credit usage in VS Code](https://code.visualstudio.com/docs/agents/guides/optimize-usage)
- [Custom agents in VS Code](https://code.visualstudio.com/docs/agent-customization/custom-agents)
- [Agent skills in VS Code](https://code.visualstudio.com/docs/agent-customization/agent-skills)
- [Subagents in VS Code](https://code.visualstudio.com/docs/agents/run/subagents)
- [GitHub Awesome Copilot](https://github.com/github/awesome-copilot)
