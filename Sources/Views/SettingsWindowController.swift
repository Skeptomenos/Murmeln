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
    private let route: SettingsRoute
    private let selectModel: @MainActor (TranscriptionModelID) -> Void
    
    private init() {
        application = NSApplication.shared
        let route = SettingsRoute()
        self.route = route
        selectModel = { modelID in
            AppSettings.shared.selectedModelID = modelID
        }
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
        
        window.contentView = NSHostingView(rootView: SettingsView(route: route))
    }

    init(
        application: any ApplicationPresenting,
        window: NSWindow? = nil,
        route: SettingsRoute = SettingsRoute(),
        selectModel: @escaping @MainActor (TranscriptionModelID) -> Void = { modelID in
            AppSettings.shared.selectedModelID = modelID
        }
    ) {
        self.application = application
        self.route = route
        self.selectModel = selectModel
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

    func showRecovery(for modelID: TranscriptionModelID) {
        guard ModelCatalog.entry(for: modelID) != nil else { return }
        route.select(.transcription)
        selectModel(modelID)
        show()
    }
}

extension SettingsWindowController: SettingsRecoveryPresenting {}
