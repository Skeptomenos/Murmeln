# Murmeln Implementation Plan

> Historical implementation log for the v2.2.6-v2.7.0 backlog. This file is not the active roadmap for current Murmeln planning.

**Generated:** 2026-01-11 (Verified: 2026-01-11 02:31 UTC)
**Based on:** specs/README.md + Code Verification + Oracle Analysis + Explore Agent Verification
**Status:** Phase 6 COMPLETE - v2.7.0 released - ALL SPECS COMPLETE 🎉

## Executive Summary

Phase 6 (Keyboard Layout Paste) completed on 2026-01-11. **All specs are now complete**, verified with 281 passing tests.

| Priority | Count | Status |
|----------|-------|--------|
| Critical (Ship Blockers) | 3 | **ALL FIXED** (v2.2.6) |
| High Priority (Security) | 2 | **ALL FIXED** (v2.2.7) |
| High Priority (UX) | 1 | **FIXED** (v2.3.0) |
| Medium Priority | 4 | **ALL FIXED** (v2.3.1, v2.3.3, v2.4.0, v2.6.0) |
| Low Priority | 3 | **ALL FIXED** (v2.3.2, v2.5.0, v2.7.0) |

---

## Phase 1: v2.3.0 Release (Ship Blockers) - COMPLETED

### 1.1 [005] Remove Sensitive Logs
**Priority:** CRITICAL | **Effort:** 30 min | **Status:** FIXED (v2.2.6)

**Problem Verified:**
- 24 `print()` statements found across 4 files
- NO `#if DEBUG` guards found (grep returned 0 matches)
- NO `os.Logger` usage found (grep returned 0 matches)
- Transcription text logged: `print("✅ Baseline obtained: '\(originalText)'")`

**Required Fix:**
1. Wrap all `print()` in `#if DEBUG ... #endif`
2. OR migrate to `os.Logger` with `privacy: .private` for sensitive data

**Files:**
- `Sources/Models/AppState.swift` (15 prints)
- `Sources/Services/AudioService.swift` (5 prints)
- `Sources/Services/PasteService.swift` (2 prints)
- `Sources/Services/UpdateService.swift` (2 prints)

---

### 1.2 [002] State Machine Race Condition
**Priority:** CRITICAL | **Effort:** 2-3 hours | **Status:** FIXED (v2.2.6)

**Problem Verified:**
```swift
// AppState.swift lines 54-63
recordingTask = Task {
    let hasPermission = await PermissionService.shared.checkMicrophonePermission()  // Line 55: AWAIT
    // ... 
    isRecording = true  // Line 63: State set AFTER await
}
```
If Fn released during the await, `stopAndProcess()` returns early (line 85: `guard isRecording else { return }`).

**Required Fix (Oracle Recommended - Enum Approach):**
1. Change `isRecording: Bool` to `enum RecordingState { case idle, requestingPermission, recording, processing }`
2. Set state to `.requestingPermission` synchronously BEFORE Task creation
3. Transition to `.recording` after successful start
4. Update `stopAndProcess()` to handle `.requestingPermission` state (wait or cancel)
5. Update SwiftUI bindings that depend on `isRecording`

**Why Enum over Quick Fix:** The enum approach solves the root cause (state management) rather than patching symptoms. It eliminates invalid state transitions.

**Files:** `Sources/Models/AppState.swift`, potentially `Sources/Views/*.swift`

---

### 1.3 [015] Main Thread Blocking in cleanupTempFile
**Priority:** CRITICAL | **Effort:** 15 min | **Status:** FIXED (v2.2.6)

**Problem Verified:**
```swift
// AppState.swift line 256
Thread.sleep(forTimeInterval: 0.1 * Double(attempt))
```
`AppState` is marked `@MainActor`. Calling `Thread.sleep` pauses the **Main Thread**, causing the entire UI to freeze for up to 0.6 seconds (sum of retries).

**Required Fix:**
1. Make `cleanupTempFile` async
2. Replace `Thread.sleep` with `try? await Task.sleep(for: .milliseconds(...))`

**Files:** `Sources/Models/AppState.swift`

---

### 1.4 [006] Right Option Modifier Bug
**Priority:** HIGH | **Effort:** 30 min | **Status:** FIXED (v2.2.6)

