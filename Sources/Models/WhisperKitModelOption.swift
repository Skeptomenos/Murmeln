struct WhisperKitModelOption: Identifiable, Equatable, Sendable {
    let name: String
    let variant: String
    let size: String
    let speed: String
    let quality: String
    let recommendedRAM: String

    var id: String { variant }

    static let all: [WhisperKitModelOption] = [
        WhisperKitModelOption(
            name: "Tiny",
            variant: "openai_whisper-tiny",
            size: "~75 MB",
            speed: "Fastest",
            quality: "Basic",
            recommendedRAM: "< 4GB"
        ),
        WhisperKitModelOption(
            name: "Base",
            variant: "openai_whisper-base",
            size: "~142 MB",
            speed: "Fast",
            quality: "Good",
            recommendedRAM: "8GB"
        ),
        WhisperKitModelOption(
            name: "Small",
            variant: "openai_whisper-small",
            size: "~466 MB",
            speed: "Moderate",
            quality: "Better",
            recommendedRAM: "8GB"
        ),
        WhisperKitModelOption(
            name: "Medium",
            variant: "openai_whisper-medium",
            size: "~1.5 GB",
            speed: "Slower",
            quality: "High",
            recommendedRAM: "16GB"
        ),
        WhisperKitModelOption(
            name: "Large v3",
            variant: "openai_whisper-large-v3",
            size: "~2.9 GB",
            speed: "Slowest",
            quality: "Best",
            recommendedRAM: "16GB+"
        )
    ]
}
