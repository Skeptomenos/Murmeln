import Foundation
import Testing
@testable import mrml

private struct LegacyCohereLanguageCase: Sendable {
    let name: String
    let migratedCode: String
    let runtimeCode: String
}

/// Slice 4 probe: the one-time migration from per-backend legacy settings
/// (`transcriptionProviderRaw` + `whisperKitLanguagesJSON` + `cohereLanguageRaw`)
/// to the catalog pair (`selectedModelID`, `preferredLanguage`). The mapping
/// is a pure function so the whole matrix runs without touching UserDefaults.
@Suite("Settings Migration Tests")
struct SettingsMigrationTests {

    // MARK: Pure mapping matrix

    @Test("Fresh install (no persisted provider) does not migrate")
    func freshInstallNoMigration() {
        let outcome = AppSettings.catalogMigration(
            providerRaw: nil,
            whisperKitLanguagesJSON: nil,
            cohereLanguageRaw: nil
        )
        #expect(outcome == nil)
    }

    @Test("Fresh install lands on the catalog default model (Slice 5 flip)")
    func freshInstallDefaultsToCatalogDefault() {
        // Slice 0a decision: Parakeet v3 is the fresh-install default.
        let selection = AppSettings.initialSelection(
            providerRaw: nil,
            selectedModelIDRaw: ""
        )
        #expect(selection == ModelCatalog.defaultModelID.rawValue)
    }

    @Test("Existing legacy cloud user keeps the legacy path on the default flip")
    func legacyCloudUserUnaffectedByDefaultFlip() {
        let selection = AppSettings.initialSelection(
            providerRaw: "OpenAI Whisper",
            selectedModelIDRaw: ""
        )
        #expect(selection == nil)
    }

    @Test("Already-selected catalog model wins over the default flip")
    func existingCatalogSelectionWins() {
        let selection = AppSettings.initialSelection(
            providerRaw: nil,
            selectedModelIDRaw: "cohere-transcribe-03-2026-int8"
        )
        #expect(selection == nil, "no flip needed — selection already present")
    }

