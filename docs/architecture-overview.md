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
- Full `swift test` passes; `bash validate.sh` is the single validation gate (build, tests, Dev-scheme build, doc drift checks, hygiene).
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
TranscriptionPipelineService
    |
    +--> WhisperKitTranscriptionBackend (first-class local-native)
    +--> LegacyCloudMultipartTranscriptionBackend
    +--> LegacyLocalWhisperServerBackend
    +--> LegacyCloudAudioInputBackend
    +--> TextRefinementBackend (optional)
    |
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
- Coordinates warm-up, recording, overlay state, paste, history, and cleanup.
- Calls `TranscriptionPipelineService` for backend-family execution and run-context attribution.
- Still owns the temporary parallel refinement fan-out path for multi-preset audit variants.

### TranscriptionPipelineService

- Owns transcription backend-family dispatch and selected-path refinement execution.
- Encodes support-tier and backend-kind distinctions through `TranscriptionBackendDescriptor`.
- Decides pipeline mode (`transcribe_only`, `one_call_transcription_refinement`, `two_call_refinement`).
- Emits backend run context used by canonical per-capture telemetry summary events.

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

- First-class local-native path: `WhisperKitTranscriptionBackend`.
- Legacy compatibility paths: cloud multipart, local-server, and one-call cloud audio-input adapters.
- Refinement remains separate and optional; one-call providers can still return final text without a second refinement call.

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

- **Runtime and checked-in Xcode truth:** WhisperKit local-native transcription is the current first-class path.
- **Phase 3 progress:** backend-family seams and telemetry contracts are now explicit in dedicated pipeline models/services, with remaining full coordinator decomposition deferred to Phase 3B.

Until those are reconciled, treat this document plus `_planning/` as the current top-layer truth. Use the deeper docs as supporting references rather than perfect ground truth.

## Phase 3B Handoff Boundary

If Phase 3B is promoted, the coordinator split should target only the remaining orchestration coupling:

- Keep in `AppState`: recording phase transitions, overlay/window coordination, and user-facing error state.
- Keep temporarily in `AppState` until extracted: parallel multi-preset refinement fan-out and variant assembly for history.
- Move in Phase 3B: end-to-end runtime coordinator responsibilities that still mix capture/runtime transitions with post-capture orchestration.
- Move in Phase 3B: explicit refinement-audit orchestration service if parallel variant logic remains shipped and grows further.

Phase 3B should avoid re-litigating backend-family seams; those are now owned by `TranscriptionPipelineService` and backend descriptors.

## Deep References

- `docs/audio-pipeline.md` — warm-up and capture pipeline
- `docs/state-machine-diagram.md` — detailed state-machine and interaction diagrams
- `_planning/plans/2026-03-28-murmeln-plan.md` — roadmap and strategy
- `_planning/plans/2026-03-28-murmeln-findings.md` — evidence and discoveries
