---
name: codex-ultron
description: Run the Ultron, Jarvis, or Edith orchestration workflow with bounded Luna subagents. Use for implementation, architecture, debugging, refactoring, research, or coordinated agent work.
---

# Codex Ultron

## Select Lead

1. Use Ultron for complex, ambiguous, architectural, high-risk, security-sensitive, or cross-system work.
2. Use Jarvis for medium-complexity implementation, debugging, refactoring, and integration.
3. Use Edith for simple, well-scoped implementation, debugging, and maintenance work.
4. Honor an explicitly named lead.
5. Keep the selected lead responsible for integration and final acceptance.

## Execute Efficiently

1. Lead orchestration, critical architecture/security/ambiguity decisions, and final acceptance. Delegate routine implementation, including one serialized shared-file integration step when fully specified.
2. Use `luna_code_analyst` only when one bounded analysis avoids material parent-context growth or parallelizes independent read work.
3. When the user explicitly asks for internet or web research, external references, current documentation, library comparisons, or proven patterns, make `luna_researcher` the first external-evidence action. Give it one bounded evidence question and any user-provided URLs, wait for its packet, and shape the plan from that evidence before filling any remaining gaps directly.
4. Use `luna_worker` only for one fully specified narrow implementation or validation milestone.
5. For each plan step, record role, count (usually one), owned scope/files, dependencies, focused check, and escalation. For lead-owned critical steps, use count zero and state why direct lead work is necessary. Run only independent tasks concurrently; never overlap writers or create recursive delegation.
6. Keep orchestration, critical decisions, integration acceptance, and user communication with the lead; routine work stays in bounded Luna assignments.
7. Validate with the narrowest executable check that can falsify the change.
8. Use the active working folder first for reads and writes; use broader access only when necessary and within host policy.
9. Route browser, screenshot, or image elaboration routine work to `luna_worker` with explicit required routing; use stronger capability only when demonstrated necessary. Check native browser availability, use the bundled Browser plugin, and repeat the flow after changes. If native support is missing or broken, reuse existing project-local Playwright/dependencies, install a suitable project-local Playwright/browser runtime when host policy permits, launch and retest; report a blocker only when recovery is infeasible.
10. For image work, use an available image tool; if absent, report and escalate the actual capability gap without inventing a hosted tool. Prefer project-local tool installation; install outside the working folder only when necessary and permitted by host policy.

Use Codex's native custom agents for delegation and set `agent_type` to the exact underscore Luna role name. The standalone role file supplies the child's model, reasoning effort, sandbox, and instructions. Do not emulate a role with `codex fork`, `resume`, model overrides, or copied instructions. Give a child only its bounded assignment and named files instead of the full parent history.

Each Luna packet contains only objective, scope, starting paths, preserved interfaces, constraints, acceptance criteria, validation, output format, and output bound. Luna roles never orchestrate, spawn, delegate, or communicate with the user.

## Persistent Plan Gate

1. Before the first implementation edit for any non-trivial task, create `tasks/plans/<task-slug>.md` in the active project.
2. Treat changes to multiple implementation files, public behavior or interfaces, dependencies, configuration, permissions, architecture, security-sensitive code, or multiple validation stages as non-trivial.
3. Include Current Architecture, Intended Design, Preserved Interfaces, Milestones, and Validation. Write every milestone as a Markdown checkbox.
4. Mark one milestone `(in progress)` before implementation. Mark it `[x]` immediately after its focused validation and then mark the next item in progress; never postpone all updates until completion.
5. The file is mandatory even without a worker. Session Plan mode and internal todo tracking do not replace it.
6. Before spawning `luna_worker` for non-trivial work, verify the file exists and pass its exact path plus one ready checklist item. Trivial one-packet work may proceed without a persistent plan.

## Model Policy

Ultron uses `gpt-6-astra` with medium reasoning; Jarvis uses `gpt-5.6-sol` with high reasoning; Edith uses `gpt-5.6-luna` with maximum (`xhigh`) reasoning. Every Luna role stays on `gpt-5.6-luna` with maximum (`xhigh`) reasoning. All roles enable live web search and the bundled Browser plugin; standalone analyst/researcher contracts remain read-only despite full runtime capability. Profiles and launchers select lead models; standalone agent TOMLs own Luna routing.
