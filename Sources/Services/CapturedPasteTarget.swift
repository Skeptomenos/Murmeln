import AppKit
import ApplicationServices

@MainActor
protocol PasteTargetChecking: AnyObject {
    func isStillValid() -> Bool
    func invalidationReason() -> PasteTargetInvalidationReason?
    var diagnosticPolicy: PasteTargetPolicy { get }
}

extension PasteTargetChecking {
    func invalidationReason() -> PasteTargetInvalidationReason? {
        isStillValid() ? nil : .unknownInvalid
    }

    var diagnosticPolicy: PasteTargetPolicy { .capturedUnknown }
}

/// Captures only editor identity and an empty caret. It never reads field contents.
@MainActor
final class CapturedPasteTarget: PasteTargetChecking {
    enum EnabledState: Equatable {
        case value(Bool)
        case unsupported
        case unavailable
    }

    struct Snapshot {
        var processID: pid_t
        var frontmostProcessID: pid_t?
        var bundleIdentifier: String?
        var role: String?
        var subrole: String?
        var subroleReadIsValid: Bool
        var enabledState: EnabledState
        var isEditable: Bool?
        var matchesCapturedFocus: Bool
        var selectedRange: NSRange?
        var modifierFlags: CGEventFlags = []
        var notionStructure: NotionStructure?

        var allowsCapture: Bool {
            let common = processID > 0 && frontmostProcessID == processID && matchesCapturedFocus
                && role == kAXTextAreaRole as String && subroleReadIsValid
                && isEditable == true
                && selectedRange.map { $0.location >= 0 && $0.location != NSNotFound && $0.length == 0 } == true
            guard common else { return false }
            switch bundleIdentifier {
            case "com.apple.TextEdit":
                return (subrole == nil || subrole == kAXUnknownSubrole as String)
                    && (enabledState == .value(true) || enabledState == .unsupported)
            case "notion.id":
                return subrole == nil && enabledState == .value(true) && notionStructure != nil
            default:
                return false
            }
        }

        func allowsDelivery(capturedCaret: NSRange, capturedNotionStructure: NotionStructure? = nil) -> Bool {
            guard allowsCapture, selectedRange == capturedCaret, Self.modifiersPermitDelivery(modifierFlags) else { return false }
            return bundleIdentifier != "notion.id"
                || notionStructure?.matches(capturedNotionStructure) == true
        }

        func deliveryInvalidationReason(capturedCaret: NSRange,
                                        capturedNotionStructure: NotionStructure? = nil) -> PasteTargetInvalidationReason? {
            guard allowsCapture else {
                if processID <= 0 || frontmostProcessID != processID || !matchesCapturedFocus { return .focusChanged }
                if role == nil || !subroleReadIsValid || enabledState == .unavailable
                    || isEditable == nil || selectedRange == nil { return .accessibilityUnavailable }
                if let selectedRange, selectedRange.location < 0 || selectedRange.location == NSNotFound
                    || selectedRange.length != 0 { return .caretChanged }
                return .structureUnverifiable
            }
            guard selectedRange == capturedCaret else { return .caretChanged }
            guard Self.modifiersPermitDelivery(modifierFlags) else { return .modifiersHeld }
            guard bundleIdentifier != "notion.id" || notionStructure?.matches(capturedNotionStructure) == true else {
                return .structureChanged
            }
            return nil
        }

