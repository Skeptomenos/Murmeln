import AppKit
import SwiftUI

/// Native selection and its context menu must use the same checked Copy path
/// as History buttons. NSTextView's default copy bypasses paste ownership.
struct HistorySelectableText: NSViewRepresentable {
    let text: String
    let copySelection: @MainActor (String) -> Void

    func makeNSView(context: Context) -> HistorySelectionTextView {
        let view = HistorySelectionTextView()
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = false
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.font = .preferredFont(forTextStyle: .body)
        view.textColor = .labelColor
        return view
    }

    func updateNSView(_ view: HistorySelectionTextView, context: Context) {
        if view.string != text { view.string = text }
        view.copySelection = copySelection
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: HistorySelectionTextView, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        // SwiftUI probes multiple widths. Measure separately so a discarded
        // proposal cannot leave the displayed text in a narrow container.
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        let layout = NSLayoutManager()
        let storage = NSTextStorage(attributedString: nsView.attributedString())
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        layout.ensureLayout(for: container)
        return CGSize(width: width, height: max(22, ceil(layout.usedRect(for: container).height)))
    }
}

@MainActor
final class HistorySelectionTextView: NSTextView {
    var copySelection: ((String) -> Void)?
    override func copy(_ sender: Any?) {
        let range = selectedRange()
        guard range.length > 0, NSMaxRange(range) <= (string as NSString).length else { return }
        copySelection?((string as NSString).substring(with: range))
    }
}
