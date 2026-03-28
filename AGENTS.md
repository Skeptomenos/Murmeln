# Murmeln

Push-to-talk dictation macOS menu bar app. Hold `Fn` to record, release to transcribe and auto-paste.

## Identity
- **Status:** poc
- **Tech:** Swift 6, SwiftUI, macOS, Apple Silicon

Read `index.md` first for project map, commands, key docs, and active planning files.

## Rules
- Treat Murmeln as Apple Silicon local-first and cloud-second — cleanup and architecture should make future local-native backends first-class.
- Keep durable planning memory in repo files, not session context — use the active planning docs listed in `index.md`.
- Update only the lowest necessary planning layer — evidence goes in findings, scope/priority changes go in the roadmap, executable tasks go in the active phase plan.
- Keep one active roadmap, one active findings log, and at most one active phase plan — archive superseded docs and repoint `index.md` instead of keeping parallel "current" files.
- Reconcile truth before expansion — when docs, specs, and code drift or a feature stops earning its complexity, restore one supported story before adding more surface area.
- Use `Murmeln Dev` for dogfooding once available — routine work must not overwrite the production app.
- Preserve the recording state machine and warm-up model unless evidence shows a better design — cutoff and latency work starts with root-cause investigation.
