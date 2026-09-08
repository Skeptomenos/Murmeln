import AppKit
import ApplicationServices

@MainActor
protocol DevDeliveryDiagnosticTargetChecking: AnyObject {
    func isStillValid() -> Bool
}

/// The diagnostic may inspect only its fixed, disposable TextEdit document.
@MainActor
final class DevDeliveryDiagnosticTarget: DevDeliveryDiagnosticTargetChecking {
    nonisolated static let documentURL = URL(fileURLWithPath: "/tmp/murmeln-dev-delivery-probe.txt")
    nonisolated static let initialText = "Murmeln Dev delivery receiver\n"

    enum EnabledState: Equatable {
        case value(Bool)
        case unsupported
        case unavailable
    }

    struct Snapshot {
        var processID: pid_t
        var frontmostProcessID: pid_t?
        var bundleIdentifier: String?
        var documentURL: URL?
        var role: String?
        var subrole: String?
        var subroleReadIsValid: Bool
        var enabledState: EnabledState
        var isEditable: Bool?
        var matchesCapturedFocus: Bool
        var modifierFlags: CGEventFlags = []

        var allowsContentRead: Bool {
            // TextEdit can omit AXEnabled; the exact identity and verified editability still apply.
            guard processID > 0,
                  frontmostProcessID == processID,
                  bundleIdentifier == "com.apple.TextEdit",
                  matchesCapturedFocus,
                  role == kAXTextAreaRole as String,
                  subroleReadIsValid,
                  subrole == nil || subrole == kAXUnknownSubrole as String,
                  enabledState == .value(true) || enabledState == .unsupported,
                  isEditable == true,
                  let documentURL,
                  documentURL.isFileURL,
                  documentURL.host == nil || documentURL.host == "" || documentURL.host == "localhost",
                  documentURL.query == nil,
                  documentURL.fragment == nil else { return false }

            return Self.canonicalPath(documentURL) == Self.canonicalPath(DevDeliveryDiagnosticTarget.documentURL)
        }

        private static func canonicalPath(_ url: URL) -> String {
            let standardized = url.standardizedFileURL
            // Resolve the existing parent first: the disposable file may not exist yet.
            let parent = standardized.deletingLastPathComponent().resolvingSymlinksInPath()
            return parent.appendingPathComponent(standardized.lastPathComponent)
                .resolvingSymlinksInPath().standardizedFileURL.path
        }

        func allowsInsertion(value: String?, selectedRange: NSRange?) -> Bool {
            allowsContentRead
                && Self.modifiersPermitInsertion(modifierFlags)
                && value == DevDeliveryDiagnosticTarget.initialText
                && selectedRange == NSRange(location: DevDeliveryDiagnosticTarget.initialText.utf16.count, length: 0)
        }

