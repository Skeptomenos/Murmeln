# Spec 011: Document Secure Input Field Limitation

## Problem Description

The global hotkey silently stops working when the user is focused on a "Secure Input" field (password fields, some terminal emulators), with no indication of why.

### Technical Background

macOS disables `NSEvent.addGlobalMonitorForEvents` when Secure Input is active to prevent keyloggers from capturing passwords. This is expected security behavior, but users may think the app is broken.

### Current Behavior

- User focuses on a password field
- Presses Fn key to record
- Nothing happens
- User has no idea why

### Affected Contexts

- Password fields in any app
- Safari/Chrome password autofill
- Terminal.app (when running certain commands)
- 1Password, Bitwarden unlock screens
- System Preferences authentication dialogs

## Expected Behavior

- Document this limitation clearly in README
- Optionally: Detect Secure Input mode and show a notification

## Acceptance Criteria

- [ ] Add "Known Limitations" section to README
- [ ] Explain Secure Input behavior and why it exists
- [ ] List common affected contexts
- [ ] (Optional) Detect `SecureEventInputEnabled()` and show menu bar indicator

## Technical Notes

**Files to modify:**
- `README.md`

**README addition:**
```markdown
## Known Limitations

### Hotkey Disabled in Password Fields

The Fn key hotkey will not work when you're focused on a password field or other 
"Secure Input" context. This is a macOS security feature that prevents apps from 
monitoring keystrokes in sensitive fields.

**Affected contexts:**
- Password fields in any application
- Browser password autofill dialogs
- Terminal.app (when running `sudo` or `ssh`)
- Password manager unlock screens
- System authentication dialogs

**Workaround:** Click outside the password field before using Murmeln, or use the 
menu bar to manually trigger recording.
```

**Optional detection:**
```swift
import Carbon

func isSecureInputEnabled() -> Bool {
    return SecureEventInputEnabled()
}

// In HotkeyService or AppState:
if isSecureInputEnabled() {
    // Show indicator in menu bar or overlay
}
```

**Severity:** Medium (documentation)

**Impact:** User confusion, support requests

**Effort:** Low (15 minutes for docs, 1 hour for detection)

**Success Confidence:** N/A (documentation)
