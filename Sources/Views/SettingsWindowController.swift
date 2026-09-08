import AppKit
import SwiftUI

@MainActor
protocol ApplicationPresenting: AnyObject {
    @discardableResult
    func setActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy) -> Bool
    func activate(ignoringOtherApps flag: Bool)
}

extension NSApplication: ApplicationPresenting {}

@MainActor
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private let application: any ApplicationPresenting
    
    private init() {
        application = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = AppIdentity.settingsWindowTitle
        window.contentMinSize = NSSize(width: 720, height: 460)
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        
        window.contentView = NSHostingView(rootView: SettingsView())
    }

    init(application: any ApplicationPresenting, window: NSWindow? = nil) {
        self.application = application
        super.init(window: window)
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    func show() {
        application.setActivationPolicy(.accessory)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        application.activate(ignoringOtherApps: true)
    }
    
    func hide() {
        window?.close()
    }
}
