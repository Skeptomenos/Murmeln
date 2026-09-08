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
HistoryStore (retain exact result + queue save receipt)
    |
    v
PasteService (preflight -> snapshot -> guarded post -> conditional restore)
    |
    +--> Recovery notice + menu (explicit Copy / Check / Dismiss)

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

- AppState reserves History capacity before capture and retains the immutable final result/capture ID before any paste wait. Failed or empty captures release the reservation. A new blocked result can replace the prominent card only after retention.
- `HistoryStore` owns the existing bounded History, with no second recovery journal. `HistoryPersistence` serializes whole-snapshot writes and returns revision/content receipts. Per-entry saved status and the latest required snapshot are separate. Delete invalidates actions immediately; failed deletion remains visible until a newer snapshot succeeds.
- `PasteService` shares one main-actor gate with recovery Copy and every History Copy route, including native text selection. Copy never queues. Known blockers and incomplete snapshots cause zero automatic writes/posts. Late blockers restore only while owned; changed ownership prevents posting.
- `ClipboardSnapshot` materializes every advertised representation, checks reconstruction and generation before clearing, and rechecks ownership after reconstruction on restore. This cannot make cross-process clipboard access atomic or guarantee arbitrary file-promise semantics.
- `RecoveryNoticeController` presents a nonactivating panel with generic text. It hides on lock, sleep and session switch. Successful Copy and Dismiss acknowledge attention without deleting the retained History entry; failed/busy Copy keeps attention open. The icon uses unresolved attention, not retained-result existence. Copy, exact History navigation and Dismiss share `RecoveryActionsView` with the menu. Only explicit History navigation activates a window.
- The menu receives the actual SwiftUI adaptor-owned `AppDelegate`. Restart quiesces existing work and verifies a new process for the exact bundle before exit; failed launch restores the current app. Accessibility Settings navigation and permission preflight are distinct operations.
- `AppState` captures a separate `CapturedPasteTarget` once at capture admission, before asynchronous work or UI activation. It retains ordinary TextEdit or verified Notion process/window/editor identity and empty-caret metadata; it reads no field text, selected text, title or path. Supplied proofs must still match before clipboard mutation and posting, even if Secure Input clears. Valid proofs waive only the global Secure Input flag. Unknown apps retain the default guard; failed Notion capture retains an invalid proof and cannot fall back. Supplied-proof paste never queues; failed admission, cancellation, completion and termination release the proof.
- `paste_attempt` schema 2 records the deciding stage/reason, target policy and available invalidation reason from the existing checks. Paired service modifier samples retain raw flags; the equality check ignores only the mouse/pen coalescing flag. Optional cached `app_code_hash` correlates signing metadata across builds that reuse version numbers; it is not a permission, running-image or signature-validity receipt. Schema 1 remains readable. Early cancellation records a terminal decision without sampling OS state or changing throwing behavior. The bounded Notion walk separates local budget expiry, missing metadata, unsupported structure and AX transport failure using its original reads. These records contain no transcript, clipboard contents, title, path or target-app identity. `posted` still means command posting, not confirmed insertion.
- A separately enabled Debug Dev experiment accepts only fixed text in one verified disposable TextEdit document. It shares clipboard ownership and records actual security samples. It cannot accept arbitrary transcripts and is not the normal delivery entry; see `agent-dictation-testing.md`.
- `TerminationCoordinator` stops admission, cancels and joins AppState and diagnostic paste tasks, then waits for History receipts. Save/delete failure denies Quit once, clears the latch and restores input services. Quit anyway is a separate confirmation with Cancel as default. No power-loss durability or target-delivery acknowledgment is claimed.

## Settings and migration

`SettingsShell` and its unboxed sections provide the resizable settings layout on a uniform background. `HistoryBrowser` and `HistoryTranscriptDetail` provide the transcript list and an unboxed reading pane. These presentation views do not access services or storage. History adapters supply selectable text and Copy actions, so a guarded clipboard implementation can retain its own selection and copy policy.

Settings and History adapters share the `windowAppearance` UserDefaults key, defaulting to Dark. Their `preferredColorScheme` applies only to the hosted window. System mode inherits macOS appearance. Native window appearance transitions are checked by the offscreen preview helper; app-wide appearance and the recovery panel are unchanged.

`selectedModelID` identifies a catalog model and `preferredLanguage` stores either `auto` or an ISO language code. Each catalog entry resolves that preference according to its language capability; hint-required models provide an explicit safe default.

Cloud and local-server choices remain represented by `TranscriptionProvider`. Selection changes flow through one setter/change signal. A one-time migration reads legacy provider and language values, maps them to the equivalent catalog model and language, and leaves existing users on the same functional path without requiring setup again.

## Primary runtime flow

1. `HotkeyService` detects Fn press or lock-mode activation.
2. `AppState` starts audio-engine warm-up and displays pre-capture feedback.
3. After the hold threshold, capture begins.
4. On release, `AppState` stops recording, performs speech checks, and sends the audio to `TranscriptionPipelineService`.
5. The pipeline resolves the selected catalog runtime or legacy adapter and transcribes.
6. Optional refinement runs unless the user keeps the default raw/transcribe-only mode.
7. Murmeln retains the exact final result, then attempts the guarded paste transaction and records its outcome. Blocked delivery offers explicit recovery from History. Disk persistence and a posted command are reported separately.

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
