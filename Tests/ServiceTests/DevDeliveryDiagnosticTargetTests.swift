import AppKit
import ApplicationServices
import Testing
@testable import mrml

@Suite("Dev Delivery Probe Target Tests")
@MainActor
struct DevDeliveryDiagnosticTargetTests {
    private func validSnapshot() -> DevDeliveryDiagnosticTarget.Snapshot {
        .init(
            processID: 42,
            frontmostProcessID: 42,
            bundleIdentifier: "com.apple.TextEdit",
            documentURL: DevDeliveryDiagnosticTarget.documentURL,
            role: "AXTextArea",
            subrole: nil,
            subroleReadIsValid: true,
            enabledState: .value(true),
            isEditable: true,
            matchesCapturedFocus: true
        )
    }

    @Test("The exact plain TextEdit receiver accepts only an empty caret at its end")
    func fixedReceiverAllowsInsertion() {
        let snapshot = validSnapshot()
        #expect(snapshot.allowsContentRead)
        #expect(snapshot.allowsInsertion(
            value: DevDeliveryDiagnosticTarget.initialText,
            selectedRange: NSRange(location: DevDeliveryDiagnosticTarget.initialText.utf16.count, length: 0)
        ))
    }

    @Test("Normal TextEdit unknown and absent subroles are accepted only within the fixed receiver")
    func ordinaryTextAreaSubroles() {
        var snapshot = validSnapshot()
        snapshot.subrole = "AXUnknown"
        #expect(snapshot.allowsContentRead)
        snapshot.subrole = "AXSecureTextField"
        #expect(!snapshot.allowsContentRead)
        snapshot.subrole = "AXUnexpectedTextArea"
        #expect(!snapshot.allowsContentRead)
        snapshot.subrole = nil
        snapshot.subroleReadIsValid = false
        #expect(!snapshot.allowsContentRead)
    }

    @Test("Wrong app, process, focus or document cannot authorize a content read")
    func rejectsOtherTargetsBeforeContentRead() {
        var snapshot = validSnapshot()
        snapshot.bundleIdentifier = "com.example.other"
        #expect(!snapshot.allowsContentRead)
        snapshot = validSnapshot()
        snapshot.frontmostProcessID = 43
        #expect(!snapshot.allowsContentRead)
        snapshot.frontmostProcessID = nil
        #expect(!snapshot.allowsContentRead)
        snapshot = validSnapshot()
        snapshot.matchesCapturedFocus = false
        #expect(!snapshot.allowsContentRead)
        snapshot = validSnapshot()
        snapshot.processID = 0
        #expect(!snapshot.allowsContentRead)
        snapshot = validSnapshot()
        snapshot.documentURL = URL(fileURLWithPath: "/tmp/unrelated-document.txt")
        #expect(!snapshot.allowsContentRead)
        snapshot.documentURL = nil
        #expect(!snapshot.allowsContentRead)
        snapshot.documentURL = URL(string: "https://example.invalid/murmeln-dev-delivery-probe.txt")
        #expect(!snapshot.allowsContentRead)
    }

    @Test("The receiver URL permits the macOS tmp alias but rejects remote hosts and URL suffixes")
    func validatesCanonicalLocalDocument() {
        var snapshot = validSnapshot()
        snapshot.documentURL = URL(fileURLWithPath: "/private/tmp/murmeln-dev-delivery-probe.txt")
        #expect(snapshot.allowsContentRead)
        snapshot.documentURL = URL(string: "file://other-host/tmp/murmeln-dev-delivery-probe.txt")
        #expect(!snapshot.allowsContentRead)
        snapshot.documentURL = URL(string: "file:///tmp/murmeln-dev-delivery-probe.txt?other")
        #expect(!snapshot.allowsContentRead)
        snapshot.documentURL = URL(string: "file:///tmp/murmeln-dev-delivery-probe.txt#other")
        #expect(!snapshot.allowsContentRead)
    }

    @Test("Unknown roles and unavailable, disabled or read-only attributes reject the receiver")
    func rejectsUnsafeOrUnavailableEditorAttributes() {
        var snapshot = validSnapshot()
        snapshot.role = "AXTextField"
        #expect(!snapshot.allowsContentRead)
        snapshot.role = nil
        #expect(!snapshot.allowsContentRead)
        snapshot = validSnapshot()
        snapshot.enabledState = .value(false)
        #expect(!snapshot.allowsContentRead)
        snapshot.enabledState = .unavailable
        #expect(!snapshot.allowsContentRead)
        snapshot = validSnapshot()
        snapshot.isEditable = false
        #expect(!snapshot.allowsContentRead)
        snapshot.isEditable = nil
        #expect(!snapshot.allowsContentRead)
    }

    @Test("Existing receiver text, selection or unavailable caret prevents insertion")
    func rejectsContentAndCaretChanges() {
        let snapshot = validSnapshot()
        let end = DevDeliveryDiagnosticTarget.initialText.utf16.count
        #expect(!snapshot.allowsInsertion(value: "other text", selectedRange: NSRange(location: end, length: 0)))
        #expect(!snapshot.allowsInsertion(value: nil, selectedRange: NSRange(location: end, length: 0)))
        #expect(!snapshot.allowsInsertion(value: DevDeliveryDiagnosticTarget.initialText, selectedRange: nil))
        #expect(!snapshot.allowsInsertion(value: DevDeliveryDiagnosticTarget.initialText, selectedRange: NSRange(location: 0, length: 0)))
        #expect(!snapshot.allowsInsertion(value: DevDeliveryDiagnosticTarget.initialText, selectedRange: NSRange(location: end, length: 1)))
        #expect(!snapshot.allowsInsertion(value: DevDeliveryDiagnosticTarget.initialText, selectedRange: NSRange(location: NSNotFound, length: 0)))
    }

    @Test("Readback validates identity without requiring the original text or caret")
    func readbackDoesNotTreatDeliveredTextAsAnInsertionTarget() {
        let snapshot = validSnapshot()
        #expect(snapshot.allowsContentRead)
        #expect(!snapshot.allowsInsertion(
            value: DevDeliveryDiagnosticTarget.initialText + "Murmeln paste diagnostic",
            selectedRange: NSRange(location: 0, length: 0)
        ))
    }

    @Test("Held shortcut modifiers prevent insertion but do not authorize a different readback target")
    func heldModifiersBlockInsertion() {
        for flag: CGEventFlags in [.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn] {
            var snapshot = validSnapshot()
            snapshot.modifierFlags = flag
            #expect(snapshot.allowsContentRead)
            #expect(!snapshot.allowsInsertion(
                value: DevDeliveryDiagnosticTarget.initialText,
                selectedRange: NSRange(location: DevDeliveryDiagnosticTarget.initialText.utf16.count, length: 0)
            ))
        }
        var snapshot = validSnapshot()
        snapshot.modifierFlags = .maskAlphaShift
        #expect(snapshot.allowsInsertion(
            value: DevDeliveryDiagnosticTarget.initialText,
            selectedRange: NSRange(location: DevDeliveryDiagnosticTarget.initialText.utf16.count, length: 0)
        ))
    }

    @Test("TextEdit's unsupported enabled attribute is accepted only for the verified editable receiver")
    func unsupportedEnabledStillRequiresExactEditableReceiver() {
        var snapshot = validSnapshot()
        snapshot.enabledState = .unsupported
        #expect(snapshot.allowsContentRead)
        #expect(snapshot.allowsInsertion(
            value: DevDeliveryDiagnosticTarget.initialText,
            selectedRange: NSRange(location: DevDeliveryDiagnosticTarget.initialText.utf16.count, length: 0)
        ))

        snapshot.isEditable = nil
        #expect(!snapshot.allowsContentRead)
        snapshot.isEditable = false
        #expect(!snapshot.allowsContentRead)
        snapshot.isEditable = true
        snapshot.role = "AXTextField"
        #expect(!snapshot.allowsContentRead)
        snapshot.role = "AXTextArea"
        snapshot.bundleIdentifier = "com.example.other"
        #expect(!snapshot.allowsContentRead)
        snapshot.bundleIdentifier = "com.apple.TextEdit"
        snapshot.documentURL = URL(fileURLWithPath: "/tmp/unrelated-document.txt")
        #expect(!snapshot.allowsContentRead)
    }

    @Test("Enabled attribute classification preserves explicit false and rejects errors or malformed values")
    func distinguishesUnsupportedEnabledFromFailures() {
        #expect(DevDeliveryDiagnosticTarget.classifyEnabledAttribute(result: .success, value: kCFBooleanTrue) == .value(true))
        #expect(DevDeliveryDiagnosticTarget.classifyEnabledAttribute(result: .success, value: kCFBooleanFalse) == .value(false))
        #expect(DevDeliveryDiagnosticTarget.classifyEnabledAttribute(result: .attributeUnsupported, value: nil) == .unsupported)
        #expect(DevDeliveryDiagnosticTarget.classifyEnabledAttribute(result: .attributeUnsupported, value: kCFBooleanFalse) == .unavailable)
        #expect(DevDeliveryDiagnosticTarget.classifyEnabledAttribute(result: .attributeUnsupported, value: "true" as CFString) == .unavailable)
        #expect(DevDeliveryDiagnosticTarget.classifyEnabledAttribute(result: .cannotComplete, value: nil) == .unavailable)
        #expect(DevDeliveryDiagnosticTarget.classifyEnabledAttribute(result: .noValue, value: nil) == .unavailable)
        #expect(DevDeliveryDiagnosticTarget.classifyEnabledAttribute(result: .success, value: nil) == .unavailable)
        #expect(DevDeliveryDiagnosticTarget.classifyEnabledAttribute(result: .success, value: "true" as CFString) == .unavailable)
        #expect(DevDeliveryDiagnosticTarget.classifyEnabledAttribute(result: .success, value: NSNumber(value: 2)) == .unavailable)
    }

    @Test("Absent diagnostic subrole metadata rejects contradictory returned values")
    func absentSubroleRejectsMalformedValues() {
        for result: AXError in [.attributeUnsupported, .noValue] {
            #expect(DevDeliveryDiagnosticTarget.isValidSubroleRead(result: result, value: nil))
            for value: CFTypeRef in [kCFBooleanTrue, NSNumber(value: 2), "AXUnknown" as CFString] {
                #expect(!DevDeliveryDiagnosticTarget.isValidSubroleRead(result: result, value: value))
            }
        }
        #expect(DevDeliveryDiagnosticTarget.isValidSubroleRead(result: .success, value: "AXUnknown" as CFString))
        #expect(!DevDeliveryDiagnosticTarget.isValidSubroleRead(result: .success, value: nil))
        #expect(!DevDeliveryDiagnosticTarget.isValidSubroleRead(result: .success, value: kCFBooleanTrue))
        #expect(!DevDeliveryDiagnosticTarget.isValidSubroleRead(result: .cannotComplete, value: nil))
        #expect(!DevDeliveryDiagnosticTarget.isValidSubroleRead(result: .cannotComplete, value: "AXUnknown" as CFString))
    }
}
