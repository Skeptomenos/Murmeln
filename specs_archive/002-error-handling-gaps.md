# Spec 002: Improve Error Handling and User Feedback

## Problem Description

Several areas of the codebase have weak or missing error handling, leading to silent failures and poor user experience:

1. **Silent File Cleanup Failures** (`AppState.swift:227-230`):
   ```swift
   try? FileManager.default.removeItem(at: url)
   if audioToProcess != url {
       try? FileManager.default.removeItem(at: audioToProcess)
   }
   ```
   Failed file deletions are silently ignored. This could lead to temp file accumulation.

2. **Empty Clipboard Paste** (`PasteService.swift:8-16`):
   No validation that text is non-empty before pasting. Empty text goes to clipboard and triggers paste action.

3. **API Error Truncation** (`NetworkService.swift:73-75, 106-108`, etc.):
   Raw API error responses are passed directly to users without sanitization. These often contain JSON or technical details unsuitable for end users.

4. **Missing Network Timeout Configuration**:
   All `URLSession.shared.data(for:)` calls use default timeout. Long network stalls could leave the app in processing state indefinitely.

5. **Microphone Error Not Actionable** (`AppState.swift:47-49`):
   When microphone permission is denied, the error message "Microphone permission denied" doesn't guide users to fix it.

6. **Ollama Connection Failures** (`OllamaService.swift:33-36`):
   When Ollama is not running, `isOllamaRunning` is set to false but no user-facing guidance is provided on how to start Ollama.

7. **Model Pull Errors** (`OllamaService.swift:85-87`):
   Error messages from model pulling are stored in `pullProgress` which may not be visible to users.

## Current Behavior

- Errors are logged to console (`print()`) but users see generic or technical error messages
- Silent failures accumulate temp files or leave operations incomplete
- Users have no guidance on how to resolve permission or configuration issues

## Expected Behavior

- User-friendly error messages with actionable guidance
- Proper cleanup with retry logic for temp files
- Network timeouts to prevent indefinite hangs
- Clear UI indication when external services (Ollama) are unavailable

## Acceptance Criteria

- [ ] Add retry logic for temp file cleanup with logging
- [ ] Validate text before attempting paste; skip if empty
- [ ] Sanitize API error messages for user display (extract meaningful message from JSON)
- [ ] Add configurable timeout to network requests (e.g., 60 seconds)
- [ ] Improve microphone permission error with "Open System Settings" button
- [ ] Add "How to start Ollama" help text when Ollama is not running
- [ ] Show model pull errors in an alert or visible status area
- [ ] Consider implementing a structured error display component

## Technical Notes

**Key files:**
- `Sources/Models/AppState.swift`
- `Sources/Services/NetworkService.swift`
- `Sources/Services/PasteService.swift`
- `Sources/Services/OllamaService.swift`
- `Sources/Services/PermissionService.swift`

**Severity:** High

**Impact:** User experience, reliability, debuggability

**Related patterns:**
The codebase already has some error display via `AppState.lastError` shown in the menu bar. This pattern should be extended and improved.
