# Spec 008: Optimize Audio Memory Usage

## Problem Description

Audio files are loaded entirely into memory multiple times during processing, causing excessive memory usage for long recordings.

### Current Implementation

```swift
// AudioService.swift:173 - trimSilence loads entire file
let file = try AVAudioFile(forReading: url)
let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, 
                               frameCapacity: AVAudioFrameCount(file.length))!
try file.read(into: buffer)

// AudioService.swift:267 - hasAudibleSpeech loads entire file again
let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                               frameCapacity: AVAudioFrameCount(file.length))!

// NetworkService.swift:85, 123, 149, 192 - loads file for upload
let audioData = try Data(contentsOf: audioURL)
let base64Audio = audioData.base64EncodedString()  // +33% memory
```

### Memory Impact

| Recording Length | Sample Rate | Raw Size | With Base64 | Peak Memory |
|------------------|-------------|----------|-------------|-------------|
| 1 minute         | 16kHz       | ~2 MB    | ~2.7 MB     | ~8 MB       |
| 5 minutes        | 16kHz       | ~10 MB   | ~13 MB      | ~40 MB      |
| 10 minutes       | 16kHz       | ~20 MB   | ~27 MB      | ~80 MB      |
| 10 minutes       | 44.1kHz     | ~53 MB   | ~70 MB      | ~200 MB     |

Peak memory is ~3x raw size due to multiple copies (VAD, trim, upload).

### Risk

- OOM crashes on older Macs with limited RAM
- System slowdown during processing
- Swap thrashing on memory-constrained systems

## Expected Behavior

- Process audio in chunks for VAD and trimming
- Stream audio uploads instead of loading into memory
- Constant memory footprint regardless of recording length

## Acceptance Criteria

- [ ] Refactor `hasAudibleSpeech` to analyze in 10-second chunks
- [ ] Refactor `trimSilence` to process in chunks
- [ ] Use `URLSession.uploadTask(with:fromFile:)` for streaming upload
- [ ] Peak memory usage < 50MB for any recording length
- [ ] Add memory usage test/benchmark

## Technical Notes

**Files to modify:**
- `Sources/Services/AudioService.swift`
- `Sources/Services/NetworkService.swift`

**Chunked VAD approach:**
```swift
func hasAudibleSpeech(in url: URL, threshold: Float = 0.01) async throws -> Bool {
    let file = try AVAudioFile(forReading: url)
    let chunkSize: AVAudioFrameCount = 16000 * 10  // 10 seconds at 16kHz
    let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, 
                                   frameCapacity: chunkSize)!
    
    while file.framePosition < file.length {
        try file.read(into: buffer)
        if chunkHasAudibleSpeech(buffer, threshold: threshold) {
            return true
        }
        buffer.frameLength = 0  // Reset for next read
    }
    return false
}
```

**Streaming upload:**
```swift
// Instead of:
let audioData = try Data(contentsOf: audioURL)
let (data, response) = try await session.upload(for: request, from: audioData)

// Use:
let (data, response) = try await session.upload(for: request, fromFile: audioURL)
```

**Note:** Multipart form data with streaming is more complex and may require a custom `InputStream`-based body.

**Severity:** High

**Impact:** Stability on memory-constrained systems

**Effort:** High (4-6 hours)

**Success Confidence:** 80%
