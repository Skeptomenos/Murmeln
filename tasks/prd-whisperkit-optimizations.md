# PRD: WhisperKit Configurable Optimizations

## Introduction
Enhance the WhisperKit integration in Murmeln by adding multi-language support (specifically English and German) and configurable optimization profiles. This allows users to trade off speed vs. accuracy based on their needs and hardware capabilities.

## Goals
- Enable transcription in languages other than English (specifically German).
- Provide easy-to-use "profiles" for optimization (Fast, Balanced, Accurate).
- Allow granular control over decoding options for advanced users.
- Persist user preferences for language and optimization strategy.

## User Stories

### US-001: Language Selection
**Description:** As a user, I want to select the language of the audio so that transcription is accurate and faster (by skipping detection).

**Acceptance Criteria:**
- [ ] Add `whisperKitLanguage` setting to `AppSettings` (default: "en")
- [ ] Add Language Picker to `SettingsView` -> Transcription -> WhisperKit
- [ ] Options: Auto, English, German, French, Spanish, Italian (Multi-select is NOT supported by WhisperKit decoding options, so single select for now, but UI can be extensible)
    - *Correction*: User asked for multi-select "1B with multiselect", but Whisper's `decodingOptions.language` takes a single string code.
    - *Refinement*: We will implement a SINGLE select picker for the *primary* language to guide decoding. Whisper automatically handles mixed language if "Auto" is selected, but forcing a specific language improves speed/accuracy for mono-lingual audio.
    - *Wait*, did the user mean "I want to be able to select from multiple languages in the UI"? Yes.
    - *Clarification*: I will implement a picker with the requested languages.
- [ ] Pass selected language to `WhisperKitService` decoding options
- [ ] Verify UI in settings matches design

### US-002: Optimization Profiles
**Description:** As a user, I want to quickly switch between speed and accuracy without tweaking technical parameters.

**Acceptance Criteria:**
- [ ] Add `whisperKitProfile` enum to `AppSettings` (Fast, Balanced, Accurate, Custom)
- [ ] Add Profile Picker to `SettingsView` -> Transcription -> WhisperKit
- [ ] Map profiles to `DecodingOptions` in `WhisperKitService`:
    - **Fast**: Greedy, no VAD, no timestamps
    - **Balanced**: Greedy, basic VAD, timestamps
    - **Accurate**: Beam search (if feasible/performant) or Greedy with fallback, aggressive VAD, special tokens
- [ ] Verify transcription speed/quality changes with profiles

### US-003: Advanced Custom Options
**Description:** As an advanced user, I want to tweak specific decoding parameters when "Custom" is selected.

**Acceptance Criteria:**
- [ ] Add granular settings to `AppSettings`: `whisperKitUseVAD`, `whisperKitTemperature`, `whisperKitBeamSize` (if applicable)
- [ ] Show "Advanced Options" group in `SettingsView` ONLY when "Custom" profile is selected
- [ ] Connect these settings to `WhisperKitService` decoding options
- [ ] Verify UI visibility logic

### US-004: Persistence & Migration
**Description:** As a user, I want my settings to be saved so I don't have to re-configure them every time.

**Acceptance Criteria:**
- [ ] All new settings persist in `UserDefaults` via `AppSettings`
- [ ] Default values preserve current "Fast" behavior (Language: English, Profile: Fast)
- [ ] Typecheck passes

## Functional Requirements

- FR-1: `WhisperKitService.transcribe` must read `AppSettings.whisperKitLanguage` and `whisperKitProfile`
- FR-2: If `language` is not "Auto", set `decodingOptions.language` to the code (e.g., "de") and `detectLanguage = false`
- FR-3: If `profile` is "Fast", use `temperature=0`, `chunkingStrategy=.none`, `withoutTimestamps=true`
- FR-4: If `profile` is "Accurate", enable `chunkingStrategy=.vad`, `temperatureFallbackCount=5`
- FR-5: Settings UI must visually group these options under "Decoding Strategy"

## Non-Goals
- Real-time switching of profiles *during* recording (settings apply to next transcription)
- Downloading language-specific models (we use multilingual models `large-v3`, `small`, etc.)

## Technical Considerations
- WhisperKit `decodingOptions` struct is the source of truth.
- `language` property in `DecodingOptions` expects ISO codes ("en", "de").
- VAD requires `chunkingStrategy = .vad`

## Success Metrics
- Users can successfully transcribe German audio by selecting "German"
- Users can observe speed difference between "Fast" and "Accurate" profiles

