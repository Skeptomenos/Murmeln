import SwiftUI

struct HistorySaveNotice: View {
    @ObservedObject var store: HistoryStore

    var body: some View {
        if store.loadFailed {
            Text("History could not be read. Its existing file has not been overwritten. Recording is paused.")
        } else if store.hasUnpersistedChanges {
            Text(store.saveState == .saving ? "Saving History…" : "History was not saved. Keep Murmeln open to recover your text.")
            if store.hasPendingDeletion {
                Text("Unsaved deletions may reappear after restart.")
            }
            Button("Retry save", systemImage: "externaldrive") { store.retrySave() }
                .disabled(store.saveState == .saving)
        }
    }
}
