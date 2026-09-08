import Observation

@MainActor
@Observable
final class PastePermissionController {
    private(set) var hasPostEventAccess: Bool
    private(set) var navigationMessage: String?
    private let permissionService: PermissionService

    init(permissionService: PermissionService = .shared) {
        self.permissionService = permissionService
        hasPostEventAccess = permissionService.hasPostEventAccess()
    }

    func refresh() {
        hasPostEventAccess = permissionService.hasPostEventAccess()
        if hasPostEventAccess { navigationMessage = nil }
    }

    func openSettings() {
        _ = permissionService.requestPostEventAccess()
        let result = permissionService.openAccessibilitySettings()
        let instructions = "Privacy & Security → Accessibility"
        navigationMessage = result == .failed
            ? "System Settings could not be opened. \(instructions)"
            : instructions
        refresh()
    }
}
