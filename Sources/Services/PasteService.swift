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

final class PasteService: Sendable {
    @MainActor static let shared = PasteService()
    
    /// Pastes text and restores the original clipboard contents afterward
    func paste(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            #if DEBUG
            print("⚠️ Skipping paste: text is empty")
            #endif
            return
        }
        
        Task { @MainActor in
            let pasteboard = NSPasteboard.general
            
            // Save current clipboard contents before clearing
            let savedItems = saveClipboard(from: pasteboard)
            #if DEBUG
            print("📋 Saved \(savedItems.count) clipboard item(s) with \(savedItems.flatMap { $0.types }.count) type(s)")
            #endif
            
            // Set new content
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            
            // Wait for clipboard to settle, then simulate paste
            try? await Task.sleep(for: .milliseconds(100))
            self.simulatePaste()
            
            // Wait for paste to complete, then restore original clipboard
            try? await Task.sleep(for: .milliseconds(200))
            restoreClipboard(savedItems, to: pasteboard)
            #if DEBUG
            print("📋 Restored \(savedItems.count) clipboard item(s)")
            #endif
        }
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
    private func simulatePaste() {
        // Try dynamic key code resolution first (works on all keyboard layouts)
        if let vKeyCode = KeyboardLayoutResolver.keyCode(for: "v") {
            #if DEBUG
            print("⌨️ Simulating paste via CGEvent with resolved key code: \(vKeyCode)")
            #endif
            simulatePasteWithKeyCode(vKeyCode)
            return
        }
        
        // Fallback 1: Try hardcoded US QWERTY key code (works for most users)
        #if DEBUG
        print("⚠️ KeyboardLayoutResolver failed, trying hardcoded kVK_ANSI_V")
        #endif
        simulatePasteWithKeyCode(CGKeyCode(kVK_ANSI_V))
        
        // Note: If CGEvent paste fails (e.g., in Secure Input mode), 
        // there's no reliable fallback. AppleScript keystroke also fails
        // in Secure Input contexts for the same security reasons.
    }
    
    private func simulatePasteWithKeyCode(_ keyCode: CGKeyCode) {
        let source = CGEventSource(stateID: .hidSystemState)
        
        let cmdVDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        cmdVDown?.flags = .maskCommand
        
        let cmdVUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        cmdVUp?.flags = .maskCommand
        
        cmdVDown?.post(tap: .cgSessionEventTap)
        cmdVUp?.post(tap: .cgSessionEventTap)
    }
    
    /// AppleScript fallback for paste - slower but layout-agnostic.
    /// Note: This also fails in Secure Input contexts, so it's not a true fallback
    /// for CGEvent failures, but it can help in edge cases where Carbon APIs fail.
    @MainActor
    private func simulatePasteViaAppleScript() -> Bool {
        let script = """
        tell application "System Events"
            keystroke "v" using {command down}
        end tell
        """
        
        guard let appleScript = NSAppleScript(source: script) else {
            #if DEBUG
            print("⚠️ Failed to create AppleScript for paste")
            #endif
            return false
        }
        
        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
        
        if let error = error {
            #if DEBUG
            print("⚠️ AppleScript paste failed: \(error)")
            #endif
            return false
        }
        
        #if DEBUG
        print("✅ AppleScript paste succeeded")
        #endif
        return true
    }
}
