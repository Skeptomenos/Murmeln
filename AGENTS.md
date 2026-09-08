# Murmeln

Push-to-talk dictation macOS menu bar app. Hold `Fn` to record, release to transcribe and auto-paste.

## Identity
- **Status:** poc
- **Tech:** Swift 6, SwiftUI, macOS, Apple Silicon

Read `index.md` first for project map, commands, key docs, and active planning files.

## Validation Gate (Tier 1)

Run `bash validate.sh` in full after a batch of code, build, dependency or test changes and before final implementation closeout. During development, use focused checks at the changed boundary. For documentation-only edits, run `bash check-docs.sh` and `git diff --check`; a status update or checkbox backed by valid evidence does not require another build. These project-specific frequency rules override the general method skills so unchanged work is not repeatedly validated. Stages (must match `validate.sh`):

<!-- gate-stages-begin -->
- `swift build`
- `swift test`
- `xcodebuild -project Murmeln.xcodeproj -scheme "Murmeln Dev" -configuration "Debug Dev" build`
- `bash check-docs.sh`
- `git diff --check`
<!-- gate-stages-end -->

## Runtime Validation (Tier 1.5)

`bash validate-e2e.sh` exercises the real downloaded on-device models and their app-level pipeline path. Run it after runtime/model changes; before phase or release closeout, verify that a passing run covers the final relevant source and environment. Reuse that evidence when those inputs are unchanged. It is intentionally separate from the deterministic Tier 1 gate because it depends on multi-gigabyte local model assets.

Tier 2 is the human dogfood checklist in `docs/dogfood-checklist.md` — mandatory before release/phase closeout, evidenced by `capture-diagnostics.jsonl` capture IDs.

For agent-driven recording, speaker-audio tests, or paste-delivery proof, read [the dictation test procedure](docs/agent-dictation-testing.md) first — it records working synthetic Fn routes, build prerequisites, and the evidence needed to distinguish transcription from delivery.

## Implementation Loop

Multi-step work follows the `self-correction-loop` skill (`ai-dev/_infra/skills/skills/self-correction-loop/`). Apply these project-specific overrides to validation and review frequency; retain the skill’s evidence and diagnosis requirements:

- **Evidence rule:** a checked checkbox / "done" / "tests pass" may only be claimed together with re-derivable evidence — the command run and the observed result (see the skill for the authoritative wording). Flip plan checkboxes only with an evidence line.
- **Probe first:** for behavior claims, write the failing test before the fix and watch it fail; if it fails differently than expected, record a Discovery in the active plan before fixing.
- **Regression lock:** every reproducible bug or wiring fix must add a minimal permanent test at the broken boundary, observed red before the fix and green after — this prevents recurrence; record non-automatable UI/OS cases as Tier 2 dogfood checks with diagnostics.
- **Evidence reuse:** retain accepted results with their source/build identity, relevant environment, command and observed outcome. Repeat only checks invalidated by a relevant change, contradictory evidence or missing evidence. State why a rerun is needed; a new conversation or handoff alone does not invalidate a result.
- **Same failure twice in a row → stop and re-plan**, do not iterate blindly.
- **Falsifiability:** never trust a new gate or check until you have watched it fail once (break, observe red, restore).
- **Independent verification:** obtain one fresh-context whole-change review before final PR readiness or implementation closeout, using `self-correction-loop/references/verify-plan-prompt.md`. After that, review only changes and evidence that affect its conclusions. Routine progress handoffs do not trigger another whole-change review. Disputed claims remain open.

- **Live test scope:** prepare a bounded case list and stop when its acceptance criteria pass. Choose repetition counts to test a stated reliability risk; honor explicit user requirements. Keep fresh desktop handoffs, receiver verification, clipboard preservation and safe target refusal mandatory.

## Rules
- Treat Murmeln as Apple Silicon local-first and cloud-second — cleanup and architecture should make future local-native backends first-class.
- Keep durable planning memory in repo files, not session context — use the active planning docs listed in `index.md`.
- Update only the lowest necessary planning layer — evidence goes in findings, scope/priority changes go in the roadmap, executable tasks go in the active phase plan.
- Keep one active roadmap, one active findings log, and at most one active phase plan. Keep one current acceptance checklist in the plan; mark older checkpoints as historical so superseded next steps do not cause repeated work. Archive superseded docs and repoint `index.md`.
- Reconcile truth before expansion — when docs, specs, and code drift or a feature stops earning its complexity, restore one supported story before adding more surface area.
- Use `Murmeln Dev` for dogfooding once available — routine work must not overwrite the production app.
- Preserve the recording state machine and warm-up model unless evidence shows a better design — cutoff and latency work starts with root-cause investigation.
