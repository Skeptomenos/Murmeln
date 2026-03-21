# PRD: WhisperKit Integration for Murmeln

## 1. Introduction
Integrate **WhisperKit** (by Argmax) into Murmeln to provide native, fully offline, privacy-first speech recognition on macOS. This leverages Apple Silicon's Neural Engine for high-performance transcription without requiring an external server or API keys.

## 2. Goals
- **True Offline Support:** Transcribe audio without internet connection or external server processes.
- **Privacy First:** Ensure audio data never leaves the device.
- **High Performance:** Utilize Apple Silicon (CoreML + Metal) for fast transcription.
- **Seamless UX:** Easy model management with a dedicated setup wizard and smart defaults.
- **Coexistence:** Retain existing provider support (OpenAI, Groq, Local Server) while adding this as a premium native option.

## 3. User Stories

### US-001: Configure WhisperKit in Settings
**Description:** As a user, I want to select "WhisperKit (On-Device)" as my transcription provider in settings.

**Acceptance Criteria:**
- [ ] "WhisperKit (On-Device)" added to Transcription Provider list
- [ ] When selected, specific WhisperKit UI options appear (Model status, Current model)
- [ ] No API key field is shown for this provider
- [ ] "Local Whisper" renamed to "Local Whisper Server" to avoid confusion
- [ ] Verify in Settings UI

### US-002: Model Download Wizard
**Description:** As a user, I want a guided experience to download transcription models so I understand what is being installed.

**Acceptance Criteria:**
- [ ] "Download Models" button opens a Setup/Download Wizard sheet
- [ ] Wizard displays list of available models (tiny, base, small, medium, large-v3) with metadata (size, speed, quality)
- [ ] "Smart Default" is pre-selected based on device RAM (e.g., 'base' for 8GB, 'small' for 16GB+)
- [ ] Download progress bar shows percentage and status text
- [ ] Verify in UI with network throttling if possible

### US-003: Download & Manage Models
**Description:** As a user, I want to download models to a permanent location so I don't have to re-download them after cache clearing.

**Acceptance Criteria:**
- [ ] Models downloaded to `~/Library/Application Support/Murmeln/Models/`
- [ ] Download process handles network interruptions gracefully (basic error handling)
- [ ] UI reflects "Ready" status when model is successfully downloaded and compiled
- [ ] User can switch between multiple downloaded models

### US-004: Transcribe Audio Offline
**Description:** As a user, I want to record and transcribe audio using the installed WhisperKit model.

**Acceptance Criteria:**
- [ ] Audio pipeline routes recording to `WhisperKitService` when provider is selected
- [ ] Transcription returns accurate text
- [ ] Processing indicator (overlay) works normally during transcription
- [ ] First-run "Prewarming/Compiling" delay is handled with a user-facing status ("Preparing model...")
- [ ] Verify transcription with network disconnected

## 4. Functional Requirements

### 4.1. WhisperKit Service (`WhisperKitService.swift`)
- **FR-1:** Singleton service managing `WhisperKit` instance.
- **FR-2:** `fetchAvailableModels()` retrieves model list from HuggingFace.
- **FR-3:** `downloadModel(variant)` downloads to Application Support directory.
- **FR-4:** `loadModel(variant)` initializes WhisperKit with the specified model.
- **FR-5:** `transcribe(audioURL)` performs the transcription.
- **FR-6:** `scanDownloadedModels()` detects locally available models.
- **FR-7:** Manage model state (`unloaded`, `downloading`, `loading`, `ready`, `error`).

### 4.2. App Settings (`AppSettings.swift`)
- **FR-8:** Store `whisperKitModel` (String) preference.
- **FR-9:** Rename `localWhisper` enum case to `localWhisperServer` (with migration if needed, or just display rename).
- **FR-10:** Add `TranscriptionProvider.whisperKit` case.

### 4.3. UI Components
- **FR-11:** `WhisperKitSetupView`:
    - List of models with details.
    - Download action.
    - Progress visualization.
- **FR-12:** `SettingsView` updates:
    - Conditional section for WhisperKit provider.
    - Model selector (dropdown of *downloaded* models).
    - Status indicator (Ready/Not Ready).

### 4.4. Integration
- **FR-13:** `NetworkService` handles routing to `WhisperKitService` instead of HTTP call when `whisperKit` provider is active.

## 5. Non-Goals
- Bundling models with the app binary (keep binary small).
- Fine-tuning models on-device.
- Supporting Intel Macs (WhisperKit is optimized for Apple Silicon; Intel support is possible but low priority for this pass).
- Real-time streaming transcription (batch processing only for now).

## 6. Technical Considerations

- **Storage:** Use `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)`
- **Memory:** WhisperKit models stay in RAM. Implement `unload` mechanism if memory pressure is high, or rely on OS paging.
- **Concurrency:** Ensure `WhisperKitService` operations are non-blocking on MainActor.
- **Compilation:** CoreML models take time to compile on first run. Use `prewarm: true` during download phase if possible, or show "Compiling..." state on first use.

## 7. Success Metrics
- Successful transcription without internet access.
- Model download completes successfully in testing.
- Settings UI clearly communicates model status.
- No regression in existing provider functionality.

## 8. Open Questions
- **Intel Macs:** Should we explicitly block or warn Intel users? (Assumption: Allow, but performance may vary. WhisperKit theoretically supports it via CPU).
- **Update Check:** How do we handle model updates? (Future scope).
