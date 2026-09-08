import AppKit

/// Main-actor ownership boundary for AppKit global and local event monitors.
@MainActor
struct HotkeyMonitorClient {
    typealias GlobalHandler = @MainActor (NSEvent) -> Void
    typealias LocalHandler = @MainActor (NSEvent) -> NSEvent?
    typealias InstallGlobal = @MainActor (@escaping GlobalHandler) -> Any?
    typealias InstallLocal = @MainActor (@escaping LocalHandler) -> Any?
    typealias Remove = @MainActor (Any) -> Void

    let installGlobalFlagsMonitor: InstallGlobal
    let installLocalFlagsMonitor: InstallLocal
    let removeMonitor: Remove

    static let live = HotkeyMonitorClient(
        installGlobalFlagsMonitor: { handler in
            NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { event in
                handler(event)
            }
        },
        installLocalFlagsMonitor: { handler in
            NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                handler(event)
            }
        },
        removeMonitor: { token in
            NSEvent.removeMonitor(token)
        }
    )
}
