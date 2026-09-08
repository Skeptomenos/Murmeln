import Foundation
import AppKit
import AVFoundation
import CoreGraphics

final class PermissionService: Sendable {
    static let shared = PermissionService()

    private let preflightPostEventAccess: @Sendable () -> Bool
    private let requestPostEventAccessOperation: @Sendable () -> Bool
    private let openURL: @MainActor @Sendable (URL) -> Bool

    enum SettingsNavigation: Equatable {
        case accessibilityPane
        case systemSettings
        case failed
    }

    init(
        preflightPostEventAccess: @escaping @Sendable () -> Bool = {
            CGPreflightPostEventAccess()
        },
        requestPostEventAccess: @escaping @Sendable () -> Bool = {
            CGRequestPostEventAccess()
        },
        openURL: @escaping @MainActor @Sendable (URL) -> Bool = {
            NSWorkspace.shared.open($0)
        }
    ) {
        self.preflightPostEventAccess = preflightPostEventAccess
        self.requestPostEventAccessOperation = requestPostEventAccess
        self.openURL = openURL
    }
    
    func checkMicrophonePermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }
    
    func hasPostEventAccess() -> Bool {
        preflightPostEventAccess()
    }

    func requestPostEventAccess() -> Bool {
        requestPostEventAccessOperation()
    }

    @MainActor
    func openAccessibilitySettings() -> SettingsNavigation {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"),
           openURL(url) {
            return .accessibilityPane
        }
        if openURL(URL(fileURLWithPath: "/System/Applications/System Settings.app")) {
            return .systemSettings
        }
        return .failed
    }
}
