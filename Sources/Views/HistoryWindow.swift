import SwiftUI
import AppKit

@MainActor
final class HistoryWindowController: ObservableObject {
    static let shared = HistoryWindowController()
    
    private var window: NSWindow?
    
    private init() {}
    
    func show() {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let contentView = HistoryView()
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 800),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = AppIdentity.historyWindowTitle
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 800, height: 600)
        window.makeKeyAndOrderFront(nil)
        
        NSApp.activate(ignoringOtherApps: true)
        
        self.window = window
    }
}

struct HistoryView: View {
    @ObservedObject private var store = HistoryStore.shared
    @State private var selectedEntryId: UUID?
    
    var body: some View {
        VStack(spacing: 0) {
            if store.entries.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "text.bubble")
                        .font(.largeTitle)
                        .imageScale(.large)
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No transcriptions yet")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Hold Fn to record")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.7))
                }
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 24) {
                            ForEach(store.entries) { entry in
                                HistoryCard(entry: entry, isSelected: selectedEntryId == entry.id)
                                    .id(entry.id)
                                    .onTapGesture {
                                        selectedEntryId = entry.id
                                    }
                            }
                        }
                        .padding(20)
                    }
                    .onChange(of: selectedEntryId) { _, newValue in
                        if let id = newValue {
                            withAnimation {
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }
                    }
                }
                
                Divider()
                
                HStack {
                    Text("\(store.entries.count) entries")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .accessibilityLabel("\(store.entries.count) transcription entries")
                    
                    Spacer()
                    
                    Text("↑↓ Navigate • ⌘C Copy")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.6))
                    
                    Spacer()
                    
                    Button("Clear All") {
                        store.clear()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.red.opacity(0.8))
                    .accessibilityLabel("Clear all history")
                    .accessibilityHint("Removes all transcription entries")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if selectedEntryId == nil, let first = store.entries.first {
                selectedEntryId = first.id
            }
        }
        .onKeyPress(.upArrow) {
            navigateSelection(direction: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            navigateSelection(direction: 1)
            return .handled
        }
        .background {
            Button("") { copySelectedEntry() }
                .keyboardShortcut("c", modifiers: .command)
                .hidden()
        }
    }
    
    private func navigateSelection(direction: Int) {
        guard !store.entries.isEmpty else { return }
        
        if let currentId = selectedEntryId,
           let currentIndex = store.entries.firstIndex(where: { $0.id == currentId }) {
            let newIndex = max(0, min(store.entries.count - 1, currentIndex + direction))
            selectedEntryId = store.entries[newIndex].id
        } else {
            selectedEntryId = store.entries.first?.id
        }
    }
    
    private func copySelectedEntry() {
        guard let id = selectedEntryId,
              let entry = store.entries.first(where: { $0.id == id }) else { return }
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.refined, forType: .string)
    }
}

struct HistoryCard: View {
    let entry: HistoryEntry
    var isSelected: Bool = false
    @State private var isHovering = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            
            VStack(alignment: .leading, spacing: 20) {
                if entry.hasDistinctOriginalBaseline {
                    originalBlock
                }
                
                variantsGrid
            }
            .padding(16)
            
            footer
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isSelected ? 2 : 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Transcription from \(entry.formattedDate)")
        .accessibilityHint("Contains \(entry.hasDistinctOriginalBaseline ? "baseline transcription and " : "")\(entry.variants?.count ?? 1) visible result block\(entry.variants?.count == 1 ? "" : "s"). Press Command C to copy.")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.formattedDate)
                    .font(.caption.weight(.bold))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                    Text("Pasted: \(entry.safePresetName)")
                        .font(.caption2.weight(.black))
                }
                .foregroundColor(.accentColor)
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                if entry.hasParallelAuditTrail {
                    Text("Parallel Audit Trail")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.purple.opacity(0.15))
                        .foregroundColor(.purple)
                        .clipShape(Capsule())
                }
                
                Label("Transcription", systemImage: "waveform")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.15))
                    .foregroundColor(.blue)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Color.secondary.opacity(0.03))
    }
    
    private var originalBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RAW TRANSCRIPTION (BASELINE)")
                .font(.caption2.weight(.black))
                .foregroundColor(.orange)
                .accessibilityAddTraits(.isHeader)
            
            Text(entry.original)
                .font(.system(.body, design: .default))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.orange.opacity(0.05))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.orange.opacity(0.1), lineWidth: 1)
                )
                .accessibilityLabel("Raw transcription: \(entry.original)")
        }
    }
    
    private var variantsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(entry.hasParallelAuditTrail ? "CHARACTERISTIC VARIANTS" : "FINAL RESULT")
                .font(.caption2.weight(.black))
                .foregroundColor(.green)
            
            let variants = entry.variants ?? [entry.safePresetName: entry.refined]
            let sortedNames = variants.keys.sorted()
            
            // Show variants in a grid
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                ForEach(sortedNames, id: \.self) { name in
                    variantCard(name: name, text: variants[name] ?? "", provenance: entry.promptProvenance(for: name))
                }
            }
        }
    }
    
    private func variantCard(name: String, text: String, provenance: HistoryEntry.PromptProvenance) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(name.uppercased())
                    .font(.caption2.weight(.black))
                    .foregroundColor(name == entry.safePresetName ? .accentColor : .secondary)
                
                if name == entry.safePresetName {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundColor(.accentColor)
                }
                
                Spacer()
                
                Button {
                    copyToClipboard(text)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary.opacity(0.5))
                .accessibilityLabel("Copy \(name) variant")
                .accessibilityHint("Copies this variant's text to clipboard")
            }
            
            if let effectivePrompt = provenance.effectivePrompt {
                Text(effectivePrompt)
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(4)
            }

            if provenance.showsBasePromptSeparately, let basePrompt = provenance.basePrompt {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Base Prompt")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.secondary)

                    Text(basePrompt)
                        .font(.caption2.monospaced())
                        .foregroundColor(.secondary.opacity(0.7))
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.04))
                        .cornerRadius(4)
                }
            }
            
            Text(text)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .topLeading)
                .padding(8)
                .background(name == entry.safePresetName ? Color.accentColor.opacity(0.05) : Color.secondary.opacity(0.03))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(name == entry.safePresetName ? Color.accentColor.opacity(0.2) : Color.clear, lineWidth: 1)
                )
        }
    }
    
    private var footer: some View {
        HStack(spacing: 12) {
            Spacer()
            
            Button {
                copyFullAudit()
            } label: {
                Label("Copy Full Audit Log", systemImage: "cpu.fill")
                    .font(.caption.weight(.bold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.purple)
            .accessibilityLabel("Copy full audit log")
            .accessibilityHint("Copies all variants as formatted markdown")
            
            Button {
                copyToClipboard(entry.refined)
            } label: {
                Label("Copy Final Result", systemImage: "doc.on.doc")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Copy final result")
            .accessibilityHint("Copies the selected variant's text")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .padding(.top, 4)
    }
    
    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    
    private func copyFullAudit() {
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
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
    }
}
