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
        
        window.title = "History & Prompt Audit"
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
    
    var body: some View {
        VStack(spacing: 0) {
            if store.entries.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 48))
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
                ScrollView {
                    LazyVStack(spacing: 24) {
                        ForEach(store.entries) { entry in
                            HistoryCard(entry: entry)
                        }
                    }
                    .padding(20)
                }
                
                Divider()
                
                HStack {
                    Text("\(store.entries.count) entries")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button("Clear All") {
                        store.clear()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(.red.opacity(0.8))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct HistoryCard: View {
    let entry: HistoryEntry
    @State private var isHovering = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            
            VStack(alignment: .leading, spacing: 20) {
                originalBlock
                
                variantsGrid
            }
            .padding(16)
            
            footer
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.formattedDate)
                    .font(.caption.weight(.bold))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 8))
                    Text("Pasted: \(entry.safePresetName)")
                        .font(.system(size: 9, weight: .black))
                }
                .foregroundColor(.accentColor)
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                if entry.variants != nil {
                    Text("Parallel Audit Trail")
                        .font(.system(size: 9, weight: .bold))
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
                .font(.system(size: 9, weight: .black))
                .foregroundColor(.orange)
            
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
        }
    }
    
    private var variantsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CHARACTERISTIC VARIANTS")
                .font(.system(size: 9, weight: .black))
                .foregroundColor(.green)
            
            let variants = entry.variants ?? [entry.safePresetName: entry.refined]
            let sortedNames = variants.keys.sorted()
            
            // Show variants in a grid
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                ForEach(sortedNames, id: \.self) { name in
                    variantCard(name: name, text: variants[name] ?? "", prompt: entry.variantPrompts?[name] ?? "")
                }
            }
        }
    }
    
    private func variantCard(name: String, text: String, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(name.uppercased())
                    .font(.system(size: 8, weight: .black))
                    .foregroundColor(name == entry.safePresetName ? .accentColor : .secondary)
                
                if name == entry.safePresetName {
                    Image(systemName: "star.fill")
                        .font(.system(size: 7))
                        .foregroundColor(.accentColor)
                }
                
                Spacer()
                
                Button {
                    copyToClipboard(text)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 9))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary.opacity(0.5))
            }
            
            if !prompt.isEmpty {
                Text(prompt)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.7))
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(4)
            }
            
            Text(text)
                .font(.system(size: 11))
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
            
            Button {
                copyToClipboard(entry.refined)
            } label: {
                Label("Copy Final Result", systemImage: "doc.on.doc")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
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
        var markdown = "# Murmeln Transcription Audit Trail\n"
        markdown += "**Date**: \(entry.formattedDate)\n"
        markdown += "**Selected Characteristic**: \(entry.safePresetName)\n\n"
        
        markdown += "## 1. Raw Transcription (Baseline)\n"
        markdown += "> \(entry.original)\n\n"
        
        markdown += "## 2. Refinement Variants\n\n"
        
        let variants = entry.variants ?? [entry.safePresetName: entry.refined]
        for name in variants.keys.sorted() {
            let text = variants[name] ?? ""
            let prompt = entry.variantPrompts?[name] ?? ""
            
            markdown += "### Variant: \(name)\(name == entry.safePresetName ? " (SELECTED)" : "")\n"
            if !prompt.isEmpty {
                markdown += "**System Prompt**:\n```\n\(prompt)\n```\n\n"
            }
            markdown += "**Result**:\n\(text)\n\n"
            markdown += "---\n\n"
        }
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
    }
}
