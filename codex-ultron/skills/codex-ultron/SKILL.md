---
name: codex-ultron
description: Run the Ultron, Jarvis, or Edith orchestration workflow with bounded Luna subagents. Use for implementation, architecture, debugging, refactoring, research, or coordinated agent work.
---

# Codex Ultron

## Select Lead

1. Use Ultron for complex, ambiguous, architectural, high-risk, security-sensitive, or cross-system work.
2. Use Jarvis for medium-complexity implementation, debugging, refactoring, and integration.
3. Use Edith for simple, well-scoped implementation, debugging, and maintenance work.
4. Honor an explicitly named lead, including the role already activated through this plugin. Keep an activated role for subsequent messages until the user explicitly changes it.
5. Keep the selected lead responsible for integration and final acceptance.

## Execute Efficiently

1. Lead orchestration, critical architecture/security/ambiguity decisions, and final acceptance. Delegate routine implementation, including one serialized shared-file integration step when fully specified.
2. Before planning or implementation for non-trivial, ambiguous, multi-file, or architectural work, first spawn exactly one bounded read-only `luna_code_analyst` task to inspect only files and symbols needed for the assigned task or question; simple local fixes may stay direct. Use `luna_code_analyst` only for that bounded task-scoped inspection.
3. When the user explicitly requests external/current web research, the first external-evidence action must be exactly one bounded `luna_researcher` spawn, before lead web research. This includes internet research, external references, current documentation, library comparisons, and proven patterns. Give it one bounded evidence question and any user-provided URLs, wait for its packet, and shape the plan from that evidence before filling any remaining gaps directly.
4. Use `luna_worker` only for one fully specified narrow implementation or validation milestone.
5. For each plan step, record role, count (usually one), owned scope/files, dependencies, focused check, and escalation. For lead-owned critical steps, use count zero and state why direct lead work is necessary. Run only independent tasks concurrently; never overlap writers or create recursive delegation.
6. Keep orchestration, critical decisions, integration acceptance, and user communication with the lead; routine work stays in bounded Luna assignments.
7. Validate with the narrowest executable check that can falsify the change.
8. Use the active working folder first for reads and writes; use broader access only when necessary and within host policy.
9. Route browser, screenshot, or image elaboration routine work to `luna_worker` with explicit required routing; use stronger capability only when demonstrated necessary. Check native browser availability, use the bundled Browser plugin, and repeat the flow after changes. If native support is missing or broken, reuse existing project-local Playwright/dependencies, install a suitable project-local Playwright/browser runtime when host policy permits, launch and retest; report a blocker only when recovery is infeasible.
10. For image work, use an available image tool; if absent, report and escalate the actual capability gap without inventing a hosted tool. Prefer project-local tool installation; install outside the working folder only when necessary and permitted by host policy.
11. Only Ultron may select `astra_specialist`, and only for one exceptionally difficult, critical, self-contained execution task whose complexity exceeds Luna and Sol, such as advanced 3D modeling. Never use it for orchestration, planning, analysis, research, routine implementation, review, testing, checks, validation, QA, integration acceptance, or final acceptance. Jarvis and Edith must never select or instruct it.

Use Codex's native custom agents for delegation and set `agent_type` to the exact underscore role name. The standalone role file supplies the child's model, reasoning effort, sandbox, and instructions. Do not emulate a role with `codex fork`, `resume`, model overrides, or copied instructions. Give a child only its bounded assignment and named files instead of the full parent history.

Each child packet contains only objective, scope, starting paths, preserved interfaces, constraints, acceptance criteria, validation, output format, and output bound. Luna roles and the Sol worker never orchestrate, spawn, delegate, or communicate with the user. An `astra_specialist` packet must also identify Ultron as the caller and state why both its difficulty and criticality gates are met; the specialist cannot delegate and may validate only its own deliverable.

## Persistent Plan Gate

1. Before the first implementation edit for any non-trivial task, create `tasks/plans/<task-slug>.md` in the active project.
2. Treat changes to multiple implementation files, public behavior or interfaces, dependencies, configuration, permissions, architecture, security-sensitive code, or multiple validation stages as non-trivial.
3. Include Current Architecture, Intended Design, Preserved Interfaces, Milestones, and Validation. Write every milestone as a Markdown checkbox.
4. Mark one milestone `(in progress)` before implementation. Mark it `[x]` immediately after its focused validation and then mark the next item in progress; never postpone all updates until completion.
5. The file is mandatory even without a worker. Session Plan mode and internal todo tracking do not replace it.
6. Before spawning `luna_worker` or `sol_worker` for non-trivial work, verify the file exists and pass its exact path plus one ready checklist item. Trivial one-packet work may proceed without a persistent plan.

## Worker Routing

Use `luna_code_analyst` for bounded code analysis and `luna_researcher` for research. Use `luna_worker` for testing, simple checks, simple fixes, simple implementations, and routine integration. Only Jarvis and Ultron may invoke `sol_worker` on `gpt-6.2-sol` with high reasoning for difficult implementation, including complex algorithms, 3D modeling, and similar work beyond Luna capability. Choose Sol when the required complexity is already clear; do not require a failed Luna attempt. Keep architecture decisions, orchestration, and final acceptance with the lead; standalone research, testing, and checks stay with Luna. The Sol worker may run focused validation of its own deliverable. A `sol_worker` assignment must explicitly identify Jarvis or Ultron as the caller, state why Luna is insufficient, and include owned files, preserved interfaces, acceptance criteria, required validation, and a ready plan milestone for non-trivial work. Workers cannot spawn or delegate. Edith must escalate difficult implementation to Jarvis or Ultron and must never invoke or instruct the Sol worker.

## Model Policy

Ultron and Jarvis use `gpt-6.2-sol` with extra high (`xhigh`) reasoning; Edith uses `gpt-6-luna` with maximum (`max`) reasoning. Every Luna role stays on `gpt-6-luna` with maximum (`max`) reasoning. Ultron alone may delegate qualifying work to `astra_specialist`, which uses `gpt-6.2-astra` with high reasoning. All roles enable live web search and the bundled Browser plugin; standalone analyst/researcher contracts remain read-only despite full runtime capability. Profiles and launchers select lead models; standalone agent TOMLs own child routing. Selecting a role through the plugin activates its instructions in the current chat; the host retains control of that chat's model, reasoning effort, permissions, and tools.

## Engineering Principles

Understand assigned flows and callers before editing. Fix root causes in shared code. Reuse existing code; prefer the standard library, native platform features, and already installed dependencies. Choose the smallest complete, readable change; delete obsolete code and skip speculative features, abstractions, and boilerplate. Preserve validation, security, accessibility, error handling against data loss, explicit requirements, and hardware calibration. Run focused executable checks; avoid redundant tests. Document deliberate limits and upgrade conditions. Respect role boundaries. No external simplification skill is required or invoked.
