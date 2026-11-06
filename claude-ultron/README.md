# Claude Ultron

Ultron, Jarvis, and Edith for Claude Code, on the terminal, the desktop app, and the VS Code extension. It ports the `codex-ultron` workflow: the same leads, greetings, `0`/`1` status, caller boundaries, role packets, plan gate, and engineering principles, on Claude models.

## Model Routing

| Agent | Role | Model | Effort |
|---|---|---|---|
| `ultron` | Lead for complex, ambiguous, architectural, high-risk, security-sensitive, or cross-system work | Opus 5.5 | `xhigh` |
| `jarvis` | Lead for medium-complexity implementation, debugging, refactoring, and integration | Sonnet 5.5 | `xhigh` |
| `edith` | Lead for simple, well-scoped implementation, debugging, and maintenance | Haiku 5.5 | `max` |
| `opus-specialist` | One difficult, self-contained task beyond Sonnet. Ultron only | Opus 5.5 | `xhigh` |
| `opus-reviewer` | One independent review of one concern. No edit tools. Ultron only | Opus 5.5 | `xhigh` |
| `sonnet-worker` | Implementation, test writing, integration, and analysis beyond Haiku: medium work under Ultron, anything Jarvis assigns. Ultron and Jarvis only | Sonnet 5.5 | `xhigh` |
| `haiku-worker` | Running tests, simple test writing, simple checks, mechanical edits, simple fixes, fully specified mechanical integration | Haiku 5.5 | `max` |
| `haiku-code-analyst` | One bounded code search or question. No edit tools, and shell use is read-only by contract | Haiku 5.5 | `max` |
| `haiku-researcher` | One bounded research question. No edit tools, and shell use is read-only by contract | Haiku 5.5 | `max` |

Ultron orchestrates and takes the difficult work on Opus, gives medium work to Sonnet, and gives search and super-simple work to Haiku. Jarvis and Edith never ask for another lead: each does the work as well as its own tier can, however hard it is, and you decide when to switch. Each lead routes every step to the cheapest tier that can do it without loss of precision.

## Lead Accountability

The lead is personally responsible for everything its workers produce, and it decides what needs its own review. Really simple work can pass on the worker's packet. Everything else is treated as a claim: the lead reads the real diff, runs decisive checks itself, opens the sources its decisions rest on, and only then checks off the milestone. `0` means the lead vouches for the whole result: it has evidence for what it reviewed, and it judged the rest too simple to hold a costly mistake. A defect it cannot resolve means `1`. The full rule is the Acceptance section of each lead in [`plugins/leads/agents/`](plugins/leads/agents/). It is an instruction to the model: the runtime enforces routing, not review.

Ultron also verifies independently, so you never need to run a separate review. Before finishing a long job, and after any milestone where a hidden defect would be expensive, it sends `opus-reviewer` children at the changes, one per concern and as many as the risk needs, reproduces what they find, and repeats until a round finds nothing new. This costs extra Opus usage, which it skips on low-risk work of any size.

## What You See

Leads keep the chat short but readable. Before non-trivial work a lead writes an abstract of its plan: the goal, then one line per milestone with who does it. It adds one line when a milestone starts, when workers start or report, when a review finds a defect, and when a milestone is accepted, and it names what it waits for. It writes no reasoning or tool narration, and closes with at most five short lines and `0` or `1` on the last line.

Ultron writes its plans, reports, and worker packets in the style of ASD-STE100: short sentences, one instruction each, active voice, one word for one meaning. This is a style rule, not certified Simplified Technical English, since the official dictionary is not included, and Ultron's reasoning stays free because it needs the full language.

## Long Jobs

A long new job, one whose plan has more than one milestone, starts on a new branch named after the task. The lead commits after each accepted milestone, staging only what that milestone changed. It does not push, merge that branch into another, or open a pull request unless you ask.

## Install

Windows:

```powershell
.\scripts\install-plugin.ps1
```

Linux or macOS:

```sh
sh scripts/install-plugin.sh
```

This registers the `ultron-claude` marketplace and installs `leads@ultron-claude` at user scope. The terminal, desktop local sessions, and VS Code on one computer share that install, so it applies to all three. Run `/reload-plugins` or start a new session to load it. Use `-Scope Project -ProjectPath C:\path\to\repo` (or `--scope project --project-path /path/to/repo`) to enable it for one project instead. That enables it on this computer only, so every other computer or clone needs its own install from a checkout.

The marketplace is this folder and Claude Code reads the plugin from it in place, so a `git pull` here takes effect after `/reload-plugins`, and moving the checkout means installing again.

## Choose a Lead

