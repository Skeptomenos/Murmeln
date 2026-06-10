import Foundation
import AppKit
import Carbon.HIToolbox

// MARK: - Keyboard Layout Resolver

/// Resolves key codes for characters dynamically based on the current keyboard layout.
/// This ensures paste works correctly on non-US keyboard layouts (Dvorak, Colemak, AZERTY, etc.)
@MainActor
enum KeyboardLayoutResolver {
    /// Cache for resolved key codes, keyed by layout source ID
    private static var cache: [String: [Character: CGKeyCode]] = [:]
    private static var currentLayoutID: String?
    
    /// Returns the key code for a given character on the current keyboard layout.
    /// Returns nil if the character cannot be found on the current layout.
    static func keyCode(for character: Character) -> CGKeyCode? {
        let layoutID = getCurrentLayoutID()
        
        // Check cache first
        if layoutID == currentLayoutID, let cached = cache[layoutID]?[character] {
            return cached
        }
        
        // Invalidate cache if layout changed
        if layoutID != currentLayoutID {
            cache.removeAll()
            currentLayoutID = layoutID
        }
        
        // Resolve the key code
        guard let keyCode = resolveKeyCode(for: character) else {
            return nil
        }
        
        // Cache the result
        if cache[layoutID] == nil {
            cache[layoutID] = [:]
        }
        cache[layoutID]?[character] = keyCode
        
        return keyCode
    }
    
    /// Clears the cache. Call this when the keyboard layout changes.
    static func invalidateCache() {
        cache.removeAll()
        currentLayoutID = nil
    }
    
    // MARK: - Private Implementation
    
    private static func getCurrentLayoutID() -> String {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else {
            return "unknown"
        }
        if let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
            let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
            return id
        }
        return "unknown"
    }
    
    private static func resolveKeyCode(for character: Character) -> CGKeyCode? {
        // Get current keyboard layout
        var currentKeyboard = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        var rawLayoutData = TISGetInputSourceProperty(currentKeyboard, kTISPropertyUnicodeKeyLayoutData)
        
        // Fallback to ASCII-capable layout if current doesn't have layout data
        if rawLayoutData == nil {
            currentKeyboard = TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeUnretainedValue()
            rawLayoutData = TISGetInputSourceProperty(currentKeyboard, kTISPropertyUnicodeKeyLayoutData)
        }
        
        guard let layoutData = rawLayoutData else {
            #if DEBUG
            print("⚠️ KeyboardLayoutResolver: Could not get keyboard layout data")
            #endif
            return nil
        }
        
        // Convert to Data for safe memory access
        let cfData = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue() as Data
        let targetString = String(character).lowercased()
        
        // Iterate through all possible key codes (0-127)
        for keyCode in UInt16(0)...UInt16(127) {
            if let translated = translate(keyCode: keyCode, layoutData: cfData),
               translated.lowercased() == targetString {
                return CGKeyCode(keyCode)
            }
        }
        
        #if DEBUG
        print("⚠️ KeyboardLayoutResolver: Could not find key code for '\(character)'")
        #endif
        return nil
    }
    
    private static func translate(keyCode: UInt16, layoutData: Data) -> String? {
        var deadKeyState: UInt32 = 0
        let maxLength = 4
        var chars = [UniChar](repeating: 0, count: maxLength)
        var actualLength = 0
        
        let status = layoutData.withUnsafeBytes { pointer -> OSStatus in
            guard let layoutPtr = pointer.bindMemory(to: UCKeyboardLayout.self).baseAddress else {
                return OSStatus(kUCKeyTranslateNoDeadKeysBit)
            }
            
            return UCKeyTranslate(
                layoutPtr,
                keyCode,
                UInt16(kUCKeyActionDown),
                0, // No modifiers
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                maxLength,
                &actualLength,
                &chars
            )
        }
        
        guard status == noErr, actualLength > 0 else {
            return nil
        }
        
        return String(utf16CodeUnits: chars, count: actualLength)
    }
}

// MARK: - Saved Clipboard Item

/// Represents saved clipboard content for restoration after paste
struct SavedClipboardItem: Sendable {
    let types: [NSPasteboard.PasteboardType]
    let dataByType: [NSPasteboard.PasteboardType: Data]
}

struct PasteTiming: Sendable {
    let succeeded: Bool
    let commandSentElapsedMs: UInt64
    let totalElapsedMs: UInt64
    var blocker: PasteBlocker? = nil
}

