---
name: codex-ultron
description: Run the Ultron or Jarvis orchestration workflow with bounded Luna subagents. Use for complex implementation, architecture, debugging, refactoring, research, or coordinated agent work.
---

# Codex Ultron

## Select Lead

1. Use Ultron for complex, ambiguous, architectural, high-risk, security-sensitive, or cross-system work.
2. Use Jarvis for medium-complexity implementation, debugging, refactoring, and integration.
3. Use Edith for simple, well-scoped implementation, debugging, and maintenance work.
4. Honor an explicitly named lead.
5. Keep the selected lead responsible for integration and final acceptance.

## Execute Efficiently

1. Execute small, well-scoped work directly. Do not plan or delegate what one targeted local check can resolve.
2. Use `luna_code_analyst` only when one bounded analysis avoids material parent-context growth or parallelizes independent read work.
3. When the user explicitly asks for internet or web research, external references, current documentation, library comparisons, or proven patterns, make `luna_researcher` the first external-evidence action. Give it one bounded evidence question and any user-provided URLs, wait for its packet, and shape the plan from that evidence before filling any remaining gaps directly.
4. Use `luna_worker` only for one fully specified narrow implementation or validation milestone.
5. Run only independent, non-overlapping tasks concurrently. Never overlap writers.
6. Keep architecture, ambiguity, security decisions, shared files, integration, and final acceptance with the lead.
7. Validate with the narrowest executable check that can falsify the change.

Use Codex's native custom agents for delegation and set `agent_type` to the exact underscore Luna role name. The standalone role file supplies the child's model, reasoning effort, sandbox, and instructions. Do not emulate a role with `codex fork`, `resume`, model overrides, or copied instructions. On Codex 0.147, set `fork_turns` to `none` because that release cannot combine a custom role with a full-history fork.

Each Luna packet contains only objective, scope, starting paths, preserved interfaces, constraints, acceptance criteria, validation, output format, and output bound. Luna roles never orchestrate, spawn, delegate, or communicate with the user.

## Model Policy

Ultron uses `gpt-5.6-sol`; Jarvis uses `gpt-5.6-terra`; Edith and every Luna role use `gpt-5.6-luna`. Lead profiles and launchers use high reasoning; Luna roles use max reasoning. Profiles and launchers select lead models. Agent TOMLs select Luna models.