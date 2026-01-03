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
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "History"
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 350, height: 300)
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
                    LazyVStack(spacing: 1) {
                        ForEach(store.entries) { entry in
                            HistoryCard(entry: entry)
                        }
                    }
                    .padding(.vertical, 8)
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
    @State private var showOriginal = false
    @State private var isHovering = false
    
    private var displayText: String {
        showOriginal ? entry.original : entry.refined
    }
    
    private var hasChanges: Bool {
        entry.original != entry.refined
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if hasChanges {
                    Text(showOriginal ? "Original" : "Refined")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(showOriginal ? Color.orange.opacity(0.2) : Color.green.opacity(0.2))
                        .foregroundColor(showOriginal ? .orange : .green)
                        .clipShape(Capsule())
                }
                
                Button {
                    copyToClipboard(displayText)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .opacity(isHovering ? 1 : 0.5)
            }
            
            Text(displayText)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    if hasChanges {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showOriginal.toggle()
                        }
                    }
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isHovering ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.3) : Color.clear)
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