**Problem Verified (Oracle Confirmed):**
```swift
// HotkeyService.swift lines 103-104
let isRightOption = event.modifierFlags.contains(.option) && event.keyCode == kVK_RightOption
let optionReleased = !event.modifierFlags.contains(.option) && rightOptionDown
```

**Bug Scenario:**
1. User holds Left Option
2. User presses Right Option → `rightOptionDown = true`
3. User releases Right Option (Left still held) → `modifierFlags` still contains `.option`
4. `optionReleased` evaluates to `false` → lock/dictation never triggers

**Required Fix:**
- Track Right Option release via `keyCode == kVK_RightOption` on keyUp event
- Don't rely on aggregate modifier flags for release detection

**Files:** `Sources/Services/HotkeyService.swift`

---

### 1.5 [007] Ollama Concurrent Pull Fix
**Priority:** HIGH | **Effort:** 30 min | **Status:** FIXED (v2.2.6)

**Problem Verified:**
```swift
// OllamaService.swift
private var pullTask: Task<Void, Never>?  // Line 19: Declared but NEVER USED

func pullModel(_ modelName: String) async -> Bool {
    // No cancellation of existing pullTask
    // No assignment to pullTask
    isPulling = true  // Just sets flag
```

**Required Fix:**
1. Cancel existing `pullTask` before starting new pull: `pullTask?.cancel()`
2. Assign new Task to `pullTask`
3. Add `@Published var pullingModelName: String?` for UI clarity
4. Handle cancellation in the streaming loop

**Files:** `Sources/Services/OllamaService.swift`

---

## Phase 2: v2.4.0 Security Release - COMPLETED

### 2.1 [004] Gemini API Key Header
**Priority:** HIGH | **Effort:** 1 hour | **Status:** FIXED (v2.2.7)

**Problem Verified:**
```swift
// NetworkService.swift lines 188, 288
guard let url = URL(string: "\(baseURL)/models/\(model):generateContent?key=\(apiKey)") else {

// ModelDiscoveryService.swift lines 150, 179
guard let url = URL(string: "\(baseURL)/models?key=\(apiKey)") else {
```
API key in URL query parameter, exposed in logs/proxies.

**Fix Applied:**
1. ✅ Moved API key to `x-goog-api-key` header in NetworkService.swift
2. ✅ Moved API key to `x-goog-api-key` header in ModelDiscoveryService.swift
3. ✅ Updated tests to verify header-based authentication

**Files Modified:**
- `Sources/Services/NetworkService.swift`
- `Sources/Services/ModelDiscoveryService.swift`
- `Tests/MurmelnTests.swift`

---

### 2.2 [001] API Key Security (Keychain)
**Priority:** CRITICAL | **Effort:** 4-6 hours | **Status:** FIXED (v2.2.7)

**Problem:** API keys in plain text UserDefaults, readable by any process.

**Fix Applied:**
1. ✅ Created `Sources/Services/KeychainService.swift` with save/retrieve/delete/exists operations
2. ✅ Updated `AppSettings.swift` to use KeychainService for API keys
3. ✅ Implemented one-time migration from UserDefaults to Keychain on first launch
4. ✅ Added fallback to UserDefaults if Keychain fails
5. ✅ Added 15 tests for KeychainService

**Files Modified:**
- `Sources/Services/KeychainService.swift` (new)
- `Sources/Models/AppSettings.swift`
- `Tests/ServiceTests/KeychainServiceTests.swift` (new)

---

## Phase 3: v2.3.0 Reliability Release - IN PROGRESS

### 3.1 [003] Clipboard Preservation
**Priority:** HIGH | **Effort:** 2-3 hours | **Status:** ✅ FIXED (v2.3.0)

**Problem:** User's clipboard destroyed during paste, never restored.

**Fix Applied:**
1. ✅ Created `SavedClipboardItem` struct to store clipboard data
2. ✅ Implemented `saveClipboard()` to capture all NSPasteboardItems with all types
3. ✅ Implemented `restoreClipboard()` to restore saved items after paste
4. ✅ Modified `paste()` to save before clearing, restore 200ms after paste
5. ✅ Added 8 tests for clipboard preservation

**Files Modified:**
- `Sources/Services/PasteService.swift`
- `Tests/ServiceTests/PasteServiceTests.swift` (new)

---

