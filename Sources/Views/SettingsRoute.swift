import Observation

@MainActor
@Observable
final class SettingsRoute {
    private(set) var selectedPage: SettingsPage

    init(selectedPage: SettingsPage = .transcription) {
        self.selectedPage = selectedPage
    }

    func select(_ page: SettingsPage) {
        selectedPage = page
    }
}