    @Test("Legacy WhisperKit user with single language maps to whisperkit + explicit code")
    func whisperKitSingleLanguage() throws {
        let outcome = try #require(AppSettings.catalogMigration(
            providerRaw: "WhisperKit (On-Device)",
            whisperKitLanguagesJSON: "[\"German\"]",
            cohereLanguageRaw: nil
        ))
        #expect(outcome.selectedModelID == "whisperkit")
        #expect(outcome.preferredLanguage == "de")
    }

    @Test("Legacy WhisperKit user with multiple languages maps to auto")
    func whisperKitMultiLanguage() throws {
        let outcome = try #require(AppSettings.catalogMigration(
            providerRaw: "WhisperKit (On-Device)",
            whisperKitLanguagesJSON: "[\"German\",\"English\"]",
            cohereLanguageRaw: nil
        ))
        #expect(outcome.selectedModelID == "whisperkit")
        #expect(outcome.preferredLanguage == "auto")
    }

    @Test("Legacy WhisperKit user with corrupt languages JSON maps to auto")
    func whisperKitCorruptLanguages() throws {
        let outcome = try #require(AppSettings.catalogMigration(
            providerRaw: "WhisperKit (On-Device)",
            whisperKitLanguagesJSON: "not json",
            cohereLanguageRaw: nil
        ))
        #expect(outcome.preferredLanguage == "auto")
    }

    @Test("Legacy Cohere user maps to cohere INT8 with the persisted language")
    func cohereUser() throws {
        let outcome = try #require(AppSettings.catalogMigration(
            providerRaw: "Cohere MLX (On-Device)",
            whisperKitLanguagesJSON: nil,
            cohereLanguageRaw: "German"
        ))
        #expect(outcome.selectedModelID == "cohere-transcribe-03-2026-int8")
        #expect(outcome.preferredLanguage == "de")
    }

    @Test("Legacy Cohere user with unknown language falls back to en")
    func cohereUnknownLanguage() throws {
        let outcome = try #require(AppSettings.catalogMigration(
            providerRaw: "Cohere MLX (On-Device)",
            whisperKitLanguagesJSON: nil,
            cohereLanguageRaw: "Klingon"
        ))
        #expect(outcome.preferredLanguage == "en")
    }

    @Test("Every legacy Cohere language has an explicit catalog migration", arguments: [
        LegacyCohereLanguageCase(name: "English", migratedCode: "en", runtimeCode: "en"),
        LegacyCohereLanguageCase(name: "French", migratedCode: "fr", runtimeCode: "fr"),
        LegacyCohereLanguageCase(name: "German", migratedCode: "de", runtimeCode: "de"),
        LegacyCohereLanguageCase(name: "Spanish", migratedCode: "es", runtimeCode: "es"),
        LegacyCohereLanguageCase(name: "Italian", migratedCode: "it", runtimeCode: "it"),
        LegacyCohereLanguageCase(name: "Portuguese", migratedCode: "pt", runtimeCode: "pt"),
        LegacyCohereLanguageCase(name: "Dutch", migratedCode: "nl", runtimeCode: "nl"),
        LegacyCohereLanguageCase(name: "Japanese", migratedCode: "ja", runtimeCode: "ja"),
        LegacyCohereLanguageCase(name: "Korean", migratedCode: "ko", runtimeCode: "ko"),
        LegacyCohereLanguageCase(name: "Chinese", migratedCode: "zh", runtimeCode: "zh"),
        LegacyCohereLanguageCase(name: "Hindi", migratedCode: "en", runtimeCode: "en"),
        LegacyCohereLanguageCase(name: "Russian", migratedCode: "en", runtimeCode: "en"),
        LegacyCohereLanguageCase(name: "Turkish", migratedCode: "en", runtimeCode: "en"),
        LegacyCohereLanguageCase(name: "Polish", migratedCode: "pl", runtimeCode: "pl"),
    ])
    fileprivate func allLegacyCohereLanguagesMigrate(language: LegacyCohereLanguageCase) throws {
        let outcome = try #require(AppSettings.catalogMigration(
            providerRaw: "Cohere MLX (On-Device)",
            whisperKitLanguagesJSON: nil,
            cohereLanguageRaw: language.name
        ))
        #expect(outcome.preferredLanguage == language.migratedCode)

        let runtimeCode = AppSettings.resolvedLanguageCode(
            preferred: outcome.preferredLanguage,
            for: TranscriptionModelID(rawValue: outcome.selectedModelID)
        )
        #expect(runtimeCode == language.runtimeCode)
    }

    @Test("Cloud and server providers pass through unmigrated", arguments: [
        "OpenAI Whisper", "Groq Whisper", "GPT-4o Audio", "Gemini 2.0 Flash", "Local Whisper",
    ])
    func cloudServerPassThrough(providerRaw: String) {
        let outcome = AppSettings.catalogMigration(
            providerRaw: providerRaw,
            whisperKitLanguagesJSON: nil,
            cohereLanguageRaw: nil
        )
        #expect(outcome == nil, "\(providerRaw) must keep the legacy provider path")
    }

    @Test("Unknown/corrupt provider raw value does not migrate (safe default)")
    func corruptProviderRaw() {
        let outcome = AppSettings.catalogMigration(
            providerRaw: "Not A Provider",
            whisperKitLanguagesJSON: nil,
            cohereLanguageRaw: nil
        )
        #expect(outcome == nil)
    }

    // MARK: Migrated-but-not-installed (plan probe case)

    @MainActor
    @Test("Migrated Cohere selection without weights on disk yields the actionable not-installed error, never a silent swap")
    func migratedCohereWithoutWeightsIsActionable() async throws {
        // The retired runtime's model cache is not reusable by FluidAudio: a
        // migrated user's first dictation must surface modelNotInstalled.
        let runtime = MockRuntime(id: .fluidAudio)
        runtime.installedModels = []  // nothing on disk

        let modelID = TranscriptionModelID(rawValue: "cohere-transcribe-03-2026-int8")
        await #expect(throws: TranscriptionRuntimeError.modelNotInstalled(modelID)) {
            try await runtime.load(modelID)
        }
        // The error is user-actionable (names the model, says download).
        let message = TranscriptionRuntimeError.modelNotInstalled(modelID).errorDescription ?? ""
        #expect(message.contains("cohere-transcribe-03-2026-int8"))
        #expect(message.lowercased().contains("download"))
    }
}

/// Slice 4: model switches follow the M6 single-setter discipline —
/// raw value + change signal exactly once per switch.
@MainActor
@Suite("Model Switch Tests", .serialized)
struct ModelSwitchTests {

    @Test("selectedModelID setter updates raw value and fires the change signal exactly once")
    func modelSwitchSingleSetter() {
        let settings = AppSettings()
        let previousModelID = settings.selectedModelIDRaw
        defer { settings.selectedModelIDRaw = previousModelID }

        var signaled: [TranscriptionModelID] = []
        let cancellable = settings.selectedModelChanged.sink { signaled.append($0) }
        defer { cancellable.cancel() }

        let target = TranscriptionModelID(rawValue: "parakeet-tdt-0.6b-v3")
        settings.selectedModelID = target

        #expect(settings.selectedModelIDRaw == target.rawValue)
        #expect(signaled == [target])
    }

