import AppKit
import SwiftUI

@MainActor
enum HistoryCopyCommand {
    static func perform(firstResponder: NSResponder?, copySelectedResult: () -> Void) {
        // SwiftUI selectable Text exposes its range through NSView accessibility;
        // guarded adapters use NSTextView. Keep each responder's own Copy action.
        let selection = (firstResponder as? NSTextView)?.selectedRange()
            ?? (firstResponder as? NSView)?.accessibilitySelectedTextRange()
        if let selection, selection.location != NSNotFound, selection.length > 0 {
            _ = firstResponder?.tryToPerform(#selector(NSText.copy(_:)), with: nil)
            // A guarded refusal must never turn into an unguarded result copy.
            return
        }
        copySelectedResult()
    }
}

/// Presentation only. The caller owns persistence, clipboard writes and recovery.
struct HistoryBrowser<Notice: View, Detail: View>: View {
    let entries: [HistoryEntry]
    @Binding var selectedEntryID: UUID?
    let onCopy: (UUID) -> Void
    let onClear: () -> Void
    @ViewBuilder var notice: () -> Notice
    @ViewBuilder var detail: (HistoryEntry) -> Detail

    private var selectedEntry: HistoryEntry? {
        entries.first { $0.id == selectedEntryID }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(WindowPalette.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("History")
                        .font(.system(size: 20, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text("Your dictated text, ready to use again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(entries.count) \(entries.count == 1 ? "result" : "results")")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            notice()
            Divider()

            if entries.isEmpty {
                HistoryEmptyState(
                    title: "Your words will appear here",
                    message: "Hold Fn to dictate. Return here to review or copy a result."
                )
            } else {
                HSplitView {
                    transcriptList
                        .frame(minWidth: 220, idealWidth: 250, maxWidth: 290)
                    Group {
                        if let entry = selectedEntry {
                            detail(entry)
                                .id(entry.id)
                        } else {
                            HistoryEmptyState(
                                title: "Select a result",
                                message: "Choose a dictation from the list to read its text."
                            )
                        }
                    }
                    .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            Divider()
            HStack(spacing: 6) {
                Image(systemName: "lock")
                    .accessibilityHidden(true)
                Text("History is stored on this Mac")
                Spacer()
                Text("↑ ↓ to browse")
                Text("·")
                Text("⌘C to copy")
                if !entries.isEmpty {
                    Divider().frame(height: 12).padding(.horizontal, 8)
                    Button("Clear All", role: .destructive, action: onClear)
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Clear all history")
                        .accessibilityHint("Removes all transcription entries")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.vertical, 9)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WindowPalette.canvas)
        .onAppear(perform: reconcileSelection)
        .onChange(of: entries.map(\.id)) { _, _ in reconcileSelection() }
        .onKeyPress(.upArrow) {
            navigateSelection(direction: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            navigateSelection(direction: 1)
            return .handled
        }
        .background {
            Button("Copy selected result") {
                HistoryCopyCommand.perform(firstResponder: NSApp.keyWindow?.firstResponder) {
                    if let selectedEntryID { onCopy(selectedEntryID) }
                }
            }
            .keyboardShortcut("c", modifiers: .command)
            .hidden()
        }
    }

    private var transcriptList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("RECENT DICTATIONS")
                .font(.caption.weight(.medium))
                .tracking(0.6)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)
                .accessibilityAddTraits(.isHeader)

            ScrollViewReader { proxy in
                List(selection: $selectedEntryID) {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(entry.displayText.isEmpty ? "Empty result" : entry.displayText)
                                .font(.body)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            HStack(spacing: 6) {
                                Text(entry.formattedTime)
                                Text("·")
                                Text(entry.safePresetName).lineLimit(1)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                        .tag(entry.id)
                        .id(entry.id)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(entry.formattedDate), \(entry.safePresetName), \(entry.displayText)")
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .accessibilityLabel("Dictation history")
                .onChange(of: selectedEntryID) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
                .onAppear {
                    if let selectedEntryID { proxy.scrollTo(selectedEntryID) }
                }
            }
        }
        .background(WindowPalette.sidebar)
    }

    private func reconcileSelection() {
        if !entries.contains(where: { $0.id == selectedEntryID }) {
            selectedEntryID = entries.first?.id
        }
    }

    private func navigateSelection(direction: Int) {
        guard !entries.isEmpty else { return }
        guard let index = entries.firstIndex(where: { $0.id == selectedEntryID }) else {
            selectedEntryID = entries.first?.id
            return
        }
        selectedEntryID = entries[max(0, min(entries.count - 1, index + direction))].id
    }
}

private struct HistoryEmptyState: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title).font(.title3.weight(.semibold))
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Selectable text is supplied by the caller so guarded Copy stays guarded.
struct HistoryTranscriptDetail<TextContent: View, Status: View, Actions: View>: View {
    let entry: HistoryEntry
    let copyFinal: () -> Void
    let copyOriginal: () -> Void
    let copyVariant: (String) -> Void
    let copyAudit: () -> Void
    @ViewBuilder var selectableText: (String) -> TextContent
    @ViewBuilder var status: () -> Status
    @ViewBuilder var actions: () -> Actions
    @State private var showsOriginal = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.formattedDate)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(entry.safePresetName)
                            .font(.system(size: 18, weight: .semibold))
                            .accessibilityAddTraits(.isHeader)
                        status()
                    }
                    Spacer(minLength: 8)
                    Button(action: copyFinal) {
                        Label("Copy Text", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .accessibilityLabel("Copy final result")
                    .accessibilityHint("Copies the selected variant's text")
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Final text").font(.caption.weight(.semibold))
                        Spacer()
                        Text("\(entry.refined.split(whereSeparator: \.isWhitespace).count) words")
                            .font(.caption.monospacedDigit())
                    }
                    .foregroundStyle(.secondary)
                    selectableText(entry.refined)
                        .font(.system(size: 15))
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .accessibilityLabel("Final result: \(entry.refined)")
                }

                Divider()
                    .overlay(WindowPalette.border)

                VStack(alignment: .leading, spacing: 14) {
                    if entry.hasDistinctOriginalBaseline {
                        DisclosureGroup("Original transcription", isExpanded: $showsOriginal) {
                            VStack(alignment: .leading, spacing: 10) {
                                selectableText(entry.original)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Button("Copy original", action: copyOriginal)
                                    .buttonStyle(.bordered)
                            }
                            .padding(.top, 8)
                        }
                        Divider()
                    }

                    DisclosureGroup(entry.hasParallelAuditTrail ? "Variants & prompt details" : "Prompt details") {
                        VStack(alignment: .leading, spacing: 20) {
                            let variants = entry.variants ?? [entry.safePresetName: entry.refined]
                            ForEach(variants.keys.sorted(), id: \.self) { name in
                                variant(name: name, text: variants[name] ?? "")
                            }
                            Button(action: copyAudit) {
                                Label("Copy Full Audit Log", systemImage: "doc.plaintext")
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Copy full audit log")
                            .accessibilityHint("Copies all variants as formatted markdown")
                        }
                        .padding(.top, 16)
                    }
                }
                .font(.callout)

                actions()
            }
            .padding(20)
        }
        .background(WindowPalette.canvas)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Transcription from \(entry.formattedDate)")
    }

    private func variant(name: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(name).fontWeight(.semibold)
                if name == entry.safePresetName {
                    Text("Selected").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Copy") { copyVariant(name) }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Copy \(name) variant")
            }
            if entry.hasParallelAuditTrail || text != entry.refined {
                selectableText(text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            let provenance = entry.promptProvenance(for: name)
            if let prompt = provenance.effectivePrompt {
                promptBlock("Effective prompt", text: prompt)
            }
            if provenance.showsBasePromptSeparately, let prompt = provenance.basePrompt {
                promptBlock("Base prompt", text: prompt)
            }
            if provenance.effectivePrompt == nil {
                Text("No prompt was saved for this result.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func promptBlock(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            Text(text)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
