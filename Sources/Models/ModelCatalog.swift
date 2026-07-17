import Foundation

/// Stable identifier for a catalog model. Persisted in settings — raw values
/// are a compatibility contract; never rename an existing one.
struct TranscriptionModelID: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: String

    static let whisperKit = Self(rawValue: "whisperkit")
}

/// Which inference engine serves a catalog entry.
enum RuntimeID: String, Codable, Sendable {
    case whisperKit = "whisperkit"
    case fluidAudio = "fluidaudio"
    // Future: case mlxAudio (Granite, Qwen3-ASR 1.7B), case appleSpeech
}

/// How a model consumes the user's language preference.
enum ModelLanguageMode: String, Codable, Sendable {
    /// Model detects the spoken language itself; a hint is optional or ignored.
    case autoDetect = "auto_detect"
    /// Model must be told the language up front (e.g. Cohere's conditioned prompt).
    case hintRequired = "hint_required"
}

/// One supported on-device model. Adding a model in an already-supported
/// runtime family is exactly one new entry here (plus tests).
struct CatalogEntry: Sendable, Equatable {
    let id: TranscriptionModelID
    let displayName: String
    let runtime: RuntimeID
    /// HuggingFace repo the runtime downloads from; nil when the runtime
    /// manages its own model source (WhisperKit's variant picker).
    let sourceRepo: String?
    /// ISO 639-1 codes the model supports.
    let languages: [String]
    let languageMode: ModelLanguageMode
    let approxDownloadMB: Int
    /// Hard per-call audio cap in seconds (Cohere: 35). The runtime's
    /// long-form path handles longer audio; nil = no cap.
    let maxUtteranceSeconds: Int?
    /// User-facing caveat surfaced in the model picker (e.g. Cohere's
    /// per-launch warm-up cost). nil = no caveat.
    let usageNote: String?
    /// Weight quantization when known (e.g. "int8"); emitted in telemetry.
    let quantization: String?
}

/// Static, in-code model catalog (Decision Log: unit-testable, no
/// remote-config surface). Order = display order in the picker; the
/// default model is first.
enum ModelCatalog {

    /// Slice 0a decision (plan Decision Log 2026-07-09): Parakeet v3 default.
    static let defaultModelID = TranscriptionModelID(rawValue: "parakeet-tdt-0.6b-v3")

    static let cohereLanguageCodes = [
        "en", "fr", "de", "es", "it", "pt", "nl", "pl", "el", "ar", "ja", "zh", "ko", "vi",
    ]

    static let parakeetV3LanguageCodes = [
        "bg", "hr", "cs", "da", "nl", "en", "et", "fi", "fr", "de", "el", "hu", "it",
        "lv", "lt", "mt", "pl", "pt", "ro", "ru", "sk", "sl", "es", "sv", "uk",
    ]

    static let entries: [CatalogEntry] = [
        CatalogEntry(
            id: defaultModelID,
            displayName: "Parakeet v3 (Multilingual)",
            runtime: .fluidAudio,
            sourceRepo: "FluidInference/parakeet-tdt-0.6b-v3-coreml",
            languages: parakeetV3LanguageCodes,
            languageMode: .autoDetect,
            approxDownloadMB: 470,
            maxUtteranceSeconds: nil,
            usageNote: nil,
            quantization: nil
        ),
        CatalogEntry(
            id: TranscriptionModelID(rawValue: "parakeet-tdt-0.6b-v2"),
            displayName: "Parakeet v2 (English)",
            runtime: .fluidAudio,
            sourceRepo: "FluidInference/parakeet-tdt-0.6b-v2-coreml",
            languages: ["en"],
            languageMode: .autoDetect,
            approxDownloadMB: 470,
            maxUtteranceSeconds: nil,
            usageNote: "English only; slightly higher English accuracy than v3.",
            quantization: nil
        ),
        CatalogEntry(
            id: TranscriptionModelID(rawValue: "cohere-transcribe-03-2026-int8"),
            displayName: "Cohere Transcribe (14 languages)",
            runtime: .fluidAudio,
            sourceRepo: "FluidInference/cohere-transcribe-03-2026-coreml",
            languages: cohereLanguageCodes,
            languageMode: .hintRequired,
            approxDownloadMB: 2_050,
            maxUtteranceSeconds: 35,
            usageNote: "Takes about 90 seconds to warm up after each app launch and briefly uses a lot of memory (probe finding, macOS 27 beta).",
            quantization: "int8"
        ),
        CatalogEntry(
            id: .whisperKit,
            displayName: "WhisperKit (Whisper)",
            runtime: .whisperKit,
            sourceRepo: nil,
            languages: ["en", "de", "fr", "es", "it"],
            languageMode: .hintRequired,
            approxDownloadMB: 600,
            maxUtteranceSeconds: nil,
            usageNote: "Choose the language you dictate in; short utterances are unreliable with automatic language detection.",
            quantization: nil
        ),
    ]

    static func entry(for id: TranscriptionModelID) -> CatalogEntry? {
        entries.first { $0.id == id }
    }
}
