import SwiftUI
import AppKit

@MainActor
final class HistoryWindowController: ObservableObject {
    static let shared = HistoryWindowController()

    private var window: NSWindow?

    private init() {}

    func show(entryID: UUID? = nil) {
        if let existingWindow = window {
            if let entryID { existingWindow.contentView = NSHostingView(rootView: HistoryView(selectedEntryID: entryID)) }
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = HistoryView(selectedEntryID: entryID)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.title = AppIdentity.historyWindowTitle
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 720, height: 460)
        window.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }
}

struct HistoryView: View {
    @AppStorage("windowAppearance") private var appearance: WindowAppearance = .dark
    @ObservedObject private var store = HistoryStore.shared
    @State private var selectedEntryId: UUID?
    @StateObject private var copier = HistoryCopyController(store: .shared)
    @State private var confirmClear = false

    init(selectedEntryID: UUID? = nil) {
        _selectedEntryId = State(initialValue: selectedEntryID)
    }

    var body: some View {
        HistoryBrowser(
            entries: store.entries,
            selectedEntryID: $selectedEntryId,
            onCopy: { id in copier.copy(id: id, payload: .finalResult) },
            onClear: { confirmClear = true },
            notice: {
                VStack(alignment: .leading, spacing: 8) {
                    HistorySaveNotice(store: store)
                    if let message = copier.message {
                        Text(message).accessibilityLabel(message)
                    }
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
            },
            detail: { entry in
                HistoryCard(entry: entry, store: store, copier: copier)
            }
        )
        .windowAppearance(appearance)
        .confirmationDialog("Delete all History?", isPresented: $confirmClear) {
            Button("Delete all entries", role: .destructive) { store.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all saved and unsaved results. This cannot be undone.")
        }
    }
}

struct HistoryCard: View {
    let entry: HistoryEntry
    @ObservedObject var store: HistoryStore
    @ObservedObject var copier: HistoryCopyController
    @State private var confirmDelete = false

    var body: some View {
        HistoryTranscriptDetail(
            entry: entry,
            copyFinal: { copier.copy(id: entry.id, payload: .finalResult) },
            copyOriginal: { copier.copy(id: entry.id, payload: .original) },
            copyVariant: { name in copier.copy(id: entry.id, payload: .variant(name)) },
            copyAudit: { copier.copy(id: entry.id, payload: .fullAudit) },
            selectableText: { text in
                HistorySelectableText(text: text) {
                    copier.copySelection(id: entry.id, text: $0)
                }
            },
            status: {
                Text(store.isSaved(entry.id) ? "Saved" : (store.saveState == .saving ? "Saving…" : "Not saved"))
                    .font(.caption)
                    .foregroundStyle(store.isSaved(entry.id) ? Color.secondary : Color.orange)
            },
            actions: {
                HStack {
                    Spacer()
                    Button("Delete result", role: .destructive) { confirmDelete = true }
                        .buttonStyle(.borderless)
                        .disabled(store.mutationsSuspended)
                }
            }
        )
        .confirmationDialog("Delete this result?", isPresented: $confirmDelete) {
            Button("Delete result", role: .destructive) { store.remove(entry: entry) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(store.isSaved(entry.id) ? "This removes the result from History." : "This result has not been saved. Deleting it loses the retained text.")
        }
    }
}