### 3.2 [008] Audio Memory Optimization
**Priority:** MEDIUM | **Effort:** 4-6 hours | **Status:** ✅ FIXED (v2.6.0)

**Problem:** Audio loaded entirely into memory (3x file size peak).

**Fix Applied:**
1. ✅ Refactored `hasAudibleSpeech` to use 10-second chunked reading
2. ✅ Refactored `trimSilence` to use two-pass chunked processing (find boundaries, then copy)
3. ✅ Created streaming multipart upload helper using file-based body
4. ✅ Updated `transcribeOpenAICompatible` to use streaming file upload
5. ✅ Updated `transcribeLocalWhisper` to use streaming file upload
6. ✅ Added 8 tests for chunked audio processing and streaming uploads

**Files Modified:**
- `Sources/Services/AudioService.swift`
- `Sources/Services/NetworkService.swift`
- `Tests/MurmelnTests.swift`

**Note:** GPT-4o and Gemini still require Base64 in JSON body (API limitation), but OpenAI/Groq/LocalWhisper now use memory-efficient streaming.

---

### 3.3 [009] History Storage Migration
**Priority:** MEDIUM | **Effort:** 3-4 hours | **Status:** ✅ FIXED (v2.4.0)

**Problem:** History in UserDefaults blocks main thread, no versioning.

**Fix Applied:**
1. ✅ Created `HistoryStorage` struct with version field for schema versioning
2. ✅ Moved storage to `~/Library/Application Support/Murmeln/history.json`
3. ✅ Async save via `Task.detached` with atomic writes (temp file + rename)
4. ✅ One-time migration from UserDefaults with cleanup
5. ✅ Proper error handling with `os.Logger` instead of print
6. ✅ Added 12 tests for HistoryStorage and migration

**Files Modified:**
- `Sources/Models/HistoryStore.swift`
- `Tests/HistoryStoreTests.swift`

---

## Phase 4: Future Enhancements

### 4.1 [010] Personal Dictionary Storage
**Priority:** MEDIUM | **Effort:** 1 hour | **Status:** ✅ FIXED (v2.3.1)

**Problem:** Brittle `|||` delimiter can corrupt data.

**Fix Applied:**
1. ✅ Implemented JSON array storage via `@AppStorage("personalDictionaryJSON")`
2. ✅ Added lazy migration from old `|||` delimiter format
3. ✅ Old storage cleared after successful migration
4. ✅ Added 4 tests for JSON storage, special characters, and migration

**Files Modified:**
- `Sources/Models/AppSettings.swift`
- `Tests/AppSettingsTests.swift`

---

### 4.2 [011] Document Secure Input Limitation
**Priority:** MEDIUM | **Effort:** 30 min | **Status:** ✅ FIXED (v2.3.2)

**Fix Applied:**
1. ✅ Added "Known Limitations" section to README.md
2. ✅ Documented Secure Input behavior and why it exists
3. ✅ Listed common affected contexts (password fields, Terminal, password managers)
4. ✅ Provided workaround (click outside field or use menu bar)

**Files Modified:**
- `README.md`

---

### 4.3 [014] URL Input Validation
**Priority:** MEDIUM | **Effort:** 2 hours | **Status:** ✅ FIXED (v2.3.3)

**Fix Applied:**
1. ✅ Created `URLValidation` enum with `validate()` and `isValid()` methods
2. ✅ Created `ValidatedURLField` SwiftUI component with real-time feedback
3. ✅ Replaced transcriptionBaseURL TextField with ValidatedURLField
4. ✅ Replaced refinementBaseURL TextField with ValidatedURLField
5. ✅ URL normalization: trims whitespace, removes trailing slashes
6. ✅ Visual feedback: green checkmark for valid, red X with error message for invalid
7. ✅ Added 14 tests for URL validation logic

**Files Modified:**
- `Sources/Views/SettingsView.swift`
- `Tests/MurmelnTests.swift`

---

### 4.4 [012] Ollama Remote URL
**Priority:** LOW | **Effort:** 1 hour | **Status:** ✅ FIXED (v2.5.0)

**Problem:** Hardcoded `localhost:11434` prevents remote Ollama usage.

