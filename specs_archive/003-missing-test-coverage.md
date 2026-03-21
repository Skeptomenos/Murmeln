# Spec 003: Expand Test Coverage for Critical Components

## Problem Description

While the codebase has good test coverage for data models and enums, several critical components lack tests:

### Untested Components:

1. **AppSettings persistence** - Settings are saved via `@AppStorage` and `UserDefaults` but there are no tests verifying:
   - Settings persist across app restarts
   - Custom presets save/load correctly
   - Preset overrides persist correctly
   - Personal dictionary saves/loads correctly

2. **HistoryStore** - No tests for:
   - Adding entries and maintaining max limit (50)
   - Removing entries (single, by offsets)
   - Clearing all entries
   - Persistence via UserDefaults

3. **Audio trimming/VAD** (`AudioRecorder.trimSilence`, `AudioRecorder.hasAudibleSpeech`):
   - These are complex algorithms with edge cases not covered by current tests
   - No tests for actual audio file processing

4. **AppState recording flow**:
   - No tests for state transitions (idle -> recording -> processing -> idle)
   - No tests for cancel scenarios
   - No tests for the multi-refinement parallel processing

5. **HotkeyService state machine**:
   - While threshold logic is tested, actual state machine transitions are not
   - No tests for lock mode engagement/disengagement
   - No tests for Fn key cancellation

6. **UpdateService**:
   - No tests for version comparison logic
   - No tests for GitHub API parsing

7. **OllamaService**:
   - No tests for model management
   - No tests for keep-alive functionality

8. **Integration tests**:
   - No end-to-end tests for the recording -> transcription -> refinement -> paste flow

## Current Behavior

Only 814 lines of tests covering primarily enum validation, response parsing, and edge cases. Critical business logic is untested.

## Expected Behavior

Comprehensive test coverage including:
- Unit tests for all service logic
- Integration tests for main workflows
- Mock-based tests for network calls

## Acceptance Criteria

- [ ] Add `AppSettingsTests` suite covering persistence
- [ ] Add `HistoryStoreTests` suite covering CRUD operations
- [ ] Add `AudioProcessingTests` with sample audio files
- [ ] Add `AppStateTests` for state machine transitions
- [ ] Add `HotkeyServiceTests` for lock mode scenarios
- [ ] Add `UpdateServiceTests` for version comparison
- [ ] Add `OllamaServiceTests` for model management
- [ ] Create test doubles/mocks for network calls
- [ ] Achieve >80% code coverage on business logic

## Technical Notes

**Current test file:** `Tests/MurmelnTests.swift` (814 lines)

**Testing framework:** Swift Testing (`@Test`, `#expect`)

**Suggested test structure:**
```
Tests/
  MurmelnTests.swift (existing)
  AppSettingsTests.swift (new)
  HistoryStoreTests.swift (new)
  AudioProcessingTests.swift (new)
  AppStateTests.swift (new)
  ServiceTests/
    NetworkServiceTests.swift (new)
    HotkeyServiceTests.swift (new)
    UpdateServiceTests.swift (new)
    OllamaServiceTests.swift (new)
  Mocks/
    MockNetworkService.swift (new)
    MockAudioRecorder.swift (new)
  Resources/
    sample_audio.wav (new)
```

**Severity:** High

**Impact:** Reliability, regression prevention, confidence in refactoring
