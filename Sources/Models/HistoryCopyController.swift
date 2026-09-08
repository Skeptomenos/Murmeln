import AppKit
import Combine

/// Resolve the current immutable entry at click time. Deleted IDs cannot copy
/// stale view payloads. Every app-owned History copy shares paste ownership.
@MainActor
final class HistoryCopyController: ObservableObject {
    enum Payload { case finalResult, original, variant(String), fullAudit }
    @Published private(set) var message: String?
    private let store: HistoryStore
    private let paste: any PasteServicing
    private let announce: (String) -> Void

    init(store: HistoryStore, paste: any PasteServicing = PasteService.shared,
         announce: @escaping (String) -> Void = { message in
             NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                 userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
         }) {
        self.store = store
        self.paste = paste
        self.announce = announce
    }

    func copy(id: UUID, payload: Payload) {
        guard let entry = store.entry(id: id) else {
            message = "This entry was deleted."
            return
        }
        let text: String
        switch payload {
        case .finalResult: text = entry.refined
        case .original: text = entry.original
        case .variant(let name):
            guard let variant = entry.variants?[name] ?? (name == entry.safePresetName ? entry.refined : nil) else { return }
            text = variant
        case .fullAudit: text = Self.audit(entry)
        }
        copySelection(id: id, text: text)
    }

    func copySelection(id: UUID, text: String) {
        guard store.entry(id: id) != nil else { message = "This entry was deleted."; return }
        let feedback = paste.copyResult(text: text).message
        message = feedback
        announce(feedback)
    }

    static func audit(_ entry: HistoryEntry) -> String {
        var markdown = AppIdentity.auditTrailTitle + "\n"
        markdown += "**Date**: \(entry.formattedDate)\n"
        markdown += "**Selected Characteristic**: \(entry.safePresetName)\n\n"

        if entry.hasDistinctOriginalBaseline {
            markdown += "## 1. Raw Transcription (Baseline)\n"
            markdown += "> \(entry.original)\n\n"
            markdown += "## 2. \(entry.hasParallelAuditTrail ? "Refinement Variants" : "Final Result")\n\n"
        } else {
            markdown += "## 1. Final Result\n\n"
        }

        let variants = entry.variants ?? [entry.safePresetName: entry.refined]
        for name in variants.keys.sorted() {
            let text = variants[name] ?? ""
            let provenance = entry.promptProvenance(for: name)

            markdown += "### Variant: \(name)\(name == entry.safePresetName ? " (SELECTED)" : "")\n"
            if let effectivePrompt = provenance.effectivePrompt {
                markdown += "**Effective System Prompt**:\n```\n\(effectivePrompt)\n```\n\n"
            }
            if provenance.showsBasePromptSeparately, let basePrompt = provenance.basePrompt {
                markdown += "**Base System Prompt**:\n```\n\(basePrompt)\n```\n\n"
            }
            markdown += "**Result**:\n\(text)\n\n"
            markdown += "---\n\n"
        }

        return markdown
    }
}
