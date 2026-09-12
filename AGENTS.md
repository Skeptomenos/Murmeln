# Murmeln

Push-to-talk dictation macOS menu bar app. Hold `Fn` to record, release to transcribe and auto-paste.

## Identity
Ownership-ID: Personal
- **Tech:** Swift 6, SwiftUI, macOS, Apple Silicon

Read `index.md` first for project map, commands, key docs, and active planning files.

## Validation Gate (Tier 1)

Run `bash validate.sh` in full after a batch of code, build, dependency or test changes and before final implementation closeout. During development, use focused checks at the changed boundary. For documentation-only edits, run `bash check-docs.sh` and `git diff --check`; a status update or checkbox backed by valid evidence does not require another build. Stages (must match `validate.sh`):

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

- **Live test scope:** prepare a bounded case list and stop when its acceptance criteria pass. Choose repetition counts to test a stated reliability risk; honor explicit user requirements. Keep fresh desktop handoffs, receiver verification, clipboard preservation and safe target refusal mandatory.

## Rules
- Treat Murmeln as Apple Silicon local-first and cloud-second — cleanup and architecture should make future local-native backends first-class.
- Reconcile truth before expansion — when docs, specs, and code drift or a feature stops earning its complexity, restore one supported story before adding more surface area.
- Use `Murmeln Dev` for dogfooding once available — routine work must not overwrite the production app.
- Preserve the recording state machine and warm-up model unless evidence shows a better design — cutoff and latency work starts with root-cause investigation.
