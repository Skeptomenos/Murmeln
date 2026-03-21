# Spec 001: Remove Unused/Dead Code

## Problem Description

Several pieces of code in the codebase are defined but never used, creating unnecessary complexity and maintenance burden:

1. **`Shortcuts.swift`** (Sources/Models/Shortcuts.swift) - Defines `KeyboardShortcuts.Name.toggleRecording` but it is never referenced anywhere in the codebase. The AGENTS.md explicitly states "KeyboardShortcuts: External dependency for potential future hotkey customization (currently unused for Fn)".

2. **`VisualizerView.swift`** (Sources/Views/VisualizerView.swift) - Defines a complete `VisualizerView` component but it is never instantiated or used anywhere. The app uses `AudioBarsView` in `OverlayWindow.swift` instead, and even that is defined but not used (the overlay uses `MinimalLineIndicator`).

3. **`transcribeAndRefineWithOriginal`** method in `AppState.swift:239-273` - This private method is fully implemented but never called from anywhere in the codebase.

4. **`copyToClipboard`** method in `MurmelnApp.swift:116-119` - Defined in `MenuContent` but never used within that view.

5. **`getDefaultModels`** method in `ModelDiscoveryService.swift:214-225` - Private method that just calls `getRefinementModels` and is never called.

6. **`simulatePasteViaAppleScript`** method in `PasteService.swift:32-46` - Defined as a fallback but never called; only `simulatePasteViaCGEvent` is used.

## Current Behavior

The dead code is compiled and shipped with the app, increasing binary size and creating confusion for future maintainers who may think these features are active.

## Expected Behavior

Either:
1. Remove the dead code entirely, OR
2. Integrate the unused features properly (e.g., add keyboard shortcut customization, use the AppleScript fallback when CGEvent fails)

## Acceptance Criteria

- [ ] Remove or repurpose `Shortcuts.swift` and its keyboard shortcut definition
- [ ] Remove `VisualizerView.swift` and unused `AudioBarsView` from `OverlayWindow.swift`
- [ ] Remove `transcribeAndRefineWithOriginal` from `AppState.swift` 
- [ ] Remove or use `copyToClipboard` in `MenuContent`
- [ ] Remove `getDefaultModels` from `ModelDiscoveryService.swift`
- [ ] Either implement AppleScript fallback logic or remove `simulatePasteViaAppleScript`
- [ ] Verify app builds and tests pass after cleanup

## Technical Notes

**File locations:**
- `Sources/Models/Shortcuts.swift:1-6`
- `Sources/Views/VisualizerView.swift:1-32`
- `Sources/Models/AppState.swift:239-273`
- `Sources/MurmelnApp.swift:116-119`
- `Sources/Services/ModelDiscoveryService.swift:214-225`
- `Sources/Services/PasteService.swift:32-46`
- `Sources/Views/OverlayWindow.swift:246-289` (AudioBarsView)

**Severity:** Medium

**Impact:** Code maintainability, binary size, developer confusion
