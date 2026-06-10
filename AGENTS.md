# Murmeln

Push-to-talk dictation macOS menu bar app. Hold `Fn` to record, release to transcribe and auto-paste.

## Identity
- **Status:** poc
- **Tech:** Swift 6, SwiftUI, macOS, Apple Silicon

Read `index.md` first for project map, commands, key docs, and active planning files.

## Validation Gate (Tier 1)

`bash validate.sh` is the single validation gate — run it in full before flipping any plan checkbox, committing a step, or claiming "done". Never substitute a subset for the full gate. Stages (must match `validate.sh`):

<!-- gate-stages-begin -->
- `swift build`
- `swift test`
- `xcodebuild -project Murmeln.xcodeproj -scheme "Murmeln Dev" -configuration "Debug Dev" build`
- `bash check-docs.sh`
- `git diff --check`
<!-- gate-stages-end -->

Tier 2 is the human dogfood checklist in `docs/dogfood-checklist.md` — mandatory before release/phase closeout, evidenced by `capture-diagnostics.jsonl` capture IDs.

## Implementation Loop

Multi-step work follows the `self-correction-loop` skill (`ai-dev/_infra/skills/skills/self-correction-loop/`). The non-negotiables:

- **Evidence rule:** a checked checkbox / "done" / "tests pass" may only be claimed together with re-derivable evidence — the command run and the observed result (see the skill for the authoritative wording). Flip plan checkboxes only with an evidence line.
- **Probe first:** for behavior claims, write the failing test before the fix and watch it fail; if it fails differently than expected, record a Discovery in the active plan before fixing.
- **Full gate before every checkbox:** `bash validate.sh`, never a subset.
- **Same failure twice in a row → stop and re-plan**, do not iterate blindly.
- **Falsifiability:** never trust a new gate or check until you have watched it fail once (break, observe red, restore).
- **Independent verification:** before every PR/handoff, a fresh-context session that did not write the code re-derives all checkbox claims using `self-correction-loop/references/verify-plan-prompt.md` (`<GATE>` = `bash validate.sh`). Disputed claims re-enter the plan as open steps.

## Rules
- Treat Murmeln as Apple Silicon local-first and cloud-second — cleanup and architecture should make future local-native backends first-class.
- Keep durable planning memory in repo files, not session context — use the active planning docs listed in `index.md`.
- Update only the lowest necessary planning layer — evidence goes in findings, scope/priority changes go in the roadmap, executable tasks go in the active phase plan.
- Keep one active roadmap, one active findings log, and at most one active phase plan — archive superseded docs and repoint `index.md` instead of keeping parallel "current" files.
- Reconcile truth before expansion — when docs, specs, and code drift or a feature stops earning its complexity, restore one supported story before adding more surface area.
- Use `Murmeln Dev` for dogfooding once available — routine work must not overwrite the production app.
- Preserve the recording state machine and warm-up model unless evidence shows a better design — cutoff and latency work starts with root-cause investigation.
