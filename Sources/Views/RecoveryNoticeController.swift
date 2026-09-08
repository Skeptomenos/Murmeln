import AppKit
import Combine
import SwiftUI

/// An unsolicited notice never becomes the key window. Keyboard actions remain
/// in the menu; opening History is a separate explicit user action.
@MainActor
final class RecoveryNoticeController: NSObject {
    private let appState: AppState
    private let history: HistoryStore
    private var panel: NSPanel?
    private var subscriptions = Set<AnyCancellable>()
    private var sessionVisible = true
    private var screenLocked = false
    private var sleeping = false
    private let displayOverride: ((Bool) -> Void)?

    init(appState: AppState, history: HistoryStore,
         workspaceNotifications: NotificationCenter = NSWorkspace.shared.notificationCenter,
         lockNotifications: NotificationCenter = DistributedNotificationCenter.default(),
         displayOverride: ((Bool) -> Void)? = nil) {
        self.appState = appState
        self.history = history
        self.displayOverride = displayOverride
        super.init()
        appState.objectWillChange.merge(with: history.objectWillChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.refresh() }
            .store(in: &subscriptions)
        let workspace = workspaceNotifications
        workspace.addObserver(self, selector: #selector(sessionResigned), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        workspace.addObserver(self, selector: #selector(sessionBecameActive), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        workspace.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        let distributed = lockNotifications
        distributed.addObserver(self, selector: #selector(screenDidLock), name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        distributed.addObserver(self, selector: #selector(screenDidUnlock), name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
    }

    @objc private func sessionResigned() { sessionVisible = false; refresh() }
    @objc private func sessionBecameActive() { sessionVisible = true; refresh() }
    @objc private func willSleep() { sleeping = true; refresh() }
    @objc private func didWake() { sleeping = false; refresh() }
    @objc private func screenDidLock() { screenLocked = true; refresh() }
    @objc private func screenDidUnlock() { screenLocked = false; refresh() }

    private func refresh() {
        let shouldShow = sessionVisible && !screenLocked && !sleeping && !appState.isTerminating
            && appState.needsPasteRecoveryAttention
        if let displayOverride {
            displayOverride(shouldShow)
            return
        }
        guard shouldShow else {
            panel?.orderOut(nil)
            return
        }
        if panel == nil {
            let notice = RecoveryNoticePanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 260),
                styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView], backing: .buffered, defer: false)
            notice.title = "Dictation available"
            notice.titleVisibility = .hidden
            notice.titlebarAppearsTransparent = true
            notice.isReleasedWhenClosed = false
            notice.isFloatingPanel = true
            notice.hidesOnDeactivate = false
            notice.level = .floating
            notice.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            notice.contentView = NSHostingView(rootView: RecoveryNoticeView(appState: appState, history: history))
            panel = notice
        }
        if let panel, let content = panel.contentView {
            content.layoutSubtreeIfNeeded()
            panel.setContentSize(content.fittingSize)
        }
        if let screen = NSScreen.main, let panel, !panel.isVisible {
            panel.setFrameTopLeftPoint(NSPoint(x: screen.visibleFrame.maxX - 400, y: screen.visibleFrame.maxY - 20))
            panel.orderFrontRegardless()
        }
    }
}

@MainActor
final class RecoveryNoticePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct RecoveryNoticeView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var history: HistoryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Dictation available", systemImage: "text.bubble")
                .font(.headline)
            RecoveryActionsView(appState: appState)
            if let id = appState.recoveryEntryID {
                Text(history.isSaved(id) ? "Saved in History." : "Not yet saved. Keep Murmeln open.")
                    .font(.caption)
            }
        }
        .padding(20)
        .frame(width: 380, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}
