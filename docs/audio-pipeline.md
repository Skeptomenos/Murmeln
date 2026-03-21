# Audio Pipeline

## Concept

Murmeln captures audio through a push-to-talk interface. The user holds Fn, speaks, and releases. The audio is then transcribed and pasted. The pipeline must capture speech reliably without cutting off the beginning or end.

### Requirements

1. **Zero perceived latency** - Recording should feel instant when the user starts speaking
2. **Complete capture** - No audio loss at beginning or end of recordings
3. **Efficient processing** - Minimize file size and API latency

### Challenges

| Challenge | Cause | Impact |
|-----------|-------|--------|
| Beginning cutoff | Audio engine startup takes 50-200ms | First words lost |
| End cutoff | Audio buffers still in flight when recording stops | Last words lost |
| Buffer latency | Large buffers delay audio delivery | Increases cutoff window |

## Architecture

### Recording Flow

```
Fn Press → prepareEngine() → Engine starts, levels stream (warm-up)
         ↓ (400ms hold threshold)
Threshold met → beginCapture() → Install recording tap (instant)
         ↓
Fn Release → stopRecording() → Buffer drain detection → Process audio
```

### Components

**AudioRecorder** (actor)
- Manages AVAudioEngine lifecycle
- Handles sample rate conversion (native → 16kHz)
- Streams audio levels for visual feedback
- Writes audio to temporary WAV file

**AppState** (orchestrator)
- Coordinates warm-up, capture, and processing phases
- Manages state machine: idle → warmingUp → recording → processing → idle
- Handles permission checks

**HotkeyService** (input)
- Detects Fn key hold/release
- Fires callbacks: onHoldStarted, onKeyDown, onKeyUp, onHoldCancelled

### State Machine

```
┌─────────────────────────────────────────────────────────┐
│                                                         │
│  ┌──────┐  Fn press   ┌───────────┐  400ms   ┌─────────┐│
│  │ idle │────────────▶│ warmingUp │─────────▶│recording││
│  └──────┘             └───────────┘          └─────────┘│
│      ▲                      │                     │     │
│      │                      │ Fn release          │     │
│      │                      │ (< 400ms)           │     │
│      │                      ▼                     │     │
│      │               ┌──────────┐                 │     │
│      └───────────────│cancelled │                 │     │
│                      └──────────┘                 │     │
│      ▲                                            │     │
│      │                                            │     │
│      │         ┌────────────┐    Fn release       │     │
│      └─────────│ processing │◀────────────────────┘     │
│                └────────────┘                           │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

## API Reference

### AudioRecorder

```swift
actor AudioRecorder {
    /// Phase 1: Start engine without recording (warm-up)
    func prepareEngine(highQuality: Bool) async throws -> AsyncStream<Float>
    
    /// Phase 2: Begin writing to file (requires warm engine)
    func beginCapture() async throws
    
    /// Cancel warm-up without recording
    func cancelWarmUp() async
    
    /// Stop recording and return audio file URL
    func stopRecording() async -> URL?
    
    /// Legacy single-call API (still works for lock mode)
    func startRecording(highQuality: Bool) async throws -> AsyncStream<Float>
}
```

### AppState

```swift
@MainActor
final class AppState {
    enum RecordingPhase {
        case idle
        case warmingUp          // Engine running, waiting for threshold
        case requestingPermission
        case recording          // Actively capturing audio
        case processing         // Transcribing and refining
    }
    
    func warmUpEngine()      // Called on Fn press
    func cancelWarmUp()      // Called if Fn released before 400ms
    func beginRecording()    // Called after 400ms threshold
    func stopAndProcess()    // Called on Fn release
}
```
