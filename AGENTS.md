# MURMELN KNOWLEDGE BASE

**Generated:** 2026-01-03
**Commit:** (pending)
**Branch:** main

## OVERVIEW

Push-to-talk dictation macOS menu bar app. Swift 6 + SwiftUI. Hold Fn → record → release → transcribe via API → auto-paste. Double-tap Right Option for hands-free lock mode.

## STRUCTURE

```
Murmeln/
├── Sources/
│   ├── MurmelnApp.swift      # Entry point, MenuBarExtra, AppDelegate
│   ├── Models/               # State + settings + provider enums
│   ├── Services/             # Audio, network, hotkey, paste, permissions
│   └── Views/                # Settings window, overlay, visualizer
├── Tests/                    # XCTest target
├── Assets.xcassets/          # App icon, menu bar icon
├── Package.swift             # SPM manifest (executable: mrml)
└── Murmeln.xcodeproj/        # Xcode project (alternative build)
```

## WHERE TO LOOK

| Task | Location | Notes |
|------|----------|-------|
| Add new provider | `Models/Provider.swift` | Add to `TranscriptionProvider` enum |
| Modify API calls | `Services/NetworkService.swift` | Switch on provider type |
| Change hotkey | `Services/HotkeyService.swift` | Fn hold + Right Option double-tap |
| Adjust overlay UI | `Views/OverlayWindow.swift` | Minimal line indicator under notch |
| Settings UI | `Views/SettingsView.swift` | TabView with 4 tabs |
| History | `Models/HistoryStore.swift` + `Views/HistoryWindow.swift` | UserDefaults, max 50 entries |
| Recording logic | `Services/AudioService.swift` | Actor-based, streams audio levels |
| App state | `Models/AppState.swift` | Singleton, orchestrates record→transcribe→paste |

## CODE MAP

| Symbol | Type | Location | Role |
|--------|------|----------|------|
| `MurmelnApp` | struct | MurmelnApp.swift:5 | @main entry, MenuBarExtra |
| `AppState` | class | Models/AppState.swift:5 | @MainActor singleton, orchestrates flow |
| `AppSettings` | class | Models/AppSettings.swift:4 | @MainActor, @AppStorage persistence |
| `AudioRecorder` | actor | Services/AudioService.swift:4 | Async audio capture, RMS levels |
| `NetworkService` | class | Services/NetworkService.swift:17 | API calls, Sendable |
| `HotkeyService` | class | Services/HotkeyService.swift:4 | Fn hold + Right Option double-tap |
| `PasteService` | class | Services/PasteService.swift:5 | CGEvent paste simulation |
| `PermissionService` | class | Services/PermissionService.swift:5 | Mic + Accessibility checks |
| `OverlayWindowController` | class | Views/OverlayWindow.swift:12 | Floating status indicator |
| `TranscriptionProvider` | enum | Models/Provider.swift:40 | OpenAI/Groq/GPT-4o/Gemini/Local |
| `Provider` | enum | Models/Provider.swift:3 | Refinement providers |

## CONVENTIONS

- **Singletons**: All services use `static let shared` pattern
- **Concurrency**: `@MainActor` on UI-bound classes, `actor` for AudioRecorder, `Sendable` for NetworkService
- **State**: Single `AppState.shared` drives all UI via `@Published`
- **Settings**: `@AppStorage` for persistence, no CoreData/files
- **Naming**: Executable is `mrml` (Package.swift), app is `Murmeln`

## ANTI-PATTERNS

- **No type suppressions**: No `as any`, no force unwraps except in controlled contexts
- **No blocking main thread**: All network/audio is async
- **No hardcoded API keys**: All keys from AppSettings

## UNIQUE STYLES

- **Provider pattern**: `TranscriptionProvider` vs `Provider` enums separate transcription from refinement
- **One-call refinement**: Some providers (GPT-4o Audio, Gemini) do transcribe+refine in single call
- **Screen detection**: Overlay positions on screen of frontmost window, not just primary

## COMMANDS

```bash
# Build via xcodebuild
xcodebuild -scheme Murmeln -configuration Release -derivedDataPath build build

# Build via SPM (executable name: mrml)
swift build -c release

# Run tests
swift test

# Install to /Applications
cp -r build/Build/Products/Release/Murmeln.app /Applications/
```

## NOTES

- **Permissions**: Requires Microphone + Accessibility + Automation (System Events)
- **Fn key**: Hold >400ms to start recording (filters accidental taps)
- **Right Option**: Double-tap for lock mode (hands-free recording)
- **Unsigned builds**: Microphone permission may re-prompt on each launch
- **macOS 14+**: Uses Swift 6 strict concurrency, requires Sonoma or later
- **KeyboardShortcuts**: External dependency for potential future hotkey customization (currently unused for Fn)