        static func modifiersPermitInsertion(_ flags: CGEventFlags) -> Bool {
            flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn]).isEmpty
        }
    }

    private let processID: pid_t
    private let application: AXUIElement
    private let window: AXUIElement
    private let editor: AXUIElement

    init?() {
        guard AXIsProcessTrusted(),
              let frontmost = NSWorkspace.shared.frontmostApplication,
              frontmost.bundleIdentifier == "com.apple.TextEdit",
              !frontmost.isTerminated else { return nil }

        let application = AXUIElementCreateApplication(frontmost.processIdentifier)
        guard Self.boundMessagingTimeout(application),
              let window = Self.element(application, kAXFocusedWindowAttribute),
              Self.boundMessagingTimeout(window),
              let editor = Self.element(application, kAXFocusedUIElementAttribute),
              Self.boundMessagingTimeout(editor) else { return nil }

        self.processID = frontmost.processIdentifier
        self.application = application
        self.window = window
        self.editor = editor
        guard isStillValid() else { return nil }
    }

    func isStillValid() -> Bool {
        guard let snapshot = currentSnapshot(), snapshot.allowsContentRead else { return false }
        // Reading AXValue is permitted only after the exact document and editor checks.
        let value = Self.string(editor, kAXValueAttribute)
        let range = Self.selectedRange(editor)
        return snapshot.allowsInsertion(value: value, selectedRange: range)
            && hasCapturedFocus()
            && Snapshot.modifiersPermitInsertion(CGEventSource.flagsState(.combinedSessionState))
    }

    func currentValueMatches(_ expected: String) -> Bool {
        guard let snapshot = currentSnapshot(), snapshot.allowsContentRead else { return false }
        return Self.string(editor, kAXValueAttribute) == expected && hasCapturedFocus()
    }

    private func currentSnapshot() -> Snapshot? {
        guard AXIsProcessTrusted(), hasCapturedFocus(),
              Self.ownedBy(window, processID), Self.ownedBy(editor, processID),
              Self.string(window, kAXRoleAttribute) == kAXWindowRole as String,
              let editorWindow = Self.element(editor, kAXWindowAttribute),
              CFEqual(editorWindow, window),
              let document = Self.string(window, kAXDocumentAttribute),
              let documentURL = URL(string: document) else { return nil }

        var subroleValue: CFTypeRef?
        let subroleResult = AXUIElementCopyAttributeValue(editor, kAXSubroleAttribute as CFString, &subroleValue)
        let subrole = subroleValue as? String
        let validSubroleRead = Self.isValidSubroleRead(result: subroleResult, value: subroleValue)
        var editable: DarwinBoolean = false
        let editableResult = AXUIElementIsAttributeSettable(editor, kAXValueAttribute as CFString, &editable)
        let frontmost = NSWorkspace.shared.frontmostApplication

        return Snapshot(
            processID: processID,
            frontmostProcessID: frontmost?.processIdentifier,
            bundleIdentifier: frontmost?.bundleIdentifier,
            documentURL: documentURL,
            role: Self.string(editor, kAXRoleAttribute),
            subrole: subrole,
            subroleReadIsValid: validSubroleRead,
            enabledState: Self.enabledState(editor),
            isEditable: editableResult == .success ? editable.boolValue : nil,
            matchesCapturedFocus: true,
            modifierFlags: CGEventSource.flagsState(.combinedSessionState)
        )
    }

    private func hasCapturedFocus() -> Bool {
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              frontmost.processIdentifier == processID,
              frontmost.bundleIdentifier == "com.apple.TextEdit",
              !frontmost.isTerminated,
              let focusedWindow = Self.element(application, kAXFocusedWindowAttribute),
              CFEqual(focusedWindow, window),
              let focusedEditor = Self.element(application, kAXFocusedUIElementAttribute),
              CFEqual(focusedEditor, editor) else { return false }
        return true
    }

    private static func boundMessagingTimeout(_ element: AXUIElement) -> Bool {
        AXUIElementSetMessagingTimeout(element, 0.2) == .success
    }

    private static func ownedBy(_ element: AXUIElement, _ processID: pid_t) -> Bool {
        var owner: pid_t = 0
        return AXUIElementGetPid(element, &owner) == .success && owner == processID
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func string(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name) as? String
    }

    private static func enabledState(_ element: AXUIElement) -> EnabledState {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &value)
        return classifyEnabledAttribute(result: result, value: value)
    }

    static func classifyEnabledAttribute(result: AXError, value: CFTypeRef?) -> EnabledState {
        if result == .attributeUnsupported { return value == nil ? .unsupported : .unavailable }
        guard result == .success, let value,
              CFGetTypeID(value) == CFBooleanGetTypeID(), let enabled = value as? Bool else { return .unavailable }
        return .value(enabled)
    }

    static func isValidSubroleRead(result: AXError, value: CFTypeRef?) -> Bool {
        (result == .success && value as? String != nil)
            || ((result == .attributeUnsupported || result == .noValue) && value == nil)
    }

    private static func element(_ parent: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(parent, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        // Core Foundation's dynamic type check above is required before this bridge.
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func selectedRange(_ editor: AXUIElement) -> NSRange? {
        guard let value = attribute(editor, kAXSelectedTextRangeAttribute),
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range), range.location >= 0, range.length >= 0 else { return nil }
        return NSRange(location: range.location, length: range.length)
    }
}