The same commands work on the terminal, in the desktop app, and in the VS Code panel. The lead stays active for follow-up messages until you pick another, and each chat keeps its own. A fork of a chat keeps its lead. `/clear` drops a lead chosen in the chat; a session started on a lead stays on it.

| Do this | To |
|---|---|
| `@ultron fix the auth race` | Start or switch lead and give it the task in one message |
| `/ultron fix the auth race` | The same, from the `/` menu (listed as `leads:ultron`) |
| `/jarvis` alone | Switch lead, and wait for the task |
| `/lead-off` | Return to the session's own model and agents |

`@jarvis` and `@edith` work the same way. A mention counts at the start of a line, outside code fences, indented code, and IDE selections, and the first one wins, so a pasted thread below it stays part of the task. Anywhere else it selects nobody, and a notice says so. A file, a folder, or your own agent of the same name keeps the bare mention, and `@leads:jarvis` still selects the lead. On the terminal `@jarvis` alone also switches lead. In the desktop and VS Code composers the `@` menu lists files, so for a bare switch type `@jarvis`, a space, then Enter, or use `/jarvis`.

A mention typed while a turn is running takes effect when Claude Code delivers it, and taking the message back before then changes nothing. Workers already running keep their own tier when the lead changes.

While a lead is active, a line above the prompt shows what is really running, such as `Ultron · Opus 5.5 · xhigh`. If another plugin's band holds that place, the same text appears as a status line under the prompt, with Claude Code's `⚠ leads:` prefix.

On a terminal you can also start a session already on a lead:

```sh
claude --agent ultron
```

The launchers do the same with fixed model and effort, and offer a menu when no lead is named. They print the lead's greeting at start, and the model opens its first reply with it too, as in `codex-ultron`:

```powershell
.\scripts\start-claude.ps1
.\scripts\start-ultron.ps1 -Prompt "Design and implement the requested system"
.\scripts\start-jarvis.ps1 -WorkingDirectory C:\path\to\repo
```

```sh
sh scripts/start-claude.sh
sh scripts/start-ultron.sh "Design and implement the requested system"
sh scripts/start-jarvis.sh --cd /path/to/repo
```

To give one project a default lead, set `agent` in its `.claude/settings.local.json`. New chats there start on that lead on every surface, and older chats stay as they were:

```json
{ "agent": "leads:jarvis" }
```

## How It Works

The agents alone cannot do this everywhere: the VS Code panel has no agent selector, the desktop app's picker lists no plugin agents and always passes its own `--model`, and `effort:` frontmatter is ignored for a main-thread agent. A subagent cannot be the lead either, because its worker allowlist would not apply. So the plugin adds a small runtime in [`plugins/leads/hooks/`](plugins/leads/hooks/), a Claude Code mod that the engine runs itself, with no Node or Python needed:

- It remembers each session's lead across follow-ups, compaction, resume, and forks.
- It pins the lead's model and effort on every main-loop request, and on a forked skill, which has no agent file to set them. Workers keep the model and effort in their own files, and direct workers keep them even under `CLAUDE_CODE_EFFORT_LEVEL`. A commit's trailer names the lead's model, for the whole session.
- It offers each lead only its own workers, with no limit on how many run at once, and refuses every other `Agent` call, including forks, built-in agents, and per-call `model` or `effort` overrides. Ultron can also run workflows for large fan-outs and verification loops, each agent told to use one of its worker types. Jarvis and Edith cannot, because a workflow's agents could run above their tier.
- It stops a worker or forked skill whose model request stays silent for five minutes, because a waiting lead wakes only on a notification and stopping the worker sends one. Long-running tools do not count as silence.
- It hides the plugin's agents from plain sessions, and the lead skills are not shown to the model, so a chat with no lead pays nothing for them.

Workers have no `Agent`, `Skill`, `SendMessage`, or `TaskStop` tool, because a forked skill is a nested agent and waking a sibling is delegation, so nothing runs below them. A lead puts what a skill says into the worker's packet.

Leads deliberately have no `tools:` allowlist in their files. `Agent(...)` needs one, and it cannot express "every MCP server", so it would cost them the browser and every other MCP tool.

The plugin is named `leads` rather than `ultron` because the desktop's `/` menu highlights the shortest name that starts with what you typed, so `/ultron` would pick `ultron:edith`.

## Limits

