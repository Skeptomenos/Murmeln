# Spec 006: Fix Right Option Double-Tap Detection Bug

## Problem Description

The Right Option double-tap detection fails when the Left Option key is also held, because the release detection checks the wrong flag.

### Current Implementation

```swift
// HotkeyService.swift:102-111
private func handleRightOptionKey(_ event: NSEvent) {
    let optionPressed = event.modifierFlags.contains(.option)
    let optionReleased = !event.modifierFlags.contains(.option) && rightOptionDown
    
    if optionPressed && !rightOptionDown {
        // ... handle press
    } else if optionReleased {
        // ... handle release - BUG: never triggers if Left Option held
    }
}
```

### Bug Scenario

1. User holds Left Option (for another purpose)
2. User double-taps Right Option to engage lock mode
3. `event.modifierFlags.contains(.option)` remains `true` even when Right Option is released
4. `optionReleased` is always `false` while Left Option is held
5. Double-tap detection fails, lock mode doesn't engage

## Expected Behavior

Right Option double-tap should work regardless of Left Option state.

## Acceptance Criteria

- [ ] Detect Right Option release using `keyCode` instead of modifier flags
- [ ] Add test case for Right Option tap while Left Option is held
- [ ] Verify lock mode engages correctly in all modifier combinations
- [ ] Test edge case: both Option keys pressed simultaneously

## Technical Notes

**Files to modify:**
- `Sources/Services/HotkeyService.swift`

**Fix:**
```swift
private func handleRightOptionKey(_ event: NSEvent) {
    let isRightOptionKey = event.keyCode == 0x3D  // kVK_RightOption
    
    // Check if this specific key was pressed or released
    let rightOptionCurrentlyDown = event.modifierFlags.contains(.option) && isRightOptionKey
    
    // For release, check if we were tracking it AND the event is for right option
    let rightOptionJustReleased = rightOptionDown && isRightOptionKey && 
        !event.modifierFlags.intersection([.option]).isEmpty == false
    
    // Alternative simpler approach: track via keyCode in flagsChanged
    if event.keyCode == 0x3D {  // Right Option
        if rightOptionDown && !event.modifierFlags.contains(.option) {
            // Right option was released (regardless of left option state)
            handleRightOptionReleased()
        } else if !rightOptionDown && event.modifierFlags.contains(.option) {
            // Right option was pressed
            handleRightOptionPressed()
        }
    }
}
```

**Note:** The `flagsChanged` event fires for each modifier change, so we can track Right Option specifically by checking `keyCode == 0x3D`.

**Severity:** High

**Impact:** Feature broken for users who use Left Option frequently

**Effort:** Low (30 minutes)

**Success Confidence:** 95%
