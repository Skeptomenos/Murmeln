import SwiftUI

/// Both menu and notice use these same live actions and exact result identity.
struct RecoveryActionsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        if appState.hasPasteRecovery {
            Text(appState.recoveryMessage ?? "Your text is available to copy.")
            Button("Copy transcript", systemImage: "doc.on.doc") { appState.copyFailedPasteAgain() }
            Button("Show result in History", systemImage: "clock") {
                HistoryWindowController.shared.show(entryID: appState.recoveryEntryID)
            }
            Button("Dismiss", systemImage: "xmark") { appState.dismissPasteRecovery() }
        }
    }
}
