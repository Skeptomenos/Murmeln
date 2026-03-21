# Spec 003: Preserve User Clipboard Content

## Problem Description

The paste service destroys the user's clipboard content without saving or restoring it, causing data loss after every transcription.

### Current Implementation

```swift
// PasteService.swift:16
pasteboard.clearContents()
pasteboard.setString(text, forType: .string)
```

### User Impact

- User copies important text/image/file to clipboard
- User triggers Murmeln transcription
- Transcription replaces clipboard content
- Original clipboard content is permanently lost
- User cannot paste their original content

### Additional Issue

There's a 100ms race window between setting clipboard and sending Cmd+V. If user copies something during this window, wrong content gets pasted.

## Expected Behavior

- Save clipboard contents before transcription
- Paste transcription text
- Restore original clipboard contents after a short delay
- Handle complex clipboard items (not just strings)

## Acceptance Criteria

- [ ] Save all `NSPasteboardItem`s before clearing clipboard
- [ ] Restore original items after paste completes (~200ms delay)
- [ ] Handle edge cases: empty clipboard, non-string content
- [ ] Add user preference to disable clipboard restoration (optional)
- [ ] Test with various clipboard content types (text, images, files)

## Technical Notes

**Files to modify:**
- `Sources/Services/PasteService.swift`

**Implementation approach:**
```swift
@MainActor
final class PasteService {
    static let shared = PasteService()
    private let pasteboard = NSPasteboard.general
    
    func paste(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            print("Skipping paste: text is empty")
            return
        }
        
        // Save current clipboard
        let savedItems = saveClipboard()
        
        // Set new content and paste
        pasteboard.clearContents()
        pasteboard.setString(trimmed, forType: .string)
        
        try? await Task.sleep(for: .milliseconds(100))
        simulatePasteViaCGEvent()
        
        // Restore after paste completes
        try? await Task.sleep(for: .milliseconds(200))
        restoreClipboard(savedItems)
    }
    
    private func saveClipboard() -> [[NSPasteboard.PasteboardType: Data]] {
        var items: [[NSPasteboard.PasteboardType: Data]] = []
        for item in pasteboard.pasteboardItems ?? [] {
            var itemData: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    itemData[type] = data
                }
            }
            items.append(itemData)
        }
        return items
    }
    
    private func restoreClipboard(_ items: [[NSPasteboard.PasteboardType: Data]]) {
        guard !items.isEmpty else { return }
        pasteboard.clearContents()
        for itemData in items {
            let item = NSPasteboardItem()
            for (type, data) in itemData {
                item.setData(data, forType: type)
            }
            pasteboard.writeObjects([item])
        }
    }
}
```

**Severity:** High

**Impact:** Data loss, user frustration

**Effort:** Medium (2-3 hours)

**Success Confidence:** 85%
