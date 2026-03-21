# Spec 002: Fix State Machine Race Condition

## Problem Description

A critical race condition exists in the recording state machine that causes the app to get "stuck" in recording mode when the user performs a quick tap of the Fn key.

### Current Implementation

```swift
// AppState.swift:42-82
func startRecording() {
    guard !isRecording && !isProcessing else { return }
    
    recordingTask = Task {
        // Permission check is ASYNC
        guard await PermissionService.shared.checkMicrophonePermission() else {
            lastError = "Microphone permission denied..."
            return
        }
        
        isRecording = true  // Set AFTER await - TOO LATE!
        // ... start recording
    }
}

func stopAndProcess() {
    guard isRecording else { return }  // Returns early because isRecording is still false!
    // ...
}
```

### Race Condition Sequence

1. User quick-taps Fn key (press + release in <100ms)
2. `startRecording()` called, creates Task, begins permission check
3. `stopAndProcess()` called immediately after
4. `isRecording` is still `false` (permission check not complete)
5. `stopAndProcess()` returns early due to guard
6. Permission check completes, `isRecording = true`, recording starts
7. Recording is now "stuck" - no way to stop it without restart

### Additional State Gap

Between `stopAndProcess()` setting `isRecording = false` (line 93) and `isProcessing = true` (line 126), there are two `await` points. During this gap, a new recording can start, overwriting captured settings.

## Expected Behavior

- State changes should be synchronous and atomic
- Quick taps should either start+stop cleanly or not start at all
- No state gaps where both `isRecording` and `isProcessing` are false during active work

## Acceptance Criteria

- [ ] Set `isRecording = true` synchronously at the START of `startRecording()`, before any await
- [ ] Implement proper state enum: `enum State { case idle, recording, processing }`
- [ ] Cancel existing `recordingTask` before starting new one
- [ ] Add guard to prevent state transitions during processing
- [ ] Add test for quick-tap scenario
- [ ] Add test for rapid repeated taps

## Technical Notes

**Files to modify:**
- `Sources/Models/AppState.swift`

**Recommended refactor:**
```swift
enum RecordingState {
    case idle
    case recording
    case processing
}

@Published var state: RecordingState = .idle

func startRecording() {
    guard state == .idle else { return }
    state = .recording  // Synchronous, immediate
    
    recordingTask?.cancel()
    recordingTask = Task {
        guard await PermissionService.shared.checkMicrophonePermission() else {
            state = .idle
            lastError = "Microphone permission denied..."
            return
        }
        // ... continue recording
    }
}

func stopAndProcess() {
    guard state == .recording else { return }
    state = .processing  // Immediate transition, no gap
    // ...
}
```

**Severity:** Critical

**Impact:** App becomes unusable, requires force quit

**Effort:** Medium (2-3 hours)

**Success Confidence:** 90%
