import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()
    
    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Murmeln Settings"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        
        window.contentView = NSHostingView(rootView: SettingsView())
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    func show() {
        NSApp.setActivationPolicy(.regular)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func hide() {
        window?.close()
        NSApp.setActivationPolicy(.accessory)
    }
}