**Fix Applied:**
1. ✅ Added `@AppStorage("ollamaBaseURL")` to AppSettings.swift with default `http://localhost:11434`
2. ✅ Created `baseURL` computed property in OllamaService.swift with normalization (trim whitespace, remove trailing slashes)
3. ✅ Replaced all 4 hardcoded URLs with dynamic `baseURL` interpolation
4. ✅ Added ValidatedURLField in SettingsView.swift ollamaManagementSection with onChange trigger for status check
5. ✅ Added 6 tests for URL normalization logic

**Files Modified:**
- `Sources/Models/AppSettings.swift`
- `Sources/Services/OllamaService.swift`
- `Sources/Views/SettingsView.swift`
- `Tests/ServiceTests/OllamaServiceTests.swift`

---

### 4.5 [013] Keyboard Layout Paste
**Priority:** LOW | **Effort:** 4-6 hours | **Status:** ✅ FIXED (v2.7.0)

**Problem:** Paste used hardcoded key code 0x09 (V on US QWERTY) which fails on Dvorak, Colemak.

**Fix Applied:**
1. ✅ Created `KeyboardLayoutResolver` enum with `keyCode(for:)` method
2. ✅ Implemented `UCKeyTranslate` dynamic resolution (iterates key codes 0-127)
3. ✅ Added caching by keyboard layout source ID with automatic invalidation on layout change
4. ✅ Added AppleScript fallback method for edge cases
5. ✅ Updated `simulatePaste()` to use resolver with fallback to hardcoded kVK_ANSI_V
6. ✅ Added 7 tests for KeyboardLayoutResolver

**Files Modified:**
- `Sources/Services/PasteService.swift`
- `Tests/ServiceTests/PasteServiceTests.swift`

---

## Implementation Order (Recommended)

| Order | Spec | Effort | Cumulative | Notes |
|-------|------|--------|------------|-------|
| 1 | [005] Remove Sensitive Logs | 30 min | 30 min | Privacy - quick win |
| 2 | [NEW] Thread.sleep fix | 15 min | 45 min | UI freeze - quick win |
| 3 | [006] Right Option Bug | 30 min | 1.25 hours | UX fix |
| 4 | [007] Ollama Concurrent Pull | 30 min | 1.75 hours | Stability |
| 5 | [002] State Machine Race | 2-3 hours | 4.5 hours | Core stability |
| 6 | [004] Gemini API Header | 1 hour | 5.5 hours | Security |
| 7 | [001] Keychain Migration | 4-6 hours | 11 hours | Security |
| 8 | [003] Clipboard Preservation | 2-3 hours | 14 hours | UX |
| 9 | [010] Dictionary Storage | 1 hour | 15 hours | Data integrity |
| 10 | [011] Document Limitation | 30 min | 15.5 hours | Documentation |
| 11 | [014] URL Validation | 2 hours | 17.5 hours | UX |
| 12 | [009] History Migration | 3-4 hours | 21 hours | Performance |
| 13 | [012] Ollama Remote URL | 1 hour | 22 hours | Feature |
| 14 | [008] Audio Memory | 6-8 hours | 29 hours | Performance |
| 15 | [013] Keyboard Layout | 4-6 hours | 35 hours | Internationalization |

---

## Dependencies

- [007] should be fixed before [012] (both touch OllamaService)
- [001] Keychain should be done before any security audit
- [008] and [009] are independent, can be parallelized
- [005] is prerequisite for any production release
- [NEW] Thread.sleep fix is trivial and should be done early

---

## Test Coverage Gaps (for reference)

| Component | Coverage | Notes |
|-----------|----------|-------|
| AudioService | Low | Recording flow untested |
| PasteService | Minimal | Only Sendable conformance |
| PermissionService | Minimal | Only Sendable conformance |
| NetworkService | Medium | Parsing covered, execution not |
| UI Views | None | No snapshot tests |

---

## Corrections to specs/README.md

The following status claims in specs/README.md are **incorrect** and should be updated:

1. **[007]** marked as "pullTask pattern implemented" - **FALSE**: `pullTask` is declared but never used
2. **[006]** marked as "NEEDS VERIFICATION" - **CONFIRMED**: Bug exists in release detection logic

---

## New Spec Required

A new spec file should be created for the Thread.sleep issue:

**File:** `specs/015-main-thread-blocking.md`
**Issue:** `Thread.sleep` called on `@MainActor` in `cleanupTempFile`
**Priority:** CRITICAL
**Effort:** 15 min

---

*Plan validated by Oracle analysis. Ready for build phase.*