        static func modifiersPermitDelivery(_ flags: CGEventFlags) -> Bool {
            flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn]).isEmpty
        }
    }

    enum NotionLayout: Equatable {
        case wrapped
        case direct
    }

    struct NotionStructure {
        let ancestors: [AXUIElement]
        let insertionLine: Int
        let layout: NotionLayout

        func matches(_ captured: NotionStructure?) -> Bool {
            guard let captured, layout == captured.layout, insertionLine == captured.insertionLine,
                  ancestors.count == captured.ancestors.count else { return false }
            return zip(ancestors, captured.ancestors).allSatisfy { CFEqual($0, $1) }
        }
    }

    struct AttributeRead {
        let result: AXError
        let value: CFTypeRef?
    }

    struct NotionAXReader {
        var attribute: (AXUIElement, String) -> AttributeRead
        var isSettable: (AXUIElement, String) -> Bool?
        var processID: (AXUIElement) -> pid_t?
        var setTimeout: (AXUIElement, Float) -> Bool
        var uptime: () -> TimeInterval

        static var live: Self {
            .init(attribute: { element, name in
                var value: CFTypeRef?
                let result = AXUIElementCopyAttributeValue(element, name as CFString, &value)
                return AttributeRead(result: result, value: value)
            }, isSettable: { element, name in
                var value: DarwinBoolean = false
                guard AXUIElementIsAttributeSettable(element, name as CFString, &value) == .success else { return nil }
                return value.boolValue
            }, processID: { element in
                var processID: pid_t = 0
                return AXUIElementGetPid(element, &processID) == .success ? processID : nil
            }, setTimeout: { element, timeout in
                AXUIElementSetMessagingTimeout(element, timeout) == .success
            }, uptime: { ProcessInfo.processInfo.systemUptime })
        }
    }

    /// One walk owns its diagnostics. No extra AX calls or content reads are needed.
    @MainActor
    private final class BoundedNotionReader {
        let reader: NotionAXReader
        let deadline: TimeInterval
        private(set) var failure: PasteTargetInvalidationReason?

        init(reader: NotionAXReader, deadline: TimeInterval) {
            self.reader = reader
            self.deadline = deadline
        }

        private func note(_ reason: PasteTargetInvalidationReason) {
            if failure == nil { failure = reason }
        }

        var hasTime: Bool {
            let available = reader.uptime() < deadline
            if !available { note(.inspectionTimedOut) }
            return available
        }

        func read(_ element: AXUIElement, _ name: String, allowsUnsupported: Bool = false) -> AttributeRead {
            guard prepare(element) else { return AttributeRead(result: .cannotComplete, value: nil) }
            let sample = reader.attribute(element, name)
            let absentSubrole = name == kAXSubroleAttribute && Self.absent(sample)
            let allowedUnsupported = allowsUnsupported && sample.result == .attributeUnsupported && sample.value == nil
            if !absentSubrole && !allowedUnsupported {
                if sample.result == .noValue || sample.result == .attributeUnsupported || (sample.result == .success && sample.value == nil) {
                    note(.metadataUnavailable)
                } else if sample.result != .success {
                    // AX cannotComplete is not proof of a timeout. Only our elapsed budget is.
                    note(.accessibilityUnavailable)
                }
            }
            return sample
        }

        private static func absent(_ sample: AttributeRead) -> Bool {
            (sample.result == .noValue || sample.result == .attributeUnsupported) && sample.value == nil
        }

        func isSettable(_ element: AXUIElement, _ name: String) -> Bool? {
            guard prepare(element) else { return nil }
            let value = reader.isSettable(element, name)
            if value == nil { note(.metadataUnavailable) }
            return value
        }

        func ownedBy(_ element: AXUIElement, _ processID: pid_t) -> Bool {
            guard hasTime else { return false }
            let owner = reader.processID(element)
            if owner == nil { note(.metadataUnavailable) }
            return owner == processID
        }

        private func prepare(_ element: AXUIElement) -> Bool {
            let remaining = deadline - reader.uptime()
            guard remaining > 0 else { note(.inspectionTimedOut); return false }
            guard reader.setTimeout(element, Float(min(0.2, remaining))) else {
                note(.accessibilityUnavailable)
                return false
            }
            return true
        }
    }

    private enum StructuralClasses: Equatable {
        case values(Set<String>)
        case unsupported
        case invalid
    }

    private struct NotionEditorState: Equatable {
        let range: NSRange
        let insertionLine: Int
    }

    static func readNotionSnapshot(editor: AXUIElement, window: AXUIElement, processID: pid_t,
                                  frontmostProcessID: pid_t?, modifierFlags: CGEventFlags,
                                  reader: NotionAXReader = .live,
                                  onFailure: ((PasteTargetInvalidationReason) -> Void)? = nil) -> Snapshot? {
        let bounded = BoundedNotionReader(reader: reader, deadline: reader.uptime() + 0.25)
        guard processID > 0 else { onFailure?(.unsupportedStructure); return nil }
        guard frontmostProcessID == processID else { onFailure?(.focusChanged); return nil }
        guard bounded.ownedBy(editor, processID), bounded.ownedBy(window, processID),
              let initialEditor = readNotionEditor(editor, reader: bounded),
              let ancestry = readNotionAncestors(editor: editor, window: window, processID: processID, reader: bounded),
              bounded.ownedBy(editor, processID),
              let finalEditor = readNotionEditor(editor, reader: bounded) else {
            onFailure?(bounded.failure ?? .unsupportedStructure)
            return nil
        }
        guard finalEditor == initialEditor else {
            onFailure?(finalEditor.range != initialEditor.range ? .caretChanged : .structureChanged)
            return nil
        }
        guard bounded.hasTime else { onFailure?(.inspectionTimedOut); return nil }
        return Snapshot(processID: processID, frontmostProcessID: frontmostProcessID, bundleIdentifier: "notion.id",
                        role: kAXTextAreaRole as String, subrole: nil, subroleReadIsValid: true, enabledState: .value(true),
                        isEditable: true, matchesCapturedFocus: true, selectedRange: finalEditor.range, modifierFlags: modifierFlags,
                        notionStructure: NotionStructure(ancestors: ancestry.elements, insertionLine: finalEditor.insertionLine, layout: ancestry.layout))
    }

    private static func readNotionEditor(_ editor: AXUIElement, reader: BoundedNotionReader) -> NotionEditorState? {
        guard let role = readString(reader.read(editor, kAXRoleAttribute)),
              role == kAXTextAreaRole as String else { return nil }
        let subrole = reader.read(editor, kAXSubroleAttribute)
        let enabled = reader.read(editor, kAXEnabledAttribute)
        guard isValidSubroleRead(result: subrole.result, value: subrole.value), subrole.value == nil,
              enabled.result == .success, let enabledValue = enabled.value,
              CFGetTypeID(enabledValue) == CFBooleanGetTypeID(), enabledValue as? Bool == true,
              reader.isSettable(editor, kAXValueAttribute) == true,
              reader.isSettable(editor, kAXSelectedTextRangeAttribute) == true,
              readClasses(reader.read(editor, "AXDOMClassList")) == .values([]),
              let range = readRange(reader.read(editor, kAXSelectedTextRangeAttribute)), range.length == 0,
              let insertionLine = readInsertionLine(reader.read(editor, kAXInsertionPointLineNumberAttribute)) else { return nil }
        return NotionEditorState(range: range, insertionLine: insertionLine)
    }

    private enum NotionAncestorPhase {
        case paragraph
        case contentOrRoot
        case editorRoot
        case scroller
        case frame
        case webAncestors
        case nativeStart
        case nativeGroups
    }

    private static func readNotionAncestors(editor: AXUIElement, window: AXUIElement, processID: pid_t,
                                            reader: BoundedNotionReader) -> (elements: [AXUIElement], layout: NotionLayout)? {
        var ancestors: [AXUIElement] = []
        var current = editor
        var phase = NotionAncestorPhase.paragraph
        var layout: NotionLayout?
        for _ in 0..<32 {
            let parentRead = reader.read(current, kAXParentAttribute)
            guard parentRead.result == .success, let value = parentRead.value,
                  CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            let parent = unsafeDowncast(value, to: AXUIElement.self)
            guard !CFEqual(parent, editor), !ancestors.contains(where: { CFEqual($0, parent) }),
                  reader.ownedBy(parent, processID),
                  let role = readString(reader.read(parent, kAXRoleAttribute)) else { return nil }
            let subroleRead = reader.read(parent, kAXSubroleAttribute)
            guard isValidSubroleRead(result: subroleRead.result, value: subroleRead.value) else { return nil }
            let subrole = subroleRead.value as? String
            let classes = readClasses(reader.read(parent, "AXDOMClassList",
                allowsUnsupported: phase == .nativeStart || (phase == .nativeGroups && CFEqual(parent, window))))
            switch phase {
            case .paragraph:
                guard role == "AXGroup", subrole == nil,
                      classes == .values(["notion-selectable", "notion-text-block"]) else { return nil }
                phase = .contentOrRoot
            case .contentOrRoot:
                if role == "AXGroup", subrole == nil, classes == .values(["notion-page-content"]) {
                    layout = .wrapped
                    phase = .editorRoot
                } else {
                    guard role == "AXTextArea", subrole == "AXApplicationGroup", classes == .values([]) else { return nil }
                    layout = .direct
                    phase = .scroller
                }
            case .editorRoot:
                guard role == "AXTextArea", subrole == "AXApplicationGroup", classes == .values([]) else { return nil }
                phase = .scroller
            case .scroller:
                guard role == "AXGroup", subrole == nil, classes == .values(["notion-scroller"]) else { return nil }
                phase = .frame
            case .frame:
                guard role == "AXGroup", subrole == "AXLandmarkMain", classes == .values(["notion-frame"]) else { return nil }
                phase = .webAncestors
            case .webAncestors:
                guard subrole == nil, case .values(let tokens) = classes else { return nil }
                if role == "AXWebArea" {
                    guard tokens.isEmpty else { return nil }
                    phase = .nativeStart
                } else {
                    guard role == "AXGroup", tokens.isSubset(of: ["notion-cursor-listener", "notion-body", "notion-dark-theme"]) else { return nil }
                }
            case .nativeStart:
                guard role == "AXScrollArea", subrole == nil,
                      classes == .unsupported || classes == .values([]) else { return nil }
                phase = .nativeGroups
            case .nativeGroups:
                if CFEqual(parent, window) {
                    guard let layout, role == "AXWindow", subrole == "AXStandardWindow",
                          classes == .unsupported || classes == .values([]) else { return nil }
                    ancestors.append(parent)
                    return reader.hasTime ? (ancestors, layout) : nil
                }
                guard role == "AXGroup", subrole == nil, classes == .values([]) else { return nil }
            }
            ancestors.append(parent)
            current = parent
        }
        return nil
    }

    private static func readString(_ sample: AttributeRead) -> String? {
        guard sample.result == .success, let value = sample.value, CFGetTypeID(value) == CFStringGetTypeID() else { return nil }
        return value as? String
    }

    private static func readClasses(_ sample: AttributeRead) -> StructuralClasses {
        if sample.result == .attributeUnsupported, sample.value == nil { return .unsupported }
        guard sample.result == .success, let value = sample.value, CFGetTypeID(value) == CFArrayGetTypeID(),
              let items = value as? [Any], items.count <= 128 else { return .invalid }
        var classes = Set<String>()
        for item in items {
            guard let string = item as? String, string.utf8.count <= 128 else { return .invalid }
            if string.range(of: "^notion-[a-z-]{1,60}$", options: .regularExpression) == string.startIndex..<string.endIndex {
                classes.insert(string)
            }
        }
        return .values(classes)
    }

    private static func readInsertionLine(_ sample: AttributeRead) -> Int? {
        guard sample.result == .success, let value = sample.value, CFGetTypeID(value) == CFNumberGetTypeID() else { return nil }
        let number = unsafeDowncast(value, to: CFNumber.self)
        guard !CFNumberIsFloatType(number) else { return nil }
        var line: Int64 = 0
        guard CFNumberGetValue(number, .sInt64Type, &line), line >= 0, line < Int64(NSNotFound) else { return nil }
        return Int(line)
    }

    private static func readRange(_ sample: AttributeRead) -> NSRange? {
        guard sample.result == .success, let value = sample.value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range), range.location >= 0, range.location != NSNotFound,
              range.length >= 0, range.length != NSNotFound else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    private let processID: pid_t
    private let bundleIdentifier: String
    private let application: AXUIElement
    private let window: AXUIElement
    private let editor: AXUIElement
    private var capturedCaret: NSRange?
    private var capturedNotionStructure: NotionStructure?

    var diagnosticPolicy: PasteTargetPolicy {
        bundleIdentifier == "notion.id" ? .capturedNotion : .capturedTextEdit
    }

    private enum SnapshotRead {
        case snapshot(Snapshot)
        case invalid(PasteTargetInvalidationReason)
    }

    static func capture() -> (any PasteTargetChecking)? {
        let frontmost = NSWorkspace.shared.frontmostApplication
        var captureFailure = PasteTargetInvalidationReason.initialCaptureUnverifiable
        let capturedTarget = CapturedPasteTarget(frontmost: frontmost, onFailure: { captureFailure = $0 })
        return select(bundleIdentifier: frontmost?.bundleIdentifier, capturedTarget: capturedTarget, captureFailure: captureFailure)
    }

    static func select(bundleIdentifier: String?, capturedTarget: (any PasteTargetChecking)?,
                       captureFailure: PasteTargetInvalidationReason = .initialCaptureUnverifiable) -> (any PasteTargetChecking)? {
        if let capturedTarget { return capturedTarget }
        return bundleIdentifier == "notion.id" ? UnverifiedPasteTarget(reason: captureFailure) : nil
    }

    init?(frontmost: NSRunningApplication? = NSWorkspace.shared.frontmostApplication,
          onFailure: ((PasteTargetInvalidationReason) -> Void)? = nil) {
        guard AXIsProcessTrusted() else { onFailure?(.accessibilityUnavailable); return nil }
        guard let frontmost,
              let bundleIdentifier = frontmost.bundleIdentifier,
              ["com.apple.TextEdit", "notion.id"].contains(bundleIdentifier), !frontmost.isTerminated else {
            onFailure?(.focusChanged)
            return nil
        }
        let application = AXUIElementCreateApplication(frontmost.processIdentifier)
        guard Self.boundTimeout(application),
              let window = Self.element(application, kAXFocusedWindowAttribute), Self.boundTimeout(window),
              let editor = Self.element(application, kAXFocusedUIElementAttribute), Self.boundTimeout(editor) else {
            onFailure?(.accessibilityUnavailable)
            return nil
        }
        self.processID = frontmost.processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.application = application
        self.window = window
        self.editor = editor
        let snapshot: Snapshot
        switch currentSnapshot() {
        case .snapshot(let value): snapshot = value
        case .invalid(let reason): onFailure?(reason); return nil
        }
        guard snapshot.allowsCapture else { onFailure?(.structureUnverifiable); return nil }
        if let reason = focusInvalidationReason() { onFailure?(reason); return nil }
        // Fn or Option can still be held at this recording-start boundary.
        capturedCaret = snapshot.selectedRange
        capturedNotionStructure = snapshot.notionStructure
    }

    func isStillValid() -> Bool {
        invalidationReason() == nil
    }

    func invalidationReason() -> PasteTargetInvalidationReason? {
        guard let capturedCaret else { return .initialCaptureUnverifiable }
        let snapshot: Snapshot
        switch currentSnapshot() {
        case .snapshot(let value): snapshot = value
        case .invalid(let reason): return reason
        }
        if let reason = snapshot.deliveryInvalidationReason(capturedCaret: capturedCaret,
            capturedNotionStructure: capturedNotionStructure) { return reason }
        if let reason = focusInvalidationReason() { return reason }
        return Snapshot.modifiersPermitDelivery(CGEventSource.flagsState(.combinedSessionState)) ? nil : .modifiersHeld
    }

    private func currentSnapshot() -> SnapshotRead {
        guard AXIsProcessTrusted() else { return .invalid(.accessibilityUnavailable) }
        if let reason = focusInvalidationReason() { return .invalid(reason) }
        guard Self.ownedBy(window, processID), Self.ownedBy(editor, processID),
              Self.string(window, kAXRoleAttribute) == kAXWindowRole as String,
              let editorWindow = Self.element(editor, kAXWindowAttribute), CFEqual(editorWindow, window),
              let role = Self.string(editor, kAXRoleAttribute), role == kAXTextAreaRole as String else {
            return .invalid(.structureUnverifiable)
        }

        if bundleIdentifier == "notion.id" {
            var failure = PasteTargetInvalidationReason.unsupportedStructure
            guard let snapshot = Self.readNotionSnapshot(editor: editor, window: window, processID: processID,
                frontmostProcessID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                modifierFlags: CGEventSource.flagsState(.combinedSessionState), onFailure: { failure = $0 }) else {
                return .invalid(failure)
            }
            return .snapshot(snapshot)
        }

        var subroleValue: CFTypeRef?
        let subroleResult = AXUIElementCopyAttributeValue(editor, kAXSubroleAttribute as CFString, &subroleValue)
        let subrole = subroleValue as? String
        let validSubroleRead = Self.isValidSubroleRead(result: subroleResult, value: subroleValue)
        var editable: DarwinBoolean = false
        // This queries whether a value is editable, without fetching the value.
        let editableResult = AXUIElementIsAttributeSettable(editor, kAXValueAttribute as CFString, &editable)
        let frontmost = NSWorkspace.shared.frontmostApplication
        return .snapshot(Snapshot(
            processID: processID, frontmostProcessID: frontmost?.processIdentifier,
            bundleIdentifier: frontmost?.bundleIdentifier, role: role, subrole: subrole,
            subroleReadIsValid: validSubroleRead, enabledState: Self.enabledState(editor),
            isEditable: editableResult == .success ? editable.boolValue : nil,
            matchesCapturedFocus: true, selectedRange: Self.selectedRange(editor),
            modifierFlags: CGEventSource.flagsState(.combinedSessionState)))
    }

    private func focusInvalidationReason() -> PasteTargetInvalidationReason? {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return .accessibilityUnavailable }
        guard frontmost.processIdentifier == processID,
              frontmost.bundleIdentifier == bundleIdentifier, !frontmost.isTerminated else { return .focusChanged }
        guard let focusedWindow = Self.element(application, kAXFocusedWindowAttribute) else { return .accessibilityUnavailable }
        guard CFEqual(focusedWindow, window) else { return .focusChanged }
        guard let focusedEditor = Self.element(application, kAXFocusedUIElementAttribute) else { return .accessibilityUnavailable }
        return CFEqual(focusedEditor, editor) ? nil : .focusChanged
    }

    private static func boundTimeout(_ element: AXUIElement) -> Bool {
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
        // The ordinary TextEdit editor omits AXEnabled, but must still prove editability.
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
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func selectedRange(_ editor: AXUIElement) -> NSRange? {
        guard let value = attribute(editor, kAXSelectedTextRangeAttribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range), range.location >= 0, range.length >= 0 else { return nil }
        return NSRange(location: range.location, length: range.length)
    }
}
