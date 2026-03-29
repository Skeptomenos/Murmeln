import Foundation

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
