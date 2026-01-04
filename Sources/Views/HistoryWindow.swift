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
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "History"
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 600, height: 400)
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
                    LazyVStack(spacing: 16) {
                        ForEach(store.entries) { entry in
                            HistoryCard(entry: entry)
                        }
                    }
                    .padding(16)
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
    
    private var hasChanges: Bool {
        entry.original != entry.refined
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            
            if hasChanges {
                sideBySideContent
            } else {
                singleContent
            }
            
            footer
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.formattedDate)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 4) {
                    Image(systemName: "tag.fill")
                        .font(.system(size: 8))
                    Text(entry.safePresetName)
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundColor(.accentColor)
            }
            
            Spacer()
            
            if hasChanges {
                Label("Refined", systemImage: "sparkles")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.15))
                    .foregroundColor(.blue)
                    .clipShape(Capsule())
            } else {
                Text("One-Call")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.15))
                    .foregroundColor(.secondary)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var sideBySideContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("SYSTEM PROMPT")
                    .font(.system(size: 8, weight: .black))
                    .foregroundColor(.secondary.opacity(0.8))
                
                Text(entry.safeSystemPrompt)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(6)
            }
            .padding(.horizontal, 16)

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ORIGINAL")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.orange.opacity(0.8))
                    
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
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("REFINED")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.green.opacity(0.8))
                    
                    Text(entry.refined)
                        .font(.system(.body, design: .default))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.green.opacity(0.05))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.green.opacity(0.1), lineWidth: 1)
                        )
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 12)
    }
    
    private var singleContent: some View {
        Text(entry.refined)
            .font(.body)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(8)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
    }
    
    private var footer: some View {
        HStack(spacing: 12) {
            Spacer()
            
            if hasChanges {
                Button {
                    copyAsMarkdown()
                } label: {
                    Label("Copy both for LLM", systemImage: "doc.on.doc.fill")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .tint(.blue)
                .help("Copy original and refined text formatted for LLM training")
            }
            
            Button {
                copyToClipboard(entry.refined)
            } label: {
                Label("Copy Refined", systemImage: "doc.on.doc")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)
            .help("Copy only the refined text")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
    
    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    
    private func copyAsMarkdown() {
        let markdown = """
        ### Prompt Information
        - **Preset**: \(entry.safePresetName)
        - **System Prompt**: \(entry.safeSystemPrompt)
        
        ### Original Transcription
        \(entry.original)
        
        ### Refined Output
        \(entry.refined)
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
    }
}
