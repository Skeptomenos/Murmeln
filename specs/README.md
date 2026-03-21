# Murmeln Open Issues

**Generated:** 2026-01-11  
**Source:** Comprehensive Code Review + Oracle Analysis  
**Previous Specs:** Archived to `specs_archive/` (all implemented)

## Summary

| Priority    | Count | Ship Blocker? |
|-------------|-------|---------------|
| 🔴 Critical | 0     | N/A           |
| 🟠 High     | 0     | N/A           |
| 🟡 Medium   | 0     | N/A           |
| 🟢 Low      | 0     | N/A           |

**All specs complete!** 🎉

## Issue Index

### ✅ Completed (v2.2.6 - v2.4.0)

| Spec | Issue | Status | Version |
|------|-------|--------|---------|
| [002](002-state-machine-race-condition.md) | State machine race condition (quick tap bug) | ✅ FIXED | v2.2.6 |
| [005](005-remove-sensitive-logs.md) | Sensitive transcription text logged to console | ✅ FIXED | v2.2.6 |
| [015](015-main-thread-blocking.md) | Thread.sleep blocks main thread in cleanupTempFile | ✅ FIXED | v2.2.6 |
| [006](006-right-option-modifier-bug.md) | Right Option double-tap bug with Left Option held | ✅ FIXED | v2.2.6 |
| [007](007-ollama-concurrent-pull-fix.md) | Ollama concurrent model pull race condition | ✅ FIXED | v2.2.6 |
| [004](004-gemini-api-key-header.md) | Gemini API key exposed in URL query parameter | ✅ FIXED | v2.2.7 |
| [001](001-api-key-security.md) | API keys stored in plain text UserDefaults | ✅ FIXED | v2.2.7 |
| [003](003-clipboard-preservation.md) | Clipboard content destroyed without restore | ✅ FIXED | v2.3.0 |
| [010](010-personal-dictionary-storage.md) | Personal dictionary uses brittle delimiter | ✅ FIXED | v2.3.1 |
| [011](011-document-secure-input-limitation.md) | Hotkey silently fails in Secure Input fields | ✅ FIXED | v2.3.2 |
| [014](014-url-input-validation.md) | No URL validation in Settings | ✅ FIXED | v2.3.3 |
| [009](009-history-storage-migration.md) | History stored in UserDefaults (scalability) | ✅ FIXED | v2.4.0 |

### 🟡 Medium Priority

| Spec | Issue | Effort | Confidence | Status |
|------|-------|--------|------------|--------|
| [008](008-audio-memory-optimization.md) | Audio files loaded entirely into memory | High | 80% | ✅ FIXED (v2.6.0) |

### 🟢 Low Priority

| Spec | Issue | Effort | Confidence | Status |
|------|-------|--------|------------|--------|
| [012](012-ollama-remote-url.md) | Hardcoded Ollama localhost URL | Low | 95% | ✅ FIXED (v2.5.0) |
| [013](013-keyboard-layout-paste.md) | Paste may fail on non-US keyboard layouts | Medium | 80% | ✅ FIXED (v2.7.0) |

## Release History

### v2.4.0 (Current - Reliability Release)
- ✅ [009] History Storage Migration - File-based storage with versioning and migration

### v2.3.3
- ✅ [014] URL Input Validation - ValidatedURLField with real-time feedback

### v2.3.2
- ✅ [011] Document Secure Input Limitation - Added Known Limitations to README

### v2.3.1
- ✅ [010] Personal Dictionary Storage - JSON array storage with migration

### v2.3.0
- ✅ [003] Clipboard Preservation - Save/restore clipboard during paste

### v2.2.7 (Security Release)
- ✅ [004] Gemini API key moved to header
- ✅ [001] API keys stored in Keychain

### v2.2.6 (Ship Blockers)
- ✅ [005] Sensitive logs wrapped in #if DEBUG
- ✅ [015] Thread.sleep replaced with async Task.sleep
- ✅ [006] Right Option release detection fixed
- ✅ [007] Ollama pullTask properly managed
- ✅ [002] State machine race condition fixed

## Recommended Next Steps

All specs are now complete! 🎉

### v2.7.0 (Completed - Internationalization)
- ✅ [013](013-keyboard-layout-paste.md) - Dynamic keyboard layout support via UCKeyTranslate

### v2.6.0 (Completed - Performance Release)
- ✅ [008](008-audio-memory-optimization.md) - Chunked audio processing and streaming uploads

### v2.5.0 (Completed)
- ✅ [012](012-ollama-remote-url.md) - Remote Ollama support

## Archived Specs

Previous specs (001-005) were fully implemented and have been moved to `specs_archive/`:
- 001-unused-dead-code.md ✅
- 002-error-handling-gaps.md ✅
- 003-missing-test-coverage.md ✅
- 004-accessibility-improvements.md ✅
- 005-swift6-concurrency-audit.md ✅

See `IMPLEMENTATION_PLAN.md` for detailed implementation guidance.