/// A detectable reason a synthetic Cmd+V cannot be delivered.
/// Paste delivery cannot be positively confirmed (the target app reads the
/// pasteboard, it never writes), so honest success means ruling out every
/// failure mode we can detect. The Tier 2 dogfood checklist covers the rest.
enum PasteBlocker: String, Sendable {
    case clipboardWriteFailed = "clipboard_write_failed"
    case accessibilityNotTrusted = "accessibility_not_trusted"
    case secureInputActive = "secure_input_active"
    case keyEventCreationFailed = "key_event_creation_failed"
}

final class PasteService: Sendable {
    @MainActor static let shared = PasteService()

    /// Pure preflight decision: can a synthetic Cmd+V be delivered at all?
    static func preflightBlocker(axTrusted: Bool, secureInputActive: Bool) -> PasteBlocker? {
        if !axTrusted { return .accessibilityNotTrusted }
        if secureInputActive { return .secureInputActive }
        return nil
    }

    /// Pure restore decision: restore the saved clipboard only if the
    /// pasteboard still holds our transcript write. If the changeCount moved,
    /// someone (the user copying, another app) wrote newer content during the
    /// paste window — restoring would clobber it.
    static func shouldRestoreClipboard(changeCountAtWrite: Int, currentChangeCount: Int) -> Bool {
        currentChangeCount == changeCountAtWrite
    }
    
    /// Pastes text and restores the original clipboard contents afterward
    func paste(text: String, captureID: String? = nil) {
        Task { @MainActor in
            _ = await self.pasteAndRestore(text: text, captureID: captureID)
        }
    }

    @MainActor
    func pasteAndRestore(text: String, captureID: String? = nil) async -> PasteTiming {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        logDiagnostics("paste.requested", captureID: captureID, metadata: [
            "text_chars": String(text.count),
            "trimmed_text_chars": String(trimmed.count)
        ])

        guard !trimmed.isEmpty else {
            #if DEBUG
            print("⚠️ Skipping paste: text is empty")
            #endif
            logDiagnostics("paste.skipped_empty", captureID: captureID, metadata: [
                "reason": "empty_text",
                "text_chars": String(text.count),
                "trimmed_text_chars": String(trimmed.count)
            ])
            return PasteTiming(succeeded: false, commandSentElapsedMs: 0, totalElapsedMs: 0)
        }

        let pasteStartNs = DispatchTime.now().uptimeNanoseconds

        let pasteboard = NSPasteboard.general

        // Save current clipboard contents before clearing
        let savedItems = saveClipboard(from: pasteboard)
        #if DEBUG
        print("📋 Saved \(savedItems.count) clipboard item(s) with \(savedItems.flatMap { $0.types }.count) type(s)")
        #endif

        // Set new content
        pasteboard.clearContents()
        let wroteTranscript = pasteboard.setString(text, forType: .string)
        if !wroteTranscript {
            return failPaste(.clipboardWriteFailed, captureID: captureID, pasteStartNs: pasteStartNs)
        }
        let changeCountAtWrite = pasteboard.changeCount

        // Preflight: a synthetic Cmd+V cannot be delivered without Accessibility
        // trust, and Secure Input swallows it silently. On failure the transcript
        // stays on the clipboard (no restore) so the user can paste manually.
        if let blocker = Self.preflightBlocker(
            axTrusted: AXIsProcessTrusted(),
            secureInputActive: IsSecureEventInputEnabled()
        ) {
            return failPaste(blocker, captureID: captureID, pasteStartNs: pasteStartNs)
        }

        // Wait for clipboard to settle, then simulate paste
        try? await Task.sleep(for: .milliseconds(100))
        let keyEventsPosted = self.simulatePaste()
        let pasteTriggeredNs = DispatchTime.now().uptimeNanoseconds
        let commandElapsedMs = (pasteTriggeredNs - pasteStartNs) / 1_000_000
        if !keyEventsPosted {
            return failPaste(
                .keyEventCreationFailed,
                captureID: captureID,
                pasteStartNs: pasteStartNs,
                commandSentElapsedMs: commandElapsedMs
            )
        }
        logDiagnostics("paste.command_sent", captureID: captureID, metadata: [
            "elapsed_ms": String(commandElapsedMs)
        ])

        // Wait for paste to complete, then restore the original clipboard —
        // but only if nothing else wrote to it during the window (M2).
        try? await Task.sleep(for: .milliseconds(200))
        let restoredItemCount: Int
        if Self.shouldRestoreClipboard(changeCountAtWrite: changeCountAtWrite, currentChangeCount: pasteboard.changeCount) {
            restoreClipboard(savedItems, to: pasteboard)
            restoredItemCount = savedItems.count
            #if DEBUG
            print("📋 Restored \(savedItems.count) clipboard item(s)")
            #endif
        } else {
            restoredItemCount = 0
            #if DEBUG
            print("📋 Restore skipped — clipboard changed during paste window")
            #endif
            logDiagnostics("paste.restore_skipped", captureID: captureID, metadata: [
                "reason": "clipboard_changed_during_paste"
            ])
        }

        let pasteEndNs = DispatchTime.now().uptimeNanoseconds
        let totalElapsedMs = (pasteEndNs - pasteStartNs) / 1_000_000
        logDiagnostics("paste.complete", captureID: captureID, metadata: [
            "elapsed_ms": String(totalElapsedMs),
            "restored_items": String(restoredItemCount),
            "succeeded": String(true)
        ])

        return PasteTiming(
            succeeded: true,
            commandSentElapsedMs: commandElapsedMs,
            totalElapsedMs: totalElapsedMs
        )
    }

