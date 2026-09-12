@MainActor
final class WhisperKitSelectionControllerTestState {
    var persistedVariant = "openai_whisper-small"
    var loadStarted = false
    var releaseLoad = false
    var dismissCount = 0
    var loadedVariants: [String] = []
    var downloadedVariants: [String] = []
    var downloadStarted = false
    var externalDownloadActive = false
    var cancelDownloadCount = 0
    var loadCount = 0
    var cancellationObserved = false
}
