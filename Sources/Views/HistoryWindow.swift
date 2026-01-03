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
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "History"
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        
        NSApp.activate(ignoringOtherApps: true)
        
        self.window = window
    }
}

struct HistoryView: View {
    @ObservedObject private var store = HistoryStore.shared
    @State private var selectedEntry: HistoryEntry?
    @State private var showOriginal = false
    
    var body: some View {
        NavigationSplitView {
            List(store.entries, selection: $selectedEntry) { entry in
                HistoryRowView(entry: entry)
                    .tag(entry)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 200)
        } detail: {
            if let entry = selectedEntry {
                HistoryDetailView(entry: entry, showOriginal: $showOriginal)
            } else {
                ContentUnavailableView {
                    Label("No Selection", systemImage: "text.bubble")
                } description: {
                    Text("Select an entry to view details")
                }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                if selectedEntry != nil {
                    Toggle(isOn: $showOriginal) {
                        Label("Original", systemImage: showOriginal ? "doc.text.fill" : "doc.text")
                    }
                    .help(showOriginal ? "Showing original" : "Showing refined")
                }
                
                if !store.entries.isEmpty {
                    Button {
                        store.clear()
                        selectedEntry = nil
                    } label: {
                        Label("Clear All", systemImage: "trash")
                    }
                }
            }
        }
    }
}

struct HistoryRowView: View {
    let entry: HistoryEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.formattedDate)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(entry.previewText)
                .font(.body)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}

struct HistoryDetailView: View {
    let entry: HistoryEntry
    @Binding var showOriginal: Bool
    
    private var displayText: String {
        showOriginal ? entry.original : entry.refined
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.formattedDate)
                        .font(.headline)
                    
                    Text(showOriginal ? "Original transcription" : "Refined text")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button {
                    copyToClipboard(displayText)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
            }
            
            ScrollView {
                Text(displayText)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            if entry.original != entry.refined {
                HStack {
                    Circle()
                        .fill(showOriginal ? Color.orange : Color.green)
                        .frame(width: 8, height: 8)
                    
                    Text(showOriginal ? "Original" : "Refined")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("\(displayText.count) characters")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
    }
    
    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
