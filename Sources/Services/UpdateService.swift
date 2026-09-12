import Foundation
import AppKit

@MainActor
final class UpdateService: ObservableObject {
    static let shared = UpdateService()
    
    @Published var isChecking = false
    @Published var updateAvailable = false
    @Published var latestVersion: String?
    @Published var releaseURL: URL?
    @Published var releaseNotes: String?
    
    private let selector: ReleaseSelector
    private let currentVersionProvider: @MainActor () -> String
    private let dataLoader: @MainActor (URLRequest) async throws -> (Data, URLResponse)

    init(
        operatingSystemVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion,
        currentVersion: @escaping @MainActor () -> String = {
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        },
        dataLoader: @escaping @MainActor (URLRequest) async throws -> (Data, URLResponse) = { request in
            try await URLSession.shared.data(for: request)
        }
    ) {
        selector = ReleaseSelector(currentOSVersion: operatingSystemVersion)
        currentVersionProvider = currentVersion
        self.dataLoader = dataLoader
    }
    
    var currentVersion: String {
        currentVersionProvider()
    }
    
    var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }
    
    @discardableResult
    func checkForUpdates(automatically: Bool = false) async -> UpdateCheckOutcome {
        guard !automatically || AppIdentity.updateChecksEnabled else {
            return .disabled
        }

        isChecking = true
        defer { isChecking = false }
        clearSelectedRelease()

        guard let url = URL(
            string: "https://api.github.com/repos/Skeptomenos/Murmeln/releases?per_page=100"
        ) else {
            return .failed
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        do {
            let (data, response) = try await dataLoader(request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return .failed
            }

            let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
            guard let release = selector.selectNewestCompatible(
                from: releases,
                currentVersion: currentVersion
            ) else {
                return .upToDate
            }
            guard let selectedVersion = selector.normalizedVersion(for: release),
                  let selectedURL = selector.trustedURL(for: release) else {
                return .failed
            }

            latestVersion = selectedVersion
            releaseURL = selectedURL
            releaseNotes = release.body
            updateAvailable = true

            #if DEBUG
            print("🆕 Update available: \(currentVersion) → \(selectedVersion)")
            #endif
            return .updateAvailable
        } catch {
            #if DEBUG
            print("⚠️ Failed to check for updates: \(error.localizedDescription)")
            #endif
            return .failed
        }
    }

    private func clearSelectedRelease() {
        updateAvailable = false
        latestVersion = nil
        releaseURL = nil
        releaseNotes = nil
    }
    
    func openReleasePage() {
        guard let url = releaseURL else { return }
        NSWorkspace.shared.open(url)
    }
    
    func showUpdateAlert() {
        guard updateAvailable, let version = latestVersion else { return }
        
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "\(AppIdentity.displayName) \(version) is available. You have \(currentVersion).\n\nWould you like to download it?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")
        
        if let notes = releaseNotes, !notes.isEmpty {
            let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
            let textView = NSTextView(frame: scrollView.bounds)
            textView.string = notes
            textView.isEditable = false
            textView.font = NSFont.systemFont(ofSize: 11)
            scrollView.documentView = textView
            scrollView.hasVerticalScroller = true
            alert.accessoryView = scrollView
        }
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openReleasePage()
        }
    }
    
    func showUpToDateAlert() {
        let alert = NSAlert()
        alert.messageText = "You're Up to Date"
        alert.informativeText = "\(AppIdentity.displayName) \(currentVersion) is the latest version."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func showUpdateCheckFailedAlert() {
        let alert = NSAlert()
        alert.messageText = "Could Not Check for Updates"
        alert.informativeText = "Check your internet connection and try again."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
