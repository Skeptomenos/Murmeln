# Murmeln

Push-to-talk dictation macOS menu bar app. Hold Fn to record, release to transcribe and auto-paste.

## Identity
- **Status:** poc
- **Tech:** Swift 6, SwiftUI, macOS

## Commands

```bash
# Build (debug)
swift build

# Build (release via xcodebuild)
xcodebuild -scheme Murmeln -configuration Release -derivedDataPath build build

# Run all tests
swift test

# Run a single test file
swift test --filter AppStateTests

# Run a single test method
swift test --filter "AppStateTests/initialStateIsIdle"

# Run tests matching pattern
swift test --filter "HotkeyService"

# Install to /Applications
cp -r build/Build/Products/Release/Murmeln.app /Applications/
```

## Project Structure

```
Sources/
├── MurmelnApp.swift          # @main entry, MenuBarExtra, hotkey wiring
├── Models/                   # State, settings, provider enums
│   ├── AppState.swift        # @MainActor singleton, orchestrates recording flow
│   ├── AppSettings.swift     # @AppStorage persistence
│   └── Provider.swift        # TranscriptionProvider + Provider enums
├── Services/                 # Business logic, all async
│   ├── AudioService.swift    # actor AudioRecorder - capture, conversion
│   ├── NetworkService.swift  # Sendable - API calls
│   ├── HotkeyService.swift   # Fn hold + Right Option detection
│   └── ...
└── Views/                    # SwiftUI views
Tests/                        # Swift Testing framework suites
docs/                         # Concept and implementation docs
```

## Code Style

### Concurrency Model
- **UI-bound classes**: `@MainActor` (e.g., `AppState`)
- **Stateless services**: `Sendable` (e.g., `NetworkService`)
- **Stateful async work**: `actor` (e.g., `AudioRecorder`)

### Rules
- No `as any` — use concrete types or proper generics.
- No force unwraps — except in controlled contexts.
- No blocking main thread — all network/audio is async.
- No hardcoded API keys — all keys from AppSettings.
- Nested error enums conforming to `LocalizedError` with `errorDescription`.

## Testing

Uses Swift Testing framework (not XCTest):

```swift
import Testing
@testable import mrml

@Suite("AppState Tests")
struct AppStateTests {
    @Test("Initial state is idle")
    func initialStateIsIdle() {
        #expect(isRecording == false)
    }
}
```

## Key Patterns

- **State Machine**: `RecordingPhase`: `idle → warmingUp → recording → processing → idle`.
- **Provider Pattern**: Separate enums for `TranscriptionProvider` and `Provider`.
- **Audio Pipeline**: Engine warms up during 400ms hold threshold. See `docs/audio-pipeline.md`.
