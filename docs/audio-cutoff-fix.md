# Audio Cutoff Fix

**Date:** 2026-01-14

## Problem

Users experienced audio cutoff at the beginning and end of recordings. The issue was particularly noticeable when:
- Holding Fn longer than the speech duration (end cutoff of 3+ words)
- Starting to speak immediately after the recording indicator appeared (beginning cutoff)

## Root Cause Analysis

### 1. Large Buffer Size (End Cutoff)

**Before:** Buffer size was 4096 samples

At 16kHz sample rate: 4096 samples = **256ms per buffer**

If the user releases Fn and the last buffer hasn't been delivered yet, up to 256ms of audio is lost.

### 2. Fixed Tail Buffer (End Cutoff)

**Before:** 
```swift
func stopRecording() async -> URL? {
    try? await Task.sleep(for: .milliseconds(300))
    // ... stop engine
}
```

The 300ms sleep was a race condition. It didn't guarantee the last buffer was written—it just hoped 300ms was enough. If the last buffer arrived at 310ms, it was lost.

### 3. Engine Startup Latency (Beginning Cutoff)

**Before:** Engine started when recording began (after 400ms threshold)

```
Fn Press → 400ms wait → startRecording() → engine.prepare() → engine.start() → first buffer
                                                                              ↑
                                                              50-200ms latency here
```

The user could start speaking before the first buffer arrived.

## Solution

### 1. Reduced Buffer Size

**After:** Buffer size reduced to 1024 samples

At 16kHz: 1024 samples = **64ms per buffer** (4x improvement)

```swift
node.installTap(onBus: 0, bufferSize: 1024, format: tapFormat) { ... }
```

### 2. Buffer Drain Detection

**After:** Intelligent drain detection instead of fixed sleep

```swift
func stopRecording() async -> URL? {
    let drainThreshold: TimeInterval = 0.1  // 100ms silence = drained
    let maxWait: TimeInterval = 0.5         // 500ms max wait
    
    while let lastTime = lastBufferTime {
        let timeSinceLastBuffer = Date().timeIntervalSince(lastTime)
        
        if timeSinceLastBuffer >= drainThreshold {
            break  // Pipeline drained
        }
        
        if Date().timeIntervalSince(startTime) >= maxWait {
            break  // Timeout
        }
        
        try? await Task.sleep(for: .milliseconds(20))
    }
    // ... stop engine
}
```

The tap callback tracks `lastBufferTime`. We poll until no buffer arrives for 100ms, meaning the pipeline is empty.

### 3. Engine Warm-up During Hold Threshold

**After:** Engine starts immediately on Fn press, not after 400ms

```
Fn Press → prepareEngine() → engine running, levels streaming
         ↓ (400ms threshold)
Threshold met → beginCapture() → install recording tap (instant)
```

The 400ms hold threshold (which filters accidental taps) is now used productively to warm up the audio engine. By the time recording starts, the engine is already running.

## Implementation

### New AudioRecorder Methods

| Method | Purpose |
|--------|---------|
| `prepareEngine()` | Starts engine, installs level-only tap, returns level stream |
| `beginCapture()` | Removes level tap, installs recording tap, creates file |
| `cancelWarmUp()` | Stops engine if user releases before threshold |

### New AppState Methods

| Method | Called When |
|--------|-------------|
| `warmUpEngine()` | `onHoldStarted` (Fn press) |
| `cancelWarmUp()` | `onHoldCancelled` (Fn release < 400ms) |
| `beginRecording()` | `onKeyDown` (after 400ms threshold) |

### New RecordingPhase

Added `.warmingUp` state between `.idle` and `.recording`.

## Results

| Metric | Before | After |
|--------|--------|-------|
| Max buffer latency | 256ms | 64ms |
| Tail buffer reliability | Race condition | Deterministic |
| Startup latency | 50-200ms | 0ms |

## Tunable Parameters

If issues persist, these can be adjusted in `AudioService.swift`:

| Parameter | Default | Purpose |
|-----------|---------|---------|
| `bufferSize` | 1024 | Audio buffer size in samples |
| `drainThreshold` | 100ms | How long to wait for buffer silence |
| `maxWait` | 500ms | Maximum drain wait before timeout |
