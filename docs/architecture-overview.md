# Murmeln Architecture Overview

> Short current-state map for Murmeln. Use this as the first technical overview. For deeper flow detail, see `docs/audio-pipeline.md` and `docs/state-machine-diagram.md`.

## Mission

Murmeln turns spoken thought into pasted text with as little friction as possible. The product aims to feel trustworthy, fast, and invisible in daily use: hold a key, speak, release, keep typing.

The long-term direction is Apple-Silicon-local-first. Cloud and local-server backends remain supported, but they should not define the primary architecture.

## Current Supported State

- The installed `/Applications/Murmeln.app` currently supports WhisperKit on-device transcription.
- The app also supports cloud transcription providers and local-server transcription via `Local Whisper Server`.
- Refinement is a separate layer and can use cloud providers, Ollama, or be skipped entirely with Raw Mode.
- The checked-in Xcode project now builds both `Murmeln` and `Murmeln Dev`, and the touched reliability test suites pass with the restored WhisperKit dependency path.
- Full `swift test` still has a known unrelated failure in `RefinementTestSuite.testCategoryCoverage`.
- Current residual user-facing issues are occasional recognition misses, rare transcription-side latency outliers, and workflow polish items such as configurable paste delimiters.

## System Shape

```text
HotkeyService
    |
    v
AppState ----------------------> OverlayWindowController
    |
    v
AudioRecorder
    |
    v
Transcription Backend -----------------> Optional Refinement Backend
    |                                            |
    +----------------------------+---------------+
                                 v
                            PasteService
                                 |
                                 v
                             HistoryStore

Shared configuration: AppSettings
Supporting services: PermissionService, ModelDiscoveryService, UpdateService
```

## Component Responsibilities

### AppState

- Owns the main recording state machine.
- Coordinates warm-up, recording, transcription, optional refinement, paste, history, and cleanup.
- Acts as the main orchestration layer and is currently larger than ideal.

### HotkeyService

- Detects `Fn` hold/release for push-to-talk.
- Detects Right Option double-tap / tap flow for lock mode.
- Emits callbacks rather than directly owning app behavior.

### AudioRecorder

- Owns the audio engine lifecycle.
- Supports two-phase warm-up then capture flow.
- Streams audio levels for visual feedback.
- Writes audio to temp files and performs silence-related helper work.

### Transcription Backends

- Current checked-in code models cloud and local-server transcription through `TranscriptionProvider` and `NetworkService`.
- The installed app also includes a WhisperKit on-device path, but repo/build truth for that path is still being reconciled.

### Refinement Backends

- Refinement is distinct from transcription.
- Current providers are OpenAI, Google, Groq, and Ollama.
- Raw Mode skips this entire layer.

### PasteService

- Handles clipboard-based paste insertion and restoration behavior.

### HistoryStore

- Persists transcript history and refinement variants.
- Current persistence is file-based, but detached writes still look like a reliability risk.

## Primary Runtime Flow

1. `HotkeyService` detects `Fn` press.
2. `AppState` starts warm-up through `AudioRecorder` and shows overlay feedback.
3. After the hold threshold, `AppState` begins capture.
4. On key release, `AppState` stops recording, performs speech/silence checks, then transcribes.
5. If refinement is enabled, Murmeln refines the transcript using the selected preset/provider path.
6. Murmeln pastes the final result and stores the interaction in history.

## Current Truth Caveat

Murmeln currently has two relevant truths:

- **Runtime truth:** the installed app actively uses WhisperKit on-device transcription.
- **Repo/build truth:** the checked-in source and SwiftPM path do not yet cleanly reproduce that runtime behavior.

Until those are reconciled, treat this document plus `_planning/` as the current top-layer truth. Use the deeper docs as supporting references rather than perfect ground truth.

## Deep References

- `docs/audio-pipeline.md` — warm-up and capture pipeline
- `docs/state-machine-diagram.md` — detailed state-machine and interaction diagrams
- `_planning/plans/2026-03-28-murmeln-plan.md` — roadmap and strategy
- `_planning/plans/2026-03-28-murmeln-findings.md` — evidence and discoveries
