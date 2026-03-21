# Spec 013: Fix Paste on Non-US Keyboard Layouts

## Problem Description

The paste simulation uses a hardcoded key code for 'V' that only works on US QWERTY keyboards. On other layouts (Dvorak, AZERTY, Colemak), the wrong key is sent.

### Current Implementation

```swift
// PasteService.swift:25
private func simulatePasteViaCGEvent() {
    let vKeyCode: CGKeyCode = 0x09  // kVK_ANSI_V - US QWERTY only!
    // ...
}
```

### Bug Scenario

| Layout  | Key at 0x09 | Result of Cmd+0x09 |
|---------|-------------|-------------------|
| QWERTY  | V           | Paste (correct)   |
| Dvorak  | .           | Unknown action    |
| AZERTY  | V           | Paste (correct)   |
| Colemak | G           | Unknown action    |

### User Impact

- Paste fails silently on affected layouts
- May trigger unintended actions in some apps
- Users on non-US layouts cannot use the app

## Expected Behavior

- Dynamically resolve the key code for 'V' based on current keyboard layout
- Or use a layout-agnostic paste method

## Acceptance Criteria

- [ ] Research layout-agnostic paste methods
- [ ] Implement dynamic key code resolution OR alternative paste method
- [ ] Test on at least 3 different keyboard layouts
- [ ] Add fallback if primary method fails

## Technical Notes

**Files to modify:**
- `Sources/Services/PasteService.swift`

**Option 1: Dynamic key code resolution**
```swift
import Carbon

private func keyCodeForCharacter(_ character: String) -> CGKeyCode? {
    let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
    guard let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
        return nil
    }
    let layout = unsafeBitCast(layoutData, to: CFData.self)
    let layoutPtr = CFDataGetBytePtr(layout)
    
    // Use UCKeyTranslate to find key code for 'v'
    // This is complex - see Apple docs for full implementation
    return nil  // Placeholder
}
```

**Option 2: AppleScript fallback (simpler but slower)**
```swift
private func simulatePasteViaAppleScript() {
    let script = """
    tell application "System Events"
        keystroke "v" using {command down}
    end tell
    """
    if let appleScript = NSAppleScript(source: script) {
        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
    }
}
```

**Option 3: Use NSEvent instead of CGEvent**
```swift
// NSEvent can use characters instead of key codes
let event = NSEvent.keyEvent(
    with: .keyDown,
    location: .zero,
    modifierFlags: .command,
    timestamp: 0,
    windowNumber: 0,
    context: nil,
    characters: "v",
    charactersIgnoringModifiers: "v",
    isARepeat: false,
    keyCode: 0
)
```

**Severity:** Low (affects minority of users)

**Impact:** App unusable on some keyboard layouts

**Effort:** Medium (2-3 hours)

**Success Confidence:** 80%
