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
    
    private let repoOwner = "Skeptomenos"
    private let repoName = "Murmeln"
    
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }
    
    var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }
    
    func checkForUpdates(automatically: Bool = false) async {
        guard !automatically || AppIdentity.updateChecksEnabled else {
            return
        }

        isChecking = true
        defer { isChecking = false }
        
        guard let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest") else {
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return
            }
            
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            
            let latestVersionClean = release.tagName.replacingOccurrences(of: "v", with: "")
            latestVersion = latestVersionClean
            releaseURL = URL(string: release.htmlURL)
            releaseNotes = release.body
            
            updateAvailable = isNewerVersion(latestVersionClean, than: currentVersion)
            
            #if DEBUG
            if updateAvailable {
                print("🆕 Update available: \(currentVersion) → \(latestVersionClean)")
            } else {
                print("✅ \(AppIdentity.displayName) is up to date (\(currentVersion))")
            }
            #endif
        } catch {
            #if DEBUG
            print("⚠️ Failed to check for updates: \(error.localizedDescription)")
            #endif
        }
    }
    
    private func isNewerVersion(_ latest: String, than current: String) -> Bool {
        let latestParts = latest.split(separator: ".").compactMap { Int($0) }
        let currentParts = current.split(separator: ".").compactMap { Int($0) }
        
        for i in 0..<max(latestParts.count, currentParts.count) {
            let latestPart = i < latestParts.count ? latestParts[i] : 0
            let currentPart = i < currentParts.count ? currentParts[i] : 0
            
            if latestPart > currentPart { return true }
            if latestPart < currentPart { return false }
        }
        
        return false
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
}

struct GitHubRelease: Codable {
    let tagName: String
    let htmlURL: String
    let body: String?
    
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case body
    }
}