    /// Records an honest paste failure. The saved clipboard is deliberately NOT
    /// restored: the transcript must survive on the clipboard, losing the user's
    /// previous clipboard item is the lesser harm than losing the dictation.
    @MainActor
    private func failPaste(
        _ blocker: PasteBlocker,
        captureID: String?,
        pasteStartNs: UInt64,
        commandSentElapsedMs: UInt64 = 0
    ) -> PasteTiming {
        let totalElapsedMs = (DispatchTime.now().uptimeNanoseconds - pasteStartNs) / 1_000_000
        #if DEBUG
        print("⚠️ Paste failed (\(blocker.rawValue)) — transcript left on clipboard")
        #endif
        logDiagnostics("paste.failed", captureID: captureID, metadata: [
            "reason": blocker.rawValue,
            "clipboard_preserved": String(true),
            "elapsed_ms": String(totalElapsedMs),
            "succeeded": String(false)
        ])
        return PasteTiming(
            succeeded: false,
            commandSentElapsedMs: commandSentElapsedMs,
            totalElapsedMs: totalElapsedMs,
            blocker: blocker
        )
    }
    
    // MARK: - Clipboard Save/Restore
    
    /// Saves all items from the pasteboard, preserving all types and their data
    private func saveClipboard(from pasteboard: NSPasteboard) -> [SavedClipboardItem] {
        guard let items = pasteboard.pasteboardItems else {
            return []
        }
        
        var savedItems: [SavedClipboardItem] = []
        for item in items {
            var dataByType: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dataByType[type] = data
                }
            }
            if !dataByType.isEmpty {
                savedItems.append(SavedClipboardItem(types: item.types, dataByType: dataByType))
            }
        }
        return savedItems
    }
    
    /// Restores previously saved items to the pasteboard
    private func restoreClipboard(_ savedItems: [SavedClipboardItem], to pasteboard: NSPasteboard) {
        guard !savedItems.isEmpty else { return }
        
        pasteboard.clearContents()
        
        for savedItem in savedItems {
            let item = NSPasteboardItem()
            // Restore in original type order to preserve priority
            for type in savedItem.types {
                if let data = savedItem.dataByType[type] {
                    item.setData(data, forType: type)
                }
            }
            pasteboard.writeObjects([item])
        }
    }
    
    // MARK: - Paste Simulation
    
    @MainActor
    private func simulatePaste() -> Bool {
        // Try dynamic key code resolution first (works on all keyboard layouts)
        if let vKeyCode = KeyboardLayoutResolver.keyCode(for: "v") {
            #if DEBUG
            print("⌨️ Simulating paste via CGEvent with resolved key code: \(vKeyCode)")
            #endif
            return simulatePasteWithKeyCode(vKeyCode)
        }

        // Fallback 1: Try hardcoded US QWERTY key code (works for most users)
        #if DEBUG
        print("⚠️ KeyboardLayoutResolver failed, trying hardcoded kVK_ANSI_V")
        #endif
        return simulatePasteWithKeyCode(CGKeyCode(kVK_ANSI_V))

        // Note: If CGEvent paste fails (e.g., in Secure Input mode),
        // there's no reliable fallback. AppleScript keystroke also fails
        // in Secure Input contexts for the same security reasons.
    }

    private func simulatePasteWithKeyCode(_ keyCode: CGKeyCode) -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)

        guard let cmdVDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let cmdVUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return false
        }
        cmdVDown.flags = .maskCommand
        cmdVUp.flags = .maskCommand

        cmdVDown.post(tap: .cgSessionEventTap)
        cmdVUp.post(tap: .cgSessionEventTap)
        return true
    }

    private func logDiagnostics(_ event: String, captureID: String?, metadata: [String: String] = [:]) {
        Task {
            await CaptureDiagnostics.shared.mark(event, captureID: captureID, metadata: metadata)
        }
    }
    
}
