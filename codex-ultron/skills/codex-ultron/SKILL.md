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

Delegation is available from the primary Codex thread. Use the native Codex subagent tool, spawn a fresh child thread with `fork_turns` set to `none`, and set `agent_type` to the exact underscore role name. Never use `codex fork`, `resume`, or a full-history fork for role delegation: full-history forks inherit the parent agent type and cannot select a Luna role. A lead running as a subagent does not receive the native spawn tool, so it must complete its assigned task without attempting nested delegation; fan out Luna work from the primary lead instead.

Each Luna packet contains only objective, scope, starting paths, preserved interfaces, constraints, acceptance criteria, validation, output format, and output bound. Luna roles never orchestrate, spawn, delegate, or communicate with the user.

## Model Policy

Ultron uses `gpt-5.6-sol`; Jarvis uses `gpt-5.6-terra`; Edith and every Luna role use `gpt-5.6-luna`. Lead profiles and launchers use high reasoning; Luna roles use max reasoning. Profiles and launchers select lead models. Agent TOMLs select Luna models.