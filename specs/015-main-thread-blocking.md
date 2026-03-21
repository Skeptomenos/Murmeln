# [015] Main Thread Blocking in cleanupTempFile

**Priority:** CRITICAL  
**Effort:** 15 minutes  
**Confidence:** 99%  
**Discovered:** 2026-01-11 (Code Review + Oracle Analysis)

## Problem

`AppState.cleanupTempFile()` uses `Thread.sleep()` on a `@MainActor` class, which blocks the main thread and freezes the UI.

## Evidence

```swift
// Sources/Models/AppState.swift lines 247-260
@MainActor
final class AppState: ObservableObject {
    // ...
    
    private func cleanupTempFile(at url: URL, maxRetries: Int = 3) {
        for attempt in 1...maxRetries {
            do {
                try FileManager.default.removeItem(at: url)
                return
            } catch {
                if attempt == maxRetries {
                    print("...")
                } else {
                    Thread.sleep(forTimeInterval: 0.1 * Double(attempt))  // BLOCKS MAIN THREAD
                }
            }
        }
    }
}
```

## Impact

- **UI Freeze:** Main thread blocked for up to 0.6 seconds (0.1 + 0.2 + 0.3) during retry loop
- **User Experience:** App appears unresponsive after recording completes
- **System Integration:** macOS window server connection may timeout on extended blocks

## Root Cause

`Thread.sleep()` is a synchronous, blocking call. When called from a `@MainActor` context, it halts all UI updates and event processing.

## Solution

### Option A: Async Sleep (Recommended)

Make the function async and use cooperative sleeping:

```swift
private func cleanupTempFile(at url: URL, maxRetries: Int = 3) async {
    for attempt in 1...maxRetries {
        do {
            try FileManager.default.removeItem(at: url)
            return
        } catch {
            if attempt == maxRetries {
                print("...")
            } else {
                try? await Task.sleep(for: .milliseconds(100 * attempt))
            }
        }
    }
}
```

Update call sites to use `await`:
```swift
// In stopAndProcess()
await cleanupTempFile(at: url)
```

### Option B: Detached Task (Alternative)

If keeping the function synchronous is preferred, move the retry logic off the main actor:

```swift
private func cleanupTempFile(at url: URL, maxRetries: Int = 3) {
    Task.detached(priority: .utility) {
        for attempt in 1...maxRetries {
            do {
                try FileManager.default.removeItem(at: url)
                return
            } catch {
                if attempt == maxRetries {
                    // Log error (but not on main actor)
                } else {
                    try? await Task.sleep(for: .milliseconds(100 * attempt))
                }
            }
        }
    }
}
```

## Recommendation

**Option A** is preferred because:
1. The function is already called from an async context (`stopAndProcess()`)
2. It maintains structured concurrency
3. It's the minimal change required

## Testing

1. Record a short audio clip
2. Verify UI remains responsive during cleanup phase
3. Verify temp files are still cleaned up successfully

## Files Affected

- `Sources/Models/AppState.swift`

## Related Specs

- None (newly discovered issue)
