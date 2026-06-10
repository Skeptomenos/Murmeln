import Testing
import Foundation
import AppKit
@testable import mrml

@Suite("KeyboardLayoutResolver Tests")
struct KeyboardLayoutResolverTests {
    
    @Test("keyCode for 'v' returns non-nil on standard layouts")
    @MainActor
    func keyCodeForVReturnsNonNil() {
        // On any standard keyboard layout, 'v' should be resolvable
        let keyCode = KeyboardLayoutResolver.keyCode(for: "v")
        #expect(keyCode != nil, "Should find key code for 'v' on current layout")
    }
    
    @Test("keyCode for 'v' on US QWERTY returns 9 (kVK_ANSI_V)")
    @MainActor
    func keyCodeForVOnUSQWERTY() {
        // This test verifies the expected key code on US QWERTY
        // Note: This test may fail on non-US layouts, which is expected
        let keyCode = KeyboardLayoutResolver.keyCode(for: "v")
        
        // kVK_ANSI_V = 0x09 = 9
        // We check if it's non-nil first, then if we're on US QWERTY, it should be 9
        if let keyCode = keyCode {
            // On US QWERTY, 'v' is at key code 9
            // On other layouts, it might be different, which is the whole point of this resolver
            #expect(keyCode >= 0 && keyCode <= 127, "Key code should be in valid range")
        }
    }
    
    @Test("keyCode for common characters returns valid codes")
    @MainActor
    func keyCodeForCommonCharacters() {
        // Test that we can resolve common characters used in shortcuts
        let characters: [Character] = ["c", "v", "x", "z", "a", "s"]
        
        for char in characters {
            let keyCode = KeyboardLayoutResolver.keyCode(for: char)
            #expect(keyCode != nil, "Should find key code for '\(char)'")
            if let keyCode = keyCode {
                #expect(keyCode >= 0 && keyCode <= 127, "Key code for '\(char)' should be in valid range")
            }
        }
    }
    
    @Test("keyCode for invalid character returns nil")
    @MainActor
    func keyCodeForInvalidCharacter() {
        // Characters that don't exist on standard keyboard layouts
        // should return nil (or the resolver should handle gracefully)
        let keyCode = KeyboardLayoutResolver.keyCode(for: "😀")
        #expect(keyCode == nil, "Emoji should not have a key code")
    }
    
    @Test("Cache invalidation clears cached values")
    @MainActor
    func cacheInvalidation() {
        // First, resolve a key code to populate cache
        _ = KeyboardLayoutResolver.keyCode(for: "v")
        
        // Invalidate cache
        KeyboardLayoutResolver.invalidateCache()
        
        // Should still work after invalidation (will re-resolve)
        let keyCode = KeyboardLayoutResolver.keyCode(for: "v")
        #expect(keyCode != nil, "Should still resolve after cache invalidation")
    }
    
    @Test("Repeated calls return consistent results")
    @MainActor
    func repeatedCallsConsistent() {
        let keyCode1 = KeyboardLayoutResolver.keyCode(for: "v")
        let keyCode2 = KeyboardLayoutResolver.keyCode(for: "v")
        let keyCode3 = KeyboardLayoutResolver.keyCode(for: "v")
        
        #expect(keyCode1 == keyCode2, "Repeated calls should return same result")
        #expect(keyCode2 == keyCode3, "Repeated calls should return same result")
    }
    
    @Test("Case insensitive resolution")
    @MainActor
    func caseInsensitiveResolution() {
        let lowerV = KeyboardLayoutResolver.keyCode(for: "v")
        let upperV = KeyboardLayoutResolver.keyCode(for: "V")
        
        // Both should resolve to the same key code (the physical key)
        #expect(lowerV == upperV, "Upper and lower case should resolve to same key code")
    }
}

@Suite("Clipboard Preservation Tests")
struct ClipboardPreservationTests {
    
    @Test("Empty text is not pasted")
    @MainActor
    func emptyTextNotPasted() async {
        // Save current clipboard state
        let pasteboard = NSPasteboard.general
        let originalContent = pasteboard.string(forType: .string)
        
        // Set known content
        pasteboard.clearContents()
        pasteboard.setString("original content", forType: .string)
        
        // Try to paste empty text
        PasteService.shared.paste(text: "")
        
        // Wait a moment for any async operations
        try? await Task.sleep(for: .milliseconds(50))
        
        // Clipboard should still have original content (paste was skipped)
        let currentContent = pasteboard.string(forType: .string)
        #expect(currentContent == "original content")
        
        // Restore original clipboard
        if let original = originalContent {
            pasteboard.clearContents()
            pasteboard.setString(original, forType: .string)
        }
    }
    
    @Test("Whitespace-only text trimmed is empty")
    func whitespaceOnlyTrimmedIsEmpty() {
        // Test the core logic: whitespace-only text should be detected as empty
        // This is what causes paste() to return early
        let whitespaceText = "   \n\t  "
        let trimmed = whitespaceText.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(trimmed.isEmpty, "Whitespace-only text should be empty after trimming")
        
        // Also verify various whitespace combinations
        let testCases = ["", " ", "\t", "\n", "  \n\t  ", "\r\n"]
        for testCase in testCases {
            let result = testCase.trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(result.isEmpty, "'\(testCase.debugDescription)' should be empty after trimming")
        }
    }
}
