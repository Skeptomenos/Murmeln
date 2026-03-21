# Spec 010: Fix Personal Dictionary Storage Format

## Problem Description

The personal dictionary uses a brittle string delimiter (`|||`) that can cause data corruption if a user adds a term containing that sequence.

### Current Implementation

```swift
// AppSettings.swift:75-83
var personalDictionary: [String] {
    get {
        guard !personalDictionaryData.isEmpty else { return [] }
        return personalDictionaryData.components(separatedBy: "|||")
    }
    set {
        personalDictionaryData = newValue.prefix(20).joined(separator: "|||")
    }
}
```

### Bug Scenario

1. User adds term "foo|||bar" to dictionary (unlikely but possible)
2. Stored as: "existingTerm|||foo|||bar"
3. On load, splits into: ["existingTerm", "foo", "bar"]
4. Original term is corrupted into two separate entries

### Additional Issue

The delimiter choice is arbitrary and undocumented. Future maintainers may not understand why `|||` was chosen.

## Expected Behavior

- Dictionary stored as proper JSON array
- Any string value can be stored without corruption
- Clear, maintainable storage format

## Acceptance Criteria

- [ ] Change storage to JSON-encoded array
- [ ] Migrate existing `|||`-delimited data on first access
- [ ] Handle migration edge cases (empty, malformed)
- [ ] Add test for special characters in dictionary terms

## Technical Notes

**Files to modify:**
- `Sources/Models/AppSettings.swift`

**Fix:**
```swift
@AppStorage("personalDictionaryJSON") private var personalDictionaryJSON = "[]"

var personalDictionary: [String] {
    get {
        // Try new JSON format first
        if let data = personalDictionaryJSON.data(using: .utf8),
           let array = try? JSONDecoder().decode([String].self, from: data) {
            return array
        }
        
        // Migrate from old format if needed
        if !personalDictionaryData.isEmpty {
            let oldValues = personalDictionaryData.components(separatedBy: "|||")
            personalDictionary = oldValues  // Triggers setter with new format
            personalDictionaryData = ""  // Clear old format
            return oldValues
        }
        
        return []
    }
    set {
        let limited = Array(newValue.prefix(20))
        if let data = try? JSONEncoder().encode(limited),
           let json = String(data: data, encoding: .utf8) {
            personalDictionaryJSON = json
        }
    }
}
```

**Severity:** Medium

**Impact:** Data integrity (edge case)

**Effort:** Low (30 minutes)

**Success Confidence:** 99%
