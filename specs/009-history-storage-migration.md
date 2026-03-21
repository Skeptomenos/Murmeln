# Spec 009: Migrate History Storage to File System

## Problem Description

History is stored in `UserDefaults`, which is not designed for large data and causes performance issues as history grows.

### Current Implementation

```swift
// HistoryStore.swift:62-69
private func save() {
    if let data = try? JSONEncoder().encode(entries) {
        UserDefaults.standard.set(data, forKey: "transcriptionHistory")
    }
}

private func load() {
    if let data = UserDefaults.standard.data(forKey: "transcriptionHistory"),
       let entries = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
        self.entries = entries
    }
}
```

### Issues

1. **Performance**: UserDefaults is optimized for small key-value pairs, not large JSON blobs
2. **Blocking**: JSON encoding happens on main thread, causing UI stutters
3. **No versioning**: Schema changes could corrupt or lose user data
4. **Silent failures**: `try?` swallows encoding errors

### Data Size Estimate

With 50 entries, parallel refinement (5 presets), and average 500-char transcriptions:
- Per entry: ~3KB (original + refined + 5 variants + prompts + metadata)
- Total: ~150KB in UserDefaults
- With long transcriptions: Could exceed 1MB

## Expected Behavior

- History stored in `~/Library/Application Support/Murmeln/history.json`
- Async encoding/decoding off main thread
- Schema versioning for safe migrations
- Proper error handling with user notification

## Acceptance Criteria

- [ ] Create file-based storage in Application Support directory
- [ ] Add schema version to storage format
- [ ] Migrate existing UserDefaults data on first launch
- [ ] Move JSON encoding to background thread
- [ ] Implement atomic writes (write to temp, then rename)
- [ ] Add proper error handling with logging
- [ ] Clean up old UserDefaults key after migration
- [ ] Add migration test

## Technical Notes

**Files to modify:**
- `Sources/Models/HistoryStore.swift`

**New storage format:**
```json
{
    "version": 1,
    "entries": [...]
}
```

**Implementation:**
```swift
@MainActor
final class HistoryStore: ObservableObject {
    private let fileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let murmelnDir = appSupport.appendingPathComponent("Murmeln", isDirectory: true)
        try? FileManager.default.createDirectory(at: murmelnDir, withIntermediateDirectories: true)
        return murmelnDir.appendingPathComponent("history.json")
    }()
    
    private func save() {
        Task.detached { [entries = self.entries, fileURL = self.fileURL] in
            let storage = HistoryStorage(version: 1, entries: entries)
            do {
                let data = try JSONEncoder().encode(storage)
                let tempURL = fileURL.appendingPathExtension("tmp")
                try data.write(to: tempURL, options: .atomic)
                try FileManager.default.moveItem(at: tempURL, to: fileURL)
            } catch {
                print("Failed to save history: \(error)")
            }
        }
    }
    
    private func migrateFromUserDefaults() {
        guard let oldData = UserDefaults.standard.data(forKey: "transcriptionHistory"),
              let oldEntries = try? JSONDecoder().decode([HistoryEntry].self, from: oldData) else {
            return
        }
        entries = oldEntries
        save()
        UserDefaults.standard.removeObject(forKey: "transcriptionHistory")
    }
}

struct HistoryStorage: Codable {
    let version: Int
    let entries: [HistoryEntry]
}
```

**Severity:** Medium

**Impact:** Performance, data integrity, scalability

**Effort:** Medium (3-4 hours)

**Success Confidence:** 90%
