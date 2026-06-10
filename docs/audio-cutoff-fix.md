# Audio Cutoff Prevention — Current Design

**Last updated:** 2026-06-10 (rewritten to match the code; the original 2026-01-14
analysis described a drain-detection design that has since been removed)

## Problem (historical)

Users experienced audio cutoff at the beginning and end of recordings:
- End cutoff: trailing words lost when Fn was released while buffers were still in flight.
- Beginning cutoff: speech started before the engine delivered its first buffer.

## Current Design

The pipeline in `Sources/Services/AudioService.swift` prevents cutoff with four
mechanisms:

### 1. Small buffer size

The persistent tap uses 1024-sample buffers — **64ms per buffer at 16kHz** — so at
most one short buffer can ever be "in flight" at release time.

```swift
node.installTap(onBus: 0, bufferSize: 1024, format: tapFormat) { ... }
```

### 2. Persistent tap + pre-roll ring (beginning cutoff)

`prepareEngine()` starts the engine and installs a single persistent tap on Fn
press, **before** the 400ms hold threshold. While not yet recording, the tap
buffers audio into a bounded pre-roll ring (`preRollDurationSeconds = 0.35`).
`beginCapture()` flushes the ring into the file and arms one deferred flush so
buffers that arrive between the synchronous flush and the next tap callback are
still written in order, before live audio.

**DANGER:** this flush ordering is load-bearing — it is what prevents
beginning-of-audio cutoff. Do not "simplify" it.

### 3. Fixed stop grace period (end cutoff)

`stopRecording()` waits a fixed **350ms** (`stopGracePeriod`) before tearing the
tap down, capturing trailing audio still moving through the engine/converter.

This is an intentional, fixed product latency — not a fallback. An earlier
"drain detection" loop (exit early once no buffer arrives for 120ms) was dead
code: while the engine runs, the persistent tap delivers buffers every ~64ms,
so the early exit could never fire before the timeout. It was removed in the
2026-06 hardening pass.

### 4. Locked tap state (correctness under concurrency)

All state shared between the tap callback (audio render thread) and the
`AudioRecorder` actor lives in `TapState`, guarded by an
`OSAllocatedUnfairLock`. On stop, `isWriting` flips under the lock, so an
in-flight callback either completes its write first or diverts its buffer to
the pre-roll ring, which the final locked flush persists. No audio is dropped
between "stop requested" and "file finalized".

## Phases

| Method | Called when | Purpose |
|--------|-------------|---------|
| `prepareEngine()` | Fn press (`onHoldStarted`) | Start engine, install persistent tap, stream levels, fill pre-roll |
| `beginCapture()` | Hold threshold met (`onKeyDown`) | Create file, flush pre-roll, start writing |
| `cancelWarmUp()` | Fn release before threshold | Stop engine without saving |
| `stopRecording()` | Fn release while recording | Grace period, final flushes, finalize file |

## Tunable Parameters

| Parameter | Default | Purpose |
|-----------|---------|---------|
| `bufferSize` | 1024 | Tap buffer size in samples (64ms at 16kHz) |
| `preRollDurationSeconds` | 0.35 | Pre-roll ring capacity (beginning-cutoff protection) |
| `stopGracePeriod` | 0.35 | Fixed trailing-audio wait on stop (end-cutoff protection) |
