# Murmeln Findings Log

> Active evidence log for the current roadmap. Archive this file when the linked roadmap is completed or superseded.

## Scope

- **Roadmap:** `docs/plans/2026-03-28-murmeln-plan.md`
- **Router:** `index.md`
- **Linear:** `DEV-33`

## Entry Format

Use this shape for future entries:

```md
### YYYY-MM-DD - Short title
- Area:
- Confidence:
- Evidence:
- Impact:
- Next step:
```

## Findings

### 2026-03-28 - Repo truth is split across docs and code
- Area: documentation / roadmap hygiene
- Confidence: high
- Evidence:
  - `README.md`
  - `specs/README.md`
  - `IMPLEMENTATION_PLAN.md`
- Impact: execution sessions can be misled about feature state, version state, and project maturity.
- Next step: resolve this in Phase 0 truth pass.

### 2026-03-28 - WhisperKit lane appears split-brain and incomplete
- Area: local transcription architecture
- Confidence: high
- Evidence:
  - `Sources/Services/WhisperKitService.swift`
  - `Sources/Views/WhisperKitSetupView.swift`
  - `Sources/Models/AppSettings.swift`
- Impact: the local-transcription story is unclear and likely misleading.
- Next step: explicitly decide whether to quarantine, remove, or revisit this lane later.

### 2026-03-28 - Ending cutoff still affects real usage despite prior fix attempt
- Area: capture correctness
- Confidence: medium-high
- Evidence:
  - user daily-use report
  - `docs/audio-cutoff-fix.md`
  - `docs/audio-pipeline.md`
- Impact: Murmeln is not yet trustworthy enough for daily-driver dictation.
- Next step: instrument and reproduce in Phase 1 before proposing fixes.

### 2026-03-28 - User-reported priorities center on trust, speed, and simplicity
- Area: product direction
- Confidence: high
- Evidence:
  - user reports: ending cutoff, rare beginning cutoff, word confusion, crashes, ugly UI, slow processing, prompt/refinement frustration
- Impact: reliability and speed must outrank UI polish and advanced features in early phases.
- Next step: keep Phases 0 and 1 ahead of redesign work.

### 2026-03-28 - Local-first Apple Silicon strategy is now explicit
- Area: platform strategy
- Confidence: high
- Evidence:
  - user direction in planning session
- Impact: Intel compatibility is no longer a planning constraint and cloud should not shape the primary architecture.
- Next step: ensure future refactors support local-native backends as first-class citizens.

### 2026-03-28 - Future local backend target is Cohere Transcribe via MLX
- Area: future backend architecture
- Confidence: high
- Evidence:
  - user direction
  - `https://huggingface.co/CohereLabs/cohere-transcribe-03-2026`
  - `https://github.com/Blaizzy/mlx-audio`
- Impact: backend design must support explicit language handling, Apple Silicon local-native inference, and likely VAD/noise-gate support.
- Next step: treat this as an architectural constraint now, and an implementation target later.

### 2026-03-28 - Safe dogfooding requires a separate dev app
- Area: development workflow
- Confidence: high
- Evidence:
  - user report that replacing the production app caused major friction
- Impact: routine iteration should not depend on overwriting the daily-driver installation.
- Next step: add `Murmeln Dev` in the safe dogfooding phase.