- **The mod API is early access.** Rerun `scripts/test-runtime.py` after a Claude Code update. If the runtime stops loading, `--agent` and `/leads:ultron` still work, but delegation limits then rest on the contracts and the workers' caller checks, as in `codex-ultron`; `--agent` keeps the agent's model without its effort, and skills keep the chat's model.
- **A model you pick mid-chat stands.** The lead's pin holds while the session's own model stays what it was when the process started, so reopening a chat on another surface keeps the lead. If you change the picker, or the engine's safety classifier falls back to another model (Opus 5.5 to Opus 4.8 on flagged cybersecurity content, say), that model is used and the line above the prompt names it, though the contract text still names the lead's tier. Select the lead again to pin it again. `opusplan` counts as such a pick on its plan steps. While the pin holds, `/effort` changes nothing: pick another model or run `/lead-off` first.
- **The GUI picker shows the session's model, not the lead's.** Read the line above the prompt instead. Chat titles run on the session's model too.
- **Compaction summaries run on the session's model.** Those requests never reach the runtime, and the summary is all a lead continues from. So a lead above its session's model loses some precision there, which is why the runtime tells the summariser to keep the plan's path and milestone, running children, and unverified claims. For long work on Ultron, start from its launcher or `--agent ultron --model claude-opus-5-5`, which put the session on the lead's own model.
- **A session started on a lead keeps its system prompt.** `/lead-off` under `--agent`, a launcher, or the `agent` setting stops the pin and the worker limits, and tells the model to drop the contract, but the runtime cannot remove the prompt itself or a launcher's `--model`. Start a new chat for a truly plain session.
- **Some moves leave a lead to reselect.** After rewinding a chat past its selection the pin stays but the contract is gone, and a terminal `--fork-session` of an `--agent` chat needs `--agent` again. Name the lead again to restore it.
- **A terminal cannot tell `--agent` from an inherited variable.** Claude Code passes `CLAUDE_CODE_AGENT` down to shell commands. A `claude -p` run from a lead's shell stays plain, but a terminal session started by hand from such a shell counts as that lead, with no contract. Start it from a clean shell.
- **Agent rows appear where they do nothing.** The terminal's `@` list shows Claude Code's own `leads:* (agent)` rows mid-line and in plain chats, and the runtime cannot filter those. Only a row at the start of a line selects.
- **Browsers are off unless you enable them.** Chrome integration needs `--chrome`, `/chrome`, or `claudeInChromeDefaultEnabled`. Without it, leads and workers fall back to project-local Playwright.
- **Permissions are yours to set.** The desktop and VS Code panels use their own mode picker. The launchers default to `--permission-mode auto` rather than the full-access default of `codex-ultron`; set `CLAUDE_ULTRON_PERMISSION_MODE` to any mode the CLI accepts, such as `bypassPermissions`, to change that.
- **Replies beyond `0` and `1`.** A question gets an answer, since a bare status would swallow it. A blocker is `1` plus one line, such as `1 Blocked: <reason>`, since a bare `1` would not say why. A lead waiting on a worker ends its turn by naming what it waits for, since Claude Code answers an empty turn with a prompt that costs a full request.
- **A workflow's agents sit outside some guards.** An agent with no `agentType` runs on the session's model and effort, which the contract tells Ultron to avoid. `CLAUDE_CODE_EFFORT_LEVEL` overrides their effort, and the five-minute stall stop does not reach them. A workflow also runs at most min(16, CPUs - 2) agents at once and queues the rest, up to 1000 in a run, while direct calls have no such limit.
- **Worktree workers start from `origin`'s default branch.** That is Claude Code's default, so the contract has each one fast-forward to the job branch first. Setting `worktree.baseRef` to `head` also works.
- Model IDs are pinned to the 5.5 releases, so a later model means updating the agent files, `hooks/leads.ts`, the launchers, both check scripts, and `plugins/leads/tests/`.

## Package Layout

- `.claude-plugin/marketplace.json`: the `ultron-claude` marketplace
- `plugins/leads/agents/`: three leads and six workers
- `plugins/leads/hooks/`: the lead runtime; `leads.ts` holds each lead's model, effort, and workers
- `plugins/leads/skills/`: `/ultron`, `/jarvis`, `/edith`, `/lead-off`
- `plugins/leads/references/chat-activation.md`: what selecting a lead means, shared by every route
- `plugins/leads/tests/`: the runtime's unit tests
- `plugins/leads/tsconfig.json`: written by Claude Code for editors, and kept; `.claude-plugin/types/` beside the manifest is generated and ignored
- `scripts/`: installers, launchers, and checks

## Validate

```powershell
.\scripts\test-package.ps1
```

```sh
python scripts/test-runtime.py
```

`test-package.ps1` checks the contracts, routing tables, launchers, manifests, `claude plugin validate`, `claude plugin test`, and a disposable install, and warns when `claude` or `sh` is missing and those checks were skipped. `test-runtime.py` drives a real Claude Code binary against a local fake API, with a dummy key and a throwaway config, and reads the routing off the requests it sends, including the launch shapes of the desktop app and the VS Code panel and, on Windows, a real terminal session through ConPTY. It spends no tokens. Pass a binary path to test another install, such as the one bundled with the VS Code extension.
