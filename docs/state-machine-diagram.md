# Murmeln State Machine Diagram

**Generated:** 2026-01-11  
**Purpose:** Deep state-machine reference for the Murmeln push-to-talk dictation app

> Current-state caveat: this document is a detailed historical/deep reference. For authoritative current-state behavior, start with `README.md`, `docs/architecture-overview.md`, and the active planning docs in `_planning/`.

---

## Table of Contents

1. [Overview](#overview)
2. [Primary State Machines](#primary-state-machines)
   - [AppState.RecordingPhase](#appstaterecordingphase)
   - [OverlayState](#overlaystate)
   - [HotkeyService States](#hotkeyservice-states)
3. [Component Interaction Diagram](#component-interaction-diagram)
4. [Complete Recording Flow Sequence](#complete-recording-flow-sequence)
5. [State Summary Table](#state-summary-table)
6. [Concurrency Model](#concurrency-model)

---

## Overview

Murmeln uses multiple coordinated state machines to manage the recording flow:

- **AppState.RecordingPhase** - Core application state (4 states)
- **OverlayState** - Visual feedback indicator (5 states)
- **HotkeyService** - Input detection with timing logic (internal flags)
- **AudioRecorder** - Implicit recording state (actor-isolated)

All state machines are designed to prevent race conditions through synchronous state transitions before async operations.

---

## Primary State Machines

### AppState.RecordingPhase

**Location:** `Sources/Models/AppState.swift:10-15`

The core state machine that orchestrates the entire recording flow.

```
                              +==============+
                              ||    IDLE    ||<----------------------------+
                              +======+======+                              |
                                     |                                     |
                          startRecording()                                 |
                          [guard: phase == .idle]                          |
                                     |                                     |
                                     v                                     |
                    +--------------------------------+                     |
                    |    REQUESTING_PERMISSION       |                     |
                    |  (synchronous state change)    |                     |
                    +---------------+----------------+                     |
                                    |                                      |
                    +---------------+----------------+                     |
                    |                                |                     |
            [permission denied]              [permission granted]          |
                    |                                |                     |
                    v                                v                     |
            lastError = "..."              +-----------------+             |
            phase = .idle ---------------->|    RECORDING    |             |
                                           | overlay.show()  |             |
                                           | audioLevel loop |             |
                                           +--------+--------+             |
                                                    |                      |
                                         stopAndProcess()                  |
                                         [or recording error]              |
                                                    |                      |
                    +-------------------------------+-------------------+  |
                    |                                                   |  |
            [no audio / no speech]                              [has speech]
                    |                                                   |  |
                    v                                                   v  |
            phase = .idle <-------------------------+    +--------------+  |
            overlay.hide()                          |    |  PROCESSING  |  |
                    |                               |    | transcribe() |  |
                    +-------------------------------+----|   refine()   |  |
                                                    |    |   paste()    |  |
                                                    |    +------+-------+  |
                                                    |           |          |
                                                    |    [success/error]   |
                                                    |           |          |
                                                    +-----------+----------+
```

#### State Definitions

| State | Description | Entry Condition | Exit Condition |
|-------|-------------|-----------------|----------------|
| `idle` | Ready for recording | App launch, recording complete, or error | `startRecording()` called |
| `requestingPermission` | Checking microphone access | `startRecording()` called | Permission result received |
| `recording` | Actively capturing audio | Permission granted | `stopAndProcess()` or error |
| `processing` | Transcribing and refining | Audio has speech | Transcription complete or error |

#### Key Implementation Details

- **Race Condition Prevention:** State changes to `requestingPermission` synchronously BEFORE async permission check
- **Guard Clause:** `startRecording()` only proceeds if `phase == .idle`
- **Dual Exit from Recording:** Both `stopAndProcess()` and errors can exit recording state
- **VAD Gate:** Processing only starts if `hasAudibleSpeech()` returns true

---

### OverlayState

**Location:** `Sources/Views/OverlayWindow.swift:5-11`

Visual feedback state machine for the minimal line indicator under the notch.

```
                              +==============+
              +---------------||    IDLE    ||<------------------+
              |               || opacity=0.15|                   |
              |               +======+======+                    |
              |                      |                           |
              |           onHoldStarted()                        |
              |                      |                           |
              |                      v                           |
              |               +--------------+                   |
              |               |   WAITING    |                   |
              |               | opacity=0.4  |                   |
              |               +------+-------+                   |
              |                      |                           |
              |    +-----------------+-----------------+         |
              |    |                                   |         |
              | onHoldCancelled()              onKeyDown()       |
              | [Fn < 400ms]                   [Fn >= 400ms]     |
              |    |                                   |         |
              |    v                                   v         |
              |  .idle                         +--------------+  |
              |    |                           |  LISTENING   |  |
              |    +---------------------------| opacity=0.85 |  |
              |                                | color=white  |  |
              |                                | width=audio  |  |
              |                                +------+-------+  |
              |                                       |          |
              |                             +---------+----------+
              |                             |                    |
              |                      onKeyUp()          onLockEngaged()
              |                             |           [double-tap R-Opt]
              |                             v                    |
              |                      +--------------+            v
              |                      |  PROCESSING  |     +--------------+
              |                      | shimmer anim |     |    LOCKED    |
              |                      | opacity=0.7  |     | color=orange |
              |                      +------+-------+     | opacity=0.85 |
              |                             |             +------+-------+
              |                      overlay.hide()              |
              |                             |          onLockDisengaged()
              |                             v           [tap R-Opt again]
              +-----------------------------+--------------------+
```

#### State Definitions

| State | Visual Appearance | Trigger |
|-------|-------------------|---------|
| `idle` | Dim white line (15% opacity, 50% width) | Default, or after processing/cancel |
| `waiting` | Brighter line (40% opacity, 70% width) | Fn key pressed, waiting for threshold |
| `listening` | Bright white, audio-reactive width | Fn held > 400ms, recording active |
| `locked` | Orange color, audio-reactive | Double-tap Right Option |
| `processing` | Shimmer animation (70% opacity) | Recording stopped, transcribing |

#### Visual Properties

```swift
private var currentWidth: CGFloat {
    switch controller.state {
    case .idle:      return baseWidth * 0.5      // 20px
    case .waiting:   return baseWidth * 0.7      // 28px
    case .listening, .locked:
        let expansion = CGFloat(min(1.0, audioLevel * 4)) * maxExpansion
        return baseWidth + expansion             // 40-48px based on audio
    case .processing: return baseWidth           // 40px
    }
}

private var lineColor: Color {
    switch controller.state {
    case .idle, .waiting, .listening, .processing: return .white
    case .locked: return .orange
    }
}
```

---

### HotkeyService States

**Location:** `Sources/Services/HotkeyService.swift`

Input handler with timing-based state detection. Uses internal flags rather than an enum.

#### Fn Key Flow

```
                              +--------------+
                              | fnKeyIsDown  |
                              |   = false    |
                              +------+-------+
                                     |
                              [Fn pressed]
                              [no other modifiers]
                                     |
                                     v
                              +--------------+
                              | fnKeyIsDown  |----------> onHoldStarted()
                              |   = true     |
                              |              |
                              | start 400ms  |
                              |    timer     |
                              +------+-------+
                                     |
                    +----------------+----------------+
                    |                                 |
            [Fn released < 400ms]           [timer fires]
                    |                                 |
                    v                                 v
            cancel timer                    fnRecordingDidStart = true
            onHoldCancelled()               onKeyDown() ------------------+
                    |                                                     |
                    v                                                     |
            fnKeyIsDown = false                                           |
                                                                          |
                                                                  [Fn released]
                                                                          |
                                                                          v
                                                                  onKeyUp()
                                                                  fnRecordingDidStart = false
```

#### Right Option Lock Flow

```
                              +--------------+
                              |  isLocked    |
                              |   = false    |
                              +------+-------+
                                     |
                    [Right Option double-tap < 400ms]
                                     |
                                     v
                              +--------------+
                              |  isLocked    |----------> onLockEngaged()
                              |   = true     |            onKeyDown()
                              +------+-------+
                                     |
                    [Right Option tap while locked]
                                     |
                                     v
                              +--------------+
                              |  isLocked    |----------> onLockDisengaged()
                              |   = false    |            onKeyUp()
                              +--------------+
```

#### Internal State Flags

| Flag | Type | Purpose |
|------|------|---------|
| `fnKeyIsDown` | `Bool` | Tracks if Fn is currently pressed |
| `fnDelayedStartTask` | `Task?` | 400ms delay timer for hold detection |
| `fnRecordingDidStart` | `Bool` | Whether recording was triggered (for proper cleanup) |
| `rightOptionDown` | `Bool` | Tracks Right Option key state |
| `lastRightOptionTapTime` | `Date?` | For double-tap detection |
| `isLocked` | `Bool` | Lock mode active (hands-free recording) |

#### Timing Thresholds

```swift
var holdThreshold: TimeInterval = 0.4      // 400ms to start recording
var doubleTapThreshold: TimeInterval = 0.4 // 400ms between taps for lock
```

---

## Component Interaction Diagram

```
+------------------+     callbacks      +------------------+
|  HotkeyService   |------------------>|    AppDelegate   |
|  (event monitor) |                    |  (wires events)  |
|                  |                    |                  |
| - Fn hold detect |                    | - onHoldStarted  |
| - R-Opt dbl-tap  |                    | - onKeyDown      |
| - timing logic   |                    | - onKeyUp        |
+------------------+                    | - onLock*        |
                                        +--------+---------+
                                                 |
                    +----------------------------+----------------------------+
                    |                            |                            |
                    v                            v                            v
        +------------------+        +------------------+        +------------------+
        |OverlayController |        |    AppState      |        |   AudioRecorder  |
        |                  |<-------|   (orchestrator) |------->|     (actor)      |
        |                  |        |                  |        |                  |
        | - show/hide      |        | - startRecording |        | - startRecording |
        | - state updates  |        | - stopAndProcess |        | - stopRecording  |
        | - audio level    |        | - phase machine  |        | - audio levels   |
        | - screen detect  |        |                  |        | - VAD/trim       |
        +------------------+        +--------+---------+        +------------------+
                                             |
                                             |
                    +------------------------+------------------------+
                    |                        |                        |
                    v                        v                        v
        +------------------+    +------------------+    +------------------+
        |  NetworkService  |    |   PasteService   |    |   HistoryStore   |
        |   (Sendable)     |    |                  |    |                  |
        |                  |    | - CGEvent paste  |    | - add entry      |
        | - transcribe     |    | - clipboard      |    | - max 50 entries |
        | - refine         |    +------------------+    | - variants       |
        | - multi-provider |                            +------------------+
        +------------------+
```

### Callback Wiring (AppDelegate)

```swift
// Sources/MurmelnApp.swift:148-173
hotkey.onHoldStarted = {
    overlay.state = .waiting
}

hotkey.onHoldCancelled = {
    overlay.state = .idle
}

hotkey.onKeyDown = {
    overlay.state = .listening
    AppState.shared.startRecording()
}

hotkey.onKeyUp = {
    AppState.shared.stopAndProcess()
}

hotkey.onLockEngaged = {
    overlay.state = .locked
}

hotkey.onLockDisengaged = {
    overlay.state = .idle
}
```

---

## Complete Recording Flow Sequence

```
User Action          HotkeyService        AppState              AudioRecorder
    |                     |                   |                       |
    | [Hold Fn]           |                   |                       |
    +-------------------->|                   |                       |
    |                     | onHoldStarted()   |                       |
    |                     +------------------>|                       |
    |                     |                   | overlay.state=waiting |
    |                     |                   |                       |
    | [400ms elapsed]     |                   |                       |
    |                     | onKeyDown()       |                       |
    |                     +------------------>|                       |
    |                     |                   | startRecording()      |
    |                     |                   +---------------------->|
    |                     |                   | phase=requestingPerm  |
    |                     |                   |                       |
    |                     |                   | [check mic permission]|
    |                     |                   |                       |
    |                     |                   | phase=recording       |
    |                     |                   | overlay.show()        |
    |                     |                   |<----------------------+
    |                     |                   |   AsyncStream<Float>  |
    |                     |                   |   (audio levels)      |
    | [Speaking...]       |                   |                       |
    |                     |                   | overlay.updateLevel() |
    |                     |                   |                       |
    | [Release Fn]        |                   |                       |
    +-------------------->|                   |                       |
    |                     | onKeyUp()         |                       |
    |                     +------------------>|                       |
    |                     |                   | stopAndProcess()      |
    |                     |                   +---------------------->|
    |                     |                   |                       | stopRecording()
    |                     |                   |                       | [300ms tail buffer]
    |                     |                   |<----------------------+
    |                     |                   |   URL (audio file)    |
    |                     |                   |                       |
    |                     |                   | [VAD check]           |
    |                     |                   | [silence trim]        |
    |                     |                   |                       |
    |                     |                   | phase=processing      |
    |                     |                   | overlay.setProcessing |
    |                     |                   |                       |
    |                     |                   | NetworkService        |
    |                     |                   | .transcribeAndRefine()|
    |                     |                   |                       |
    |                     |                   | [if refinement on]    |
    |                     |                   | NetworkService.refine |
    |                     |                   | [parallel for presets]|
    |                     |                   |                       |
    |                     |                   | PasteService.paste()  |
    |                     |                   | HistoryStore.add()    |
    |                     |                   |                       |
    |                     |                   | phase=idle            |
    |                     |                   | overlay.hide()        |
    |<--------------------+-------------------+ [text pasted]         |
```

### Lock Mode Sequence

```
User Action          HotkeyService        AppState              AudioRecorder
    |                     |                   |                       |
    | [Double-tap R-Opt]  |                   |                       |
    +-------------------->|                   |                       |
    |                     | onLockEngaged()   |                       |
    |                     +------------------>| overlay.state=locked  |
    |                     | onKeyDown()       |                       |
    |                     +------------------>|                       |
    |                     |                   | startRecording()      |
    |                     |                   +---------------------->|
    |                     |                   | [recording starts]    |
    |                     |                   |                       |
    | [Speaking hands-free...]                |                       |
    |                     |                   |                       |
    | [Tap R-Opt]         |                   |                       |
    +-------------------->|                   |                       |
    |                     | onLockDisengaged()|                       |
    |                     +------------------>| overlay.state=idle    |
    |                     | onKeyUp()         |                       |
    |                     +------------------>|                       |
    |                     |                   | stopAndProcess()      |
    |                     |                   | [same as normal flow] |
```

---

## State Summary Table

| Component | States | Location |
|-----------|--------|----------|
| **AppState.RecordingPhase** | `idle`, `requestingPermission`, `recording`, `processing` | `Models/AppState.swift:10-15` |
| **OverlayState** | `idle`, `waiting`, `listening`, `locked`, `processing` | `Views/OverlayWindow.swift:5-11` |
| **HotkeyService** | Internal flags: `fnKeyIsDown`, `fnRecordingDidStart`, `isLocked`, `rightOptionDown` | `Services/HotkeyService.swift` |
| **AudioRecorder** | Implicit: idle (no engine) -> recording (engine running) -> stopped | `Services/AudioService.swift` |

---

## Concurrency Model

| Component | Isolation | Pattern | Rationale |
|-----------|-----------|---------|-----------|
| `AppState` | `@MainActor` | Singleton | Orchestrates UI state, must be main thread |
| `HotkeyService` | `@MainActor` | Singleton | Event callbacks run on main thread |
| `OverlayWindowController` | `@MainActor` | Singleton | NSWindow requires main thread |
| `AudioRecorder` | `actor` | Instance | Isolated audio capture, async streams |
| `NetworkService` | `Sendable` | Singleton | Stateless, thread-safe URLSession |
| `PasteService` | `@MainActor` | Singleton | CGEvent requires main thread |
| `HistoryStore` | `@MainActor` | Singleton | @Published properties for UI binding |
| `PermissionService` | `@MainActor` | Singleton | System permission APIs |
| `AppSettings` | `@MainActor` | Singleton | @AppStorage requires main thread |

### Actor Boundaries

```
+------------------+          +------------------+
|   @MainActor     |          |      actor       |
|                  |   async  |                  |
|   AppState       |--------->|  AudioRecorder   |
|   HotkeyService  |<---------|                  |
|   Overlay        |  stream  |                  |
|   PasteService   |          |                  |
|   HistoryStore   |          |                  |
+------------------+          +------------------+
         |
         | async
         v
+------------------+
|    Sendable      |
|                  |
|  NetworkService  |
|  (URLSession)    |
|                  |
+------------------+
```

---

## Error States and Recovery

### Permission Denied

```
startRecording() -> requestingPermission -> [denied] -> idle
                                                     -> lastError = "Microphone access denied..."
```

### Recording Error

```
recording -> [AVAudioEngine error] -> idle
                                   -> lastError = error.localizedDescription
                                   -> overlay.hide()
```

### Network Error

```
processing -> [API error] -> idle
                          -> lastError = error.localizedDescription
                          -> overlay.hide()
```

### No Speech Detected

```
stopAndProcess() -> [VAD returns false] -> idle (no error, silent skip)
                                        -> cleanup temp file
```

---

## Appendix: State Enum Definitions

### AppState.RecordingPhase

```swift
// Sources/Models/AppState.swift:10-15
enum RecordingPhase {
    case idle
    case requestingPermission  // Set synchronously before permission check
    case recording             // Actively recording audio
    case processing            // Transcribing and refining
}
```

### OverlayState

```swift
// Sources/Views/OverlayWindow.swift:5-11
enum OverlayState: Equatable {
    case idle
    case waiting
    case listening
    case locked
    case processing
}
```

### AppState.DisplayState (UI Convenience)

```swift
// Sources/MurmelnApp.swift:29-31
enum DisplayState {
    case idle, recording, processing
}
```

---

## Related Documentation

- [PROMPT_ENGINEERING_GUIDE.md](./PROMPT_ENGINEERING_GUIDE.md) - Refinement prompt design
- [PROMPT-ENGINEERING-LEARNINGS.md](./PROMPT-ENGINEERING-LEARNINGS.md) - Lessons learned
- [PROMPT_VARIANTS.md](./PROMPT_VARIANTS.md) - Preset prompt variants
