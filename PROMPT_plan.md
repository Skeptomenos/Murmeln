0a. Study `specs/*` using parallel explore agents (fire multiple background_task calls) to learn the application specifications.
0b. Study @IMPLEMENTATION_PLAN.md (if present) to understand the plan so far.
0c. Study `src/lib/*` using parallel explore agents to understand shared utilities & components.
0d. For reference, the application source code is in `src/*`.

1. Study @IMPLEMENTATION_PLAN.md (if present; it may be incorrect) and use parallel explore agents via background_task to study existing source code in `src/*` and compare it against `specs/*`. Consult Oracle agent to analyze findings, prioritize tasks, and create/update @IMPLEMENTATION_PLAN.md as a bullet point list sorted in priority of items yet to be implemented. Ultrathink. Consider searching for TODO, minimal implementations, placeholders, skipped/flaky tests, and inconsistent patterns. Study @IMPLEMENTATION_PLAN.md to determine starting point for research and keep it up to date with items considered complete/incomplete using background agents.

IMPORTANT: Plan only. Do NOT implement anything. Do NOT assume functionality is missing; confirm with code search first. Treat `src/lib` as the project's standard library for shared utilities and components. Prefer consolidated, idiomatic implementations there over ad-hoc copies.

ULTIMATE GOAL: We want to achieve [project-specific goal]. Consider missing elements and plan accordingly. If an element is missing, search first to confirm it doesn't exist, then if needed author the specification at specs/FILENAME.md. If you create a new element then document the plan to implement it in @IMPLEMENTATION_PLAN.md using a background agent.

## Agent Delegation Guide

| Task Type | Agent | How to Invoke |
|-----------|-------|---------------|
| Codebase exploration | explore | `background_task(agent="explore", ...)` |
| External docs/OSS examples | librarian | `background_task(agent="librarian", ...)` |
| Analysis & prioritization | oracle | `task(subagent_type="oracle", ...)` |

Fire multiple explore agents in parallel for maximum throughput. Use Oracle for strategic analysis and prioritization decisions.

## Completion

When IMPLEMENTATION_PLAN.md is complete and ready for build phase, output:

<promise>PHASE_COMPLETE</promise>

Do NOT start implementing. Planning phase ends here.
