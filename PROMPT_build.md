## CRITICAL: Task-by-Task Execution Rule

**You must work on ONE TASK at a time, verify it, then move to the next. After completing your current PHASE, STOP.**

### Workflow for Each Phase:

1. **Create todos** — Break the phase into individual tasks using the TodoWrite tool
2. **For each task:**
   - Mark the task as `in_progress`
   - Implement ONLY that task (one file change or one logical unit)
   - Run `swift build` or equivalent to verify it compiles
   - Run tests if applicable
   - Mark the task as `completed`
3. **After ALL tasks in the phase are done:**
   - Commit and push your changes
   - Update @IMPLEMENTATION_PLAN.md to mark the phase complete
   - Create a git tag if tests pass
   - Output `<promise>PHASE_COMPLETE</promise>`
   - **STOP IMMEDIATELY**

### DO NOT:
- **DO NOT** edit multiple files before running a build
- **DO NOT** start the next task before verifying the current one compiles
- **DO NOT** continue to the next phase after completing your current phase
- **DO NOT** expand scope mid-phase (stick to the tasks you defined)

The loop will restart you with fresh context for the next phase.

---

0a. **Detect project structure first**: Run `ls` to identify the source directory (could be `src/`, `Sources/`, `lib/`, `app/`, etc.) and test directory (`tests/`, `Tests/`, `test/`, `__tests__/`, etc.). Use the actual directory names in all subsequent searches.
0b. Study `specs/*` using parallel explore agents (fire multiple background_task calls) to learn the application specifications.
0c. Study @IMPLEMENTATION_PLAN.md.

1. Your task is to implement functionality per the specifications. Follow @IMPLEMENTATION_PLAN.md and choose the SINGLE most important phase to address. Break it into tasks using TodoWrite. Complete ONE task at a time, verifying each before moving on. Before making changes, search the codebase (don't assume not implemented) using explore agents via background_task. Fire multiple explore agents in parallel for searches/reads. Use the primary agent for build/test operations. Consult Oracle agent when complex reasoning is needed (debugging, architectural decisions, when stuck after 2+ attempts).
2. After implementing each task, run build and tests to verify. If functionality is missing then it's your job to add it as per the application specifications. Ultrathink.
3. When you discover issues, immediately update @IMPLEMENTATION_PLAN.md with your findings using a background agent. When resolved, update and remove the item.
4. When all tasks in the phase pass tests, update @IMPLEMENTATION_PLAN.md, then `git add -A` then `git commit` with a message describing the changes. After the commit, `git push`.

99999. Important: When authoring documentation, capture the why — tests and implementation importance.
999999. Important: Single sources of truth, no migrations/adapters. If tests unrelated to your work fail, resolve them as part of the increment.
9999999. As soon as there are no build or test errors create a git tag. If there are no git tags start at 0.0.0 and increment patch by 1 for example 0.0.1  if 0.0.0 does not exist.
99999999. You may add extra logging if required to debug issues.
999999999. Keep @IMPLEMENTATION_PLAN.md current with learnings using a background agent — future work depends on this to avoid duplicating efforts. Update especially after finishing your turn.
9999999999. When you learn something new about how to run the application, update @AGENTS.md using a background agent but keep it brief. For example if you run commands multiple times before learning the correct command then that file should be updated.
99999999999. For any bugs you notice, resolve them or document them in @IMPLEMENTATION_PLAN.md using a background agent even if it is unrelated to the current piece of work.
999999999999. Implement functionality completely. Placeholders and stubs waste efforts and time redoing the same work.
9999999999999. When @IMPLEMENTATION_PLAN.md becomes large periodically clean out the items that are completed from the file using a background agent.
99999999999999. If you find inconsistencies in the specs/* then consult Oracle agent to analyze and update the specs.
999999999999999. IMPORTANT: Keep @AGENTS.md operational only — status updates and progress notes belong in `IMPLEMENTATION_PLAN.md`. A bloated AGENTS.md pollutes every future loop's context.

## Agent Delegation Guide

| Task Type | Agent | How to Invoke |
|-----------|-------|---------------|
| Codebase exploration | explore | `background_task(agent="explore", ...)` |
| External docs/OSS examples | librarian | `background_task(agent="librarian", ...)` |
| Complex reasoning/debugging | oracle | `task(subagent_type="oracle", ...)` |
| Frontend UI/UX work | frontend-ui-ux-engineer | `task(subagent_type="frontend-ui-ux-engineer", ...)` |
| Documentation writing | document-writer | `task(subagent_type="document-writer", ...)` |

Fire multiple explore/librarian agents in parallel for maximum throughput. Use Oracle sparingly (expensive but powerful).

## Error Recovery Protocol

If tests fail after 3 fix attempts on the same issue:
1. Document the failure in @IMPLEMENTATION_PLAN.md under "## Blocked"
2. Move to the next highest priority task
3. Do NOT spin on the same error indefinitely

If you cannot make progress after 15 minutes of attempts:
1. Document what you tried in @IMPLEMENTATION_PLAN.md
2. Output the blocked signal (see below)

## Completion Signals

**After completing ONE phase** (not all phases — just the current one):
```
<promise>PHASE_COMPLETE</promise>
```

When ALL tasks in @IMPLEMENTATION_PLAN.md are marked complete and verified:
```
<promise>COMPLETE</promise>
```

If stuck after 3 attempts on the same task, or 15 minutes with no progress:
```
<promise>BLOCKED:[task description]:[reason]</promise>
```

Example: `<promise>BLOCKED:Fix auth middleware:Cannot reproduce error locally</promise>`