    @Test("Selecting a legacy provider clears the catalog selection")
    func legacyProviderClearsCatalogSelection() {
        let settings = AppSettings()
        let previousModelID = settings.selectedModelIDRaw
        let previousRaw = settings.transcriptionProviderRaw
        let previousURL = settings.transcriptionBaseURL
        let previousModel = settings.transcriptionModel
        defer {
            settings.selectedModelIDRaw = previousModelID
            settings.transcriptionProviderRaw = previousRaw
            settings.transcriptionBaseURL = previousURL
            settings.transcriptionModel = previousModel
        }

        settings.selectedModelID = TranscriptionModelID(rawValue: "parakeet-tdt-0.6b-v3")
        settings.transcriptionSelection = .legacy(.openAIWhisper)

        #expect(settings.selectedModelIDRaw.isEmpty)
        #expect(settings.transcriptionProviderRaw == TranscriptionProvider.openAIWhisper.rawValue)
    }

    @Test("Catalog to legacy emits one complete selection transition")
    func catalogToLegacySelectionTransition() {
        let settings = AppSettings()
        let previousModelID = settings.selectedModelIDRaw
        let previousRaw = settings.transcriptionProviderRaw
        let previousURL = settings.transcriptionBaseURL
        let previousModel = settings.transcriptionModel
        defer {
            settings.selectedModelIDRaw = previousModelID
            settings.transcriptionProviderRaw = previousRaw
            settings.transcriptionBaseURL = previousURL
            settings.transcriptionModel = previousModel
        }

        let catalogID = TranscriptionModelID(rawValue: "parakeet-tdt-0.6b-v3")
        settings.transcriptionSelection = .catalog(catalogID)

        var transitions: [AppSettings.TranscriptionSelectionTransition] = []
        let cancellable = settings.transcriptionSelectionChanged.sink { transitions.append($0) }
        defer { cancellable.cancel() }

        settings.transcriptionSelection = .legacy(.openAIWhisper)

        #expect(transitions == [
            .init(previous: .catalog(catalogID), current: .legacy(.openAIWhisper))
        ])
    }

    @Test("Catalog to legacy unloads the resident local runtime")
    func catalogToLegacyUnloadsRuntime() async throws {
        let catalogID = TranscriptionModelID(rawValue: "parakeet-tdt-0.6b-v3")
        let runtime = MockRuntime(id: .fluidAudio)
        runtime.installedModels = [catalogID]
        try await runtime.load(catalogID)

        let lifecycle = TranscriptionSelectionLifecycle { _ in runtime }
        await lifecycle.apply(
            .init(previous: .catalog(catalogID), current: .legacy(.openAIWhisper))
        )

        #expect(runtime.unloadCalls == 1)
        #expect(runtime.state == .notLoaded)
        #expect(runtime.loadCalls == [catalogID])
    }

    @Test("Catalog WhisperKit exposes concrete variant management")
    func catalogWhisperKitExposesVariantManagement() {
        let whisperKitID = TranscriptionModelID.whisperKit
        let parakeetID = TranscriptionModelID(rawValue: "parakeet-tdt-0.6b-v3")

        #expect(TranscriptionSettingsSection.showsWhisperKitVariantManagement(
            for: .catalog(whisperKitID)
        ))
        #expect(TranscriptionSettingsSection.showsWhisperKitVariantManagement(
            for: .legacy(.whisperKit)
        ))
        #expect(!TranscriptionSettingsSection.showsWhisperKitVariantManagement(
            for: .catalog(parakeetID)
        ))
    }

    @Test("preferredLanguage resolves per model capability")
    func preferredLanguageResolution() {
        // Cohere (hintRequired): auto resolves to en; explicit code passes through.
        #expect(AppSettings.resolvedLanguageCode(preferred: "auto", for: TranscriptionModelID(rawValue: "cohere-transcribe-03-2026-int8")) == "en")
        #expect(AppSettings.resolvedLanguageCode(preferred: "de", for: TranscriptionModelID(rawValue: "cohere-transcribe-03-2026-int8")) == "de")
        // Parakeet (autoDetect): auto stays nil (model detects), explicit passes through.
        #expect(AppSettings.resolvedLanguageCode(preferred: "auto", for: TranscriptionModelID(rawValue: "parakeet-tdt-0.6b-v3")) == nil)
        #expect(AppSettings.resolvedLanguageCode(preferred: "de", for: TranscriptionModelID(rawValue: "parakeet-tdt-0.6b-v3")) == "de")
        // A language carried over from another model must not escape the
        // destination model's declared capability set.
        #expect(AppSettings.resolvedLanguageCode(preferred: "ja", for: .whisperKit) == "en")
        #expect(AppSettings.resolvedLanguageCode(preferred: "ja", for: TranscriptionModelID(rawValue: "parakeet-tdt-0.6b-v3")) == nil)
    }
}
