# Murmeln Architecture Overview

> Short current-state map for Murmeln. For deeper capture-flow detail, see `docs/audio-pipeline.md` and `docs/state-machine-diagram.md`.

## Mission and baseline

Murmeln turns spoken thought into pasted text with as little friction as possible: hold a key, speak, release, keep typing. The primary path is local inference on Apple Silicon; cloud and local-server backends remain compatibility options.

The supported application baseline is macOS 26.0+ on Apple Silicon. The checked-in project builds isolated `Murmeln` and `Murmeln Dev` products. `bash validate.sh` is the deterministic Tier 1 gate; `bash validate-e2e.sh` is the real-model Tier 1.5 gate.

## System shape

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
    +--> RuntimeTranscriptionBackend (catalog-driven local models)
    |        |
    |        +--> FluidAudioRuntime (CoreML: Parakeet and Cohere)
    |        +--> WhisperKitRuntime (CoreML: Whisper family)
    |
    +--> LegacyCloudMultipartTranscriptionBackend
    +--> LegacyLocalWhisperServerBackend
    +--> LegacyCloudAudioInputBackend
    +--> TextRefinementBackend (optional)
    |
    v
PasteService -> HistoryStore

Shared configuration: AppSettings
Model metadata: ModelCatalog
Supporting services: PermissionService, ModelDiscoveryService, UpdateService
```

## Local runtime and catalog

The local architecture separates three concerns:

1. `TranscriptionRuntime` owns model lifecycle, progress, load state, deletion, and transcription.
2. `ModelCatalog` declares stable IDs, display names, runtime ownership, languages, language-hint behavior, approximate download size, per-call limits, and user-facing caveats.
3. `RuntimeTranscriptionBackend` adapts any catalog runtime into the pipeline and emits the common capture telemetry contract, including runtime and quantization attribution.

The catalog currently ships Parakeet v3 multilingual (default), Parakeet v2 English, Cohere Transcribe INT8, and WhisperKit. Adding another model to an already-supported runtime is a catalog entry plus tests; adding a runtime does not require a new app-level settings pane or pipeline adapter.

`CatalogDownloadManager` owns model-keyed download activity for the app lifetime. Downloads continue across picker changes, distinct models may download concurrently, and callbacks from cancelled attempts cannot overwrite a retry. The Settings UI reads that shared state and exposes cancel, retry, delete, and re-download operations.

## Component responsibilities

### AppState

- Owns the recording state machine and coordinates warm-up, capture, overlay state, paste, history, and cleanup.
- Calls `TranscriptionPipelineService` for transcription and selected-path refinement.
- Retains the temporary parallel-refinement fan-out used for audit variants.

### TranscriptionPipelineService

- Routes catalog entries through their runtime and generic local adapter.
- Routes cloud multipart, local-server, and one-call cloud audio through legacy compatibility adapters.
- Selects `transcribe_only`, `one_call_transcription_refinement`, or `two_call_refinement` mode.
- Produces run context for canonical per-capture telemetry.

### HotkeyService and AudioRecorder

- `HotkeyService` detects Fn hold/release and Right Option lock-mode gestures.
- `AudioRecorder` owns the two-phase engine warm-up/capture flow, audio levels, temporary files, trimming, and speech checks.
- The recording state machine and warm-up contract are preserved across runtime changes.

### PasteService and HistoryStore

- `PasteService` validates paste preconditions, inserts through the clipboard, and preserves the transcript on the clipboard when delivery fails.
- `HistoryStore` persists final transcripts and refinement/audit variants.

## Settings and migration

`selectedModelID` identifies a catalog model and `preferredLanguage` stores either `auto` or an ISO language code. Each catalog entry resolves that preference according to its language capability; hint-required models provide an explicit safe default.

Cloud and local-server choices remain represented by `TranscriptionProvider`. Selection changes flow through one setter/change signal. A one-time migration reads legacy provider and language values, maps them to the equivalent catalog model and language, and leaves existing users on the same functional path without requiring setup again.

## Primary runtime flow

1. `HotkeyService` detects Fn press or lock-mode activation.
2. `AppState` starts audio-engine warm-up and displays pre-capture feedback.
3. After the hold threshold, capture begins.
4. On release, `AppState` stops recording, performs speech checks, and sends the audio to `TranscriptionPipelineService`.
5. The pipeline resolves the selected catalog runtime or legacy adapter and transcribes.
6. Optional refinement runs unless the user keeps the default raw/transcribe-only mode.
7. Murmeln pastes the result, records telemetry, and stores history. Failed paste delivery leaves the transcript recoverable on the clipboard.

## Invariants

- Local inference is first-class; cloud and local-server paths remain supported but do not shape the catalog architecture.
- Model lifecycle state is model-keyed and observable.
- The per-capture telemetry contract is additive.
- The recording state machine and warm-up model change only with measured evidence.
- Migration keeps existing local-model selections and language intent intact.

## Phase 3B handoff boundary

If coordinator decomposition resumes, keep recording transitions, overlay/window coordination, and user-facing errors in `AppState`. Extract post-capture orchestration and parallel refinement/audit assembly without re-litigating the runtime/catalog or backend-family seams now owned by `TranscriptionPipelineService`.

## Deep references

- `docs/audio-pipeline.md` — warm-up and capture pipeline
- `docs/state-machine-diagram.md` — detailed state-machine and interaction diagrams
- `_planning/plans/2026-03-28-murmeln-plan.md` — roadmap and strategy
- `_planning/plans/2026-03-28-murmeln-findings.md` — evidence and discoveries
