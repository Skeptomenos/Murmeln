import Testing
@testable import mrml

@Suite("WhisperKit Decode Request Tests")
struct WhisperKitDecodeRequestTests {
    @MainActor
    @Test("Decode request strips unsupported negative suppress-token sentinels")
    func decodeRequestStripsUnsupportedNegativeSuppressTokens() {
        let settings = PipelineSettingsSnapshot(
            transcriptionProvider: .whisperKit,
            transcriptionAPIKey: "",
            transcriptionBaseURL: "",
            transcriptionModel: "openai_whisper-small",
            refinementProvider: .openAI,
            refinementAPIKey: "",
            refinementBaseURL: "",
            refinementModel: "gpt-4o-mini",
            skipRefinement: true,
            parallelRefinementEnabled: false,
            whisperKitProfile: .balanced,
            whisperKitTemperature: 0.0,
            whisperKitPromptPrefill: false,
            whisperKitEnableTimestamps: false,
            whisperKitUseVAD: true,
            whisperKitLanguages: [.english]
        )

        let prepared = WhisperKitService.prepareDecoding(settings: settings)

        #expect(prepared.options.supressTokens.isEmpty)
        #expect(prepared.requestShape.suppressTokens.isEmpty)
        #expect(prepared.requestShape.droppedSuppressTokens == [-1])
    }

    @MainActor
    @Test("Balanced preset request shape reflects actual decode options")
    func balancedPresetRequestShapeReflectsActualDecodeOptions() {
        let settings = PipelineSettingsSnapshot(
            transcriptionProvider: .whisperKit,
            transcriptionAPIKey: "",
            transcriptionBaseURL: "",
            transcriptionModel: "openai_whisper-small",
            refinementProvider: .openAI,
            refinementAPIKey: "",
            refinementBaseURL: "",
            refinementModel: "gpt-4o-mini",
            skipRefinement: true,
            parallelRefinementEnabled: false,
            whisperKitProfile: .balanced,
            whisperKitTemperature: 0.0,
            whisperKitPromptPrefill: false,
            whisperKitEnableTimestamps: false,
            whisperKitUseVAD: true,
            whisperKitLanguages: [.english]
        )

        let prepared = WhisperKitService.prepareDecoding(settings: settings)

        #expect(prepared.requestShape.languageMode == TranscriptionLanguageMode.explicit)
        #expect(prepared.requestShape.languageCode == "en")
        #expect(prepared.requestShape.detectLanguage == false)
        #expect(prepared.requestShape.usePrefillPrompt == true)
        #expect(prepared.requestShape.usePrefillCache == true)
        #expect(prepared.requestShape.withoutTimestamps == false)
        #expect(prepared.requestShape.chunkingStrategy == "none")
    }
}
