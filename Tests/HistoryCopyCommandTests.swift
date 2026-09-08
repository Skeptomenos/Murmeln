import AppKit
import Testing
@testable import mrml

@MainActor
private final class SelectionCopySpy: NSTextView {
    private(set) var copiedSelections: [String] = []
    var refusesCopy = false
    private(set) var copyAttempts = 0

    override func copy(_ sender: Any?) {
        copyAttempts += 1
        guard !refusesCopy else { return }
        copiedSelections.append((string as NSString).substring(with: selectedRange()))
    }
}

@MainActor
private final class NativeSelectionCopySpy: NSView {
    var range = NSRange(location: 3, length: 12)
    private(set) var copyAttempts = 0

    override func accessibilitySelectedTextRange() -> NSRange { range }

    @objc func copy(_ sender: Any?) {
        copyAttempts += 1
    }
}

@Suite("History Copy command")
@MainActor
struct HistoryCopyCommandTests {
    @Test("Native selected text takes precedence over the whole result")
    func copiesSelection() {
        let view = SelectionCopySpy()
        view.string = "The blue lantern stays by the window."
        view.setSelectedRange(NSRange(location: 4, length: 12))
        var fallbackCount = 0

        HistoryCopyCommand.perform(firstResponder: view) { fallbackCount += 1 }

        #expect(view.copiedSelections == ["blue lantern"])
        #expect(fallbackCount == 0)
    }

    @Test("An empty selection copies the selected result")
    func emptySelection() {
        let view = SelectionCopySpy()
        view.string = "The blue lantern stays by the window."
        view.setSelectedRange(NSRange(location: 4, length: 0))
        var fallbackCount = 0

        HistoryCopyCommand.perform(firstResponder: view) { fallbackCount += 1 }

        #expect(view.copyAttempts == 0)
        #expect(fallbackCount == 1)
    }

    @Test("Missing and nontext responders use the selected result")
    func noTextResponder() {
        var fallbackCount = 0
        HistoryCopyCommand.perform(firstResponder: nil) { fallbackCount += 1 }
        HistoryCopyCommand.perform(firstResponder: NSResponder()) { fallbackCount += 1 }
        #expect(fallbackCount == 2)
    }

    @Test("A guarded refusal never falls back to another clipboard write")
    func guardedRefusal() {
        let view = SelectionCopySpy()
        view.string = "original transcript"
        view.setSelectedRange(NSRange(location: 0, length: 8))
        view.refusesCopy = true
        var fallbackCount = 0

        HistoryCopyCommand.perform(firstResponder: view) { fallbackCount += 1 }

        #expect(view.copyAttempts == 1)
        #expect(view.copiedSelections.isEmpty)
        #expect(fallbackCount == 0)
    }

    @Test("Native views expose selection without text-input protocol conformance")
    func nativeViewSelection() {
        let view = NativeSelectionCopySpy()
        var fallbackCount = 0

        HistoryCopyCommand.perform(firstResponder: view) { fallbackCount += 1 }

        #expect(view.copyAttempts == 1)
        #expect(fallbackCount == 0)
    }

    @Test("Empty and unavailable native ranges use the result", arguments: [
        NSRange(location: 31, length: 0),
        NSRange(location: NSNotFound, length: 0)
    ])
    func nativeViewWithoutSelection(range: NSRange) {
        let view = NativeSelectionCopySpy()
        view.range = range
        var fallbackCount = 0

        HistoryCopyCommand.perform(firstResponder: view) { fallbackCount += 1 }

        #expect(view.copyAttempts == 0)
        #expect(fallbackCount == 1)
    }
}
