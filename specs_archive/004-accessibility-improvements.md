# Spec 004: Accessibility Improvements

## Problem Description

The app lacks proper accessibility support, making it difficult or impossible to use for users relying on VoiceOver or other assistive technologies:

### Missing Accessibility Features:

1. **OverlayWindow ignores mouse events** (`OverlayWindow.swift:67`):
   ```swift
   window.ignoresMouseEvents = true
   ```
   This is intentional for the overlay, but there's no alternative way for accessibility users to know the current state.

2. **No accessibility labels on overlay states**:
   The `MinimalLineIndicator` view changes color and size to indicate state, but doesn't expose this information via accessibility APIs.

3. **History cards lack accessibility structure** (`HistoryWindow.swift`):
   - Complex card layout with nested VStacks
   - No accessibility groups or labels
   - Variant cards don't announce their content properly

4. **Settings view accessibility gaps** (`SettingsView.swift`):
   - Sidebar navigation has no accessibility hints
   - Toggle descriptions not linked to toggles via accessibility
   - Picker selections don't announce their purpose

5. **Menu bar status not accessible**:
   - The `MenuContent` view uses color to indicate status (red for recording, blue for processing)
   - No VoiceOver announcement when status changes

6. **Keyboard navigation limited**:
   - Settings window uses `.keyboardShortcut` for some actions
   - History window has no keyboard shortcuts
   - No keyboard shortcut for common actions (copy last result, toggle recording)

7. **Missing dynamic type support**:
   - Fixed font sizes throughout (`font(.caption)`, `.font(.system(size: 9))`)
   - No support for user-preferred text size

## Current Behavior

The app is primarily usable only via mouse/trackpad and visual feedback. VoiceOver users would struggle to understand the app state or navigate effectively.

## Expected Behavior

Full VoiceOver support with:
- All interactive elements accessible and labeled
- State changes announced
- Logical navigation order
- Keyboard shortcuts for common actions
- Support for dynamic type

## Acceptance Criteria

- [ ] Add accessibility labels to overlay states that announce via VoiceOver
- [ ] Create an accessible alternative to the visual overlay (e.g., menu bar status announcements)
- [ ] Add `accessibilityLabel` and `accessibilityHint` to all interactive elements
- [ ] Group history card elements with `accessibilityElement(children: .combine)`
- [ ] Add accessibility traits (`.isButton`, `.isHeader`) where appropriate
- [ ] Announce state changes with `UIAccessibility.post(notification:)`
- [ ] Add keyboard shortcuts to History window (Cmd+C to copy selected, arrow keys to navigate)
- [ ] Support dynamic type with `.dynamicTypeSize()` or relative font sizes
- [ ] Test with VoiceOver enabled
- [ ] Add accessibility documentation to README

## Technical Notes

**Key views needing accessibility:**
- `Sources/Views/OverlayWindow.swift` - MinimalLineIndicator
- `Sources/Views/HistoryWindow.swift` - HistoryCard, variantCard
- `Sources/Views/SettingsView.swift` - All tabs
- `Sources/MurmelnApp.swift` - MenuContent

**SwiftUI accessibility modifiers:**
```swift
.accessibilityLabel("Recording in progress")
.accessibilityHint("Release Fn key to stop")
.accessibilityElement(children: .combine)
.accessibilityAddTraits(.isButton)
.accessibilityRemoveTraits(.isImage)
.accessibilityValue("50 percent")
```

**macOS accessibility notifications:**
```swift
NSAccessibility.post(element: NSApp, notification: .announcementRequested, userInfo: [.announcement: "Recording started"])
```

**Severity:** High

**Impact:** Inclusivity, compliance with accessibility standards
