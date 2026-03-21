# Spec 005: Remove Sensitive Data from Logs

## Problem Description

Transcribed text is logged to the console, potentially exposing private user dictation including passwords, medical information, or confidential data.

### Current Implementation

```swift
// AppState.swift:143
print("✅ Baseline obtained: '\(originalText)'")

// Additional logging throughout:
// AppState.swift:62, 70, 76, 91, 97, 103, 112, 131, 147, 187, 217, 234, 254
// AudioService.swift:229, 238, 262, 300, 304
// PasteService.swift:11, 26
// UpdateService.swift:54, 56, 59
```

### Privacy Risk

- User dictates password: "My password is hunter2"
- Text appears in Console.app and system logs
- Logs may be included in diagnostic reports
- Shared computers expose private dictation

## Expected Behavior

- No user-generated content in production logs
- Debug logging wrapped in `#if DEBUG`
- Error messages should not include transcription text

## Acceptance Criteria

- [ ] Wrap all `print()` statements in `#if DEBUG` blocks
- [ ] Or replace with proper logging framework (os.log) with appropriate privacy levels
- [ ] Ensure error messages don't include transcription content
- [ ] Review all files for sensitive data logging
- [ ] Add privacy note to README about debug builds

## Technical Notes

**Files to modify:**
- `Sources/Models/AppState.swift`
- `Sources/Services/AudioService.swift`
- `Sources/Services/PasteService.swift`
- `Sources/Services/UpdateService.swift`

**Option 1: Conditional compilation**
```swift
#if DEBUG
print("✅ Baseline obtained: '\(originalText)'")
#endif
```

**Option 2: os.log with privacy (preferred)**
```swift
import os

private let logger = Logger(subsystem: "com.murmeln", category: "transcription")

// Public metadata only
logger.info("Baseline obtained, length: \(originalText.count)")

// Private data (redacted in release)
logger.debug("Content: \(originalText, privacy: .private)")
```

**Severity:** High

**Impact:** User privacy, trust

**Effort:** Low (15-30 minutes)

**Success Confidence:** 99%
