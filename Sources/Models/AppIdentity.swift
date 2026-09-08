import Foundation
import Security

enum AppIdentity {
    static let productionBundleIdentifier = "com.mrml.app"
    static let productionDisplayName = "Murmeln"
    static let productionAppSupportDirectoryName = "Murmeln"
    static let productionKeychainService = "com.murmeln.apikeys"
    static let productionLoggerSubsystem = "com.murmeln.app"

    static func isDevelopmentBuild(bundleIdentifier: String?) -> Bool {
        (bundleIdentifier ?? productionBundleIdentifier) != productionBundleIdentifier
    }

    static func applicationSupportDirectoryName(bundleIdentifier: String?) -> String {
        isDevelopmentBuild(bundleIdentifier: bundleIdentifier) ? "Murmeln Dev" : productionAppSupportDirectoryName
    }

    static func keychainServiceName(bundleIdentifier: String?) -> String {
        let resolvedBundleIdentifier = bundleIdentifier ?? productionBundleIdentifier
        return isDevelopmentBuild(bundleIdentifier: resolvedBundleIdentifier)
            ? "\(resolvedBundleIdentifier).apikeys"
            : productionKeychainService
    }

    static func loggerSubsystem(bundleIdentifier: String?) -> String {
        isDevelopmentBuild(bundleIdentifier: bundleIdentifier)
            ? "\(productionLoggerSubsystem).dev"
            : productionLoggerSubsystem
    }

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? productionBundleIdentifier
    }

    static var isDevelopmentBuild: Bool {
        isDevelopmentBuild(bundleIdentifier: bundleIdentifier)
    }

    static var displayName: String {
        if let explicitDisplayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
           !explicitDisplayName.isEmpty {
            return explicitDisplayName
        }

        if let bundleName = Bundle.main.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String,
           !bundleName.isEmpty {
            return bundleName
        }

        return isDevelopmentBuild ? "Murmeln Dev" : productionDisplayName
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String ?? "unknown"
    }

    /// Best-effort signing identity for correlation, not a permission or validity receipt.
    /// Cache it so normal paste attempts do not repeatedly inspect the code signature.
    /// Security may read signing information from disk; this does not prove unchanged
    /// executable contents if another process replaces the app while it is running.
    static let codeHash: String? = {
        var ownCode: SecCode?
        guard SecCodeCopySelf([], &ownCode) == errSecSuccess, let ownCode else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(ownCode, [], &staticCode) == errSecSuccess,
              let staticCode else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, [], &information) == errSecSuccess,
              let information = information as? [String: Any] else { return nil }
        return codeHash(signingIdentifier: information[kSecCodeInfoUnique as String] as? Data)
    }()

    static func codeHash(signingIdentifier: Data?) -> String? {
        guard let signingIdentifier, signingIdentifier.count == 20 else { return nil }
        return signingIdentifier.map { String(format: "%02x", $0) }.joined()
    }

    static var applicationSupportDirectoryName: String {
        applicationSupportDirectoryName(bundleIdentifier: bundleIdentifier)
    }

    static var keychainServiceName: String {
        keychainServiceName(bundleIdentifier: bundleIdentifier)
    }

    static var loggerSubsystem: String {
        loggerSubsystem(bundleIdentifier: bundleIdentifier)
    }

    static var defaultsDomain: String {
        bundleIdentifier
    }

    static var updateChecksEnabled: Bool {
        !isDevelopmentBuild
    }

    static var menuBarTitle: String {
        displayName
    }

    static var settingsWindowTitle: String {
        "\(displayName) Settings"
    }

    static var historyWindowTitle: String {
        isDevelopmentBuild ? "History & Prompt Audit (Dev)" : "History & Prompt Audit"
    }

    static var auditTrailTitle: String {
        "# \(displayName) Transcription Audit Trail"
    }

    static var appSupportDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent(applicationSupportDirectoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
