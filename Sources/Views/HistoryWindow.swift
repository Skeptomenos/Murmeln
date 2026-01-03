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
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "History"
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 500, height: 300)
        window.makeKeyAndOrderFront(nil)
        
        NSApp.activate(ignoringOtherApps: true)
        
        self.window = window
    }
}

struct HistoryView: View {
    @ObservedObject private var store = HistoryStore.shared
    @State private var selectedEntry: HistoryEntry?
    
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
                    LazyVStack(spacing: 12) {
                        ForEach(store.entries) { entry in
                            HistoryCard(entry: entry, isExpanded: selectedEntry?.id == entry.id)
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        if selectedEntry?.id == entry.id {
                                            selectedEntry = nil
                                        } else {
                                            selectedEntry = entry
                                        }
                                    }
                                }
                        }
                    }
                    .padding(12)
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
    let isExpanded: Bool
    @State private var isHovering = false
    
    private var hasChanges: Bool {
        entry.original != entry.refined
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(entry.formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if hasChanges {
                    Text("Original ≠ Refined")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .foregroundColor(.blue)
                        .clipShape(Capsule())
                    
                    Button {
                        copyAsMarkdown()
                    } label: {
                        Image(systemName: "doc.text")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .help("Copy as Markdown (Original + Refined)")
                } else {
                    Text("One-Call Provider")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2))
                        .foregroundColor(.secondary)
                        .clipShape(Capsule())
                }
                
                Button {
                    copyToClipboard(entry.refined)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .help("Copy refined text")
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)
            
            if isExpanded && hasChanges {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Original")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.orange)
                            Spacer()
                            Button {
                                copyToClipboard(entry.original)
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption2)
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)
                        }
                        
                        Text(entry.original)
                            .font(.system(.body, design: .default))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .frame(maxWidth: .infinity)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Refined")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.green)
                            Spacer()
                            Button {
                                copyToClipboard(entry.refined)
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption2)
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)
                        }
                        
                        Text(entry.refined)
                            .font(.system(.body, design: .default))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            } else {
                Text(entry.refined)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
        }
        .background(isHovering ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.2) : Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    
    private func copyAsMarkdown() {
        let markdown = """
        ## Original (Transcription)
        
        \(entry.original)
        
        ## Refined (After Processing)
        
        \(entry.refined)
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
    }
}
