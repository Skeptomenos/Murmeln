import FluidAudio
import Testing
@testable import mrml

@Suite("ModelCatalog Tests")
struct ModelCatalogTests {

    // MARK: Invariants over the whole catalog

    @Test("Catalog has exactly the four Phase 8 entries")
    func catalogHasExpectedEntries() {
        let ids = ModelCatalog.entries.map(\.id.rawValue)
        #expect(ids == [
            "parakeet-tdt-0.6b-v3",
            "parakeet-tdt-0.6b-v2",
            "cohere-transcribe-03-2026-int8",
            "whisperkit"
        ])
    }

    @Test("Entry IDs are unique")
    func entryIDsAreUnique() {
        let ids = ModelCatalog.entries.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("Every entry declares at least one language")
    func everyEntryHasLanguages() {
        for entry in ModelCatalog.entries {
            #expect(!entry.languages.isEmpty, "\(entry.id.rawValue) has no languages")
        }
    }

    @Test("Every entry has a non-empty display name and positive download size")
    func displayNamesAndSizesAreSane() {
        for entry in ModelCatalog.entries {
            #expect(!entry.displayName.isEmpty)
            #expect(entry.approxDownloadMB > 0, "\(entry.id.rawValue) download size must be positive")
        }
    }

    @Test("maxUtteranceSeconds, when set, is positive")
    func maxUtteranceSecondsIsPositiveWhenSet() {
        for entry in ModelCatalog.entries {
            if let cap = entry.maxUtteranceSeconds {
                #expect(cap > 0, "\(entry.id.rawValue) has non-positive utterance cap")
            }
        }
    }

    @Test("Lookup by ID returns the matching entry; unknown ID returns nil")
    func lookupByID() {
        let v3 = ModelCatalog.entry(for: TranscriptionModelID(rawValue: "parakeet-tdt-0.6b-v3"))
        #expect(v3?.runtime == .fluidAudio)
        let unknown = ModelCatalog.entry(for: TranscriptionModelID(rawValue: "does-not-exist"))
        #expect(unknown == nil)
    }

    // MARK: Entry-specific contracts the runtime layer depends on

    @Test("Default model is Parakeet v3 (Slice 0a decision)")
    func defaultModelIsParakeetV3() {
        #expect(ModelCatalog.defaultModelID.rawValue == "parakeet-tdt-0.6b-v3")
        #expect(ModelCatalog.entry(for: ModelCatalog.defaultModelID) != nil)
    }

    @Test("Parakeet v3 auto-detects language and includes German + English")
    func parakeetV3Languages() throws {
        let entry = try #require(ModelCatalog.entry(for: TranscriptionModelID(rawValue: "parakeet-tdt-0.6b-v3")))
        #expect(entry.languageMode == .autoDetect)
        #expect(entry.languages.contains("de"))
        #expect(entry.languages.contains("en"))
        #expect(entry.maxUtteranceSeconds == nil)
    }

    @Test("Parakeet v2 is English-only")
    func parakeetV2IsEnglishOnly() throws {
        let entry = try #require(ModelCatalog.entry(for: TranscriptionModelID(rawValue: "parakeet-tdt-0.6b-v2")))
        #expect(entry.languages == ["en"])
    }

    @Test("Cohere requires a language hint and carries the 35s per-call cap")
    func cohereContract() throws {
        let entry = try #require(ModelCatalog.entry(for: TranscriptionModelID(rawValue: "cohere-transcribe-03-2026-int8")))
        #expect(entry.languageMode == .hintRequired)
        #expect(entry.maxUtteranceSeconds == 35)
        #expect(entry.languages.count == 14)
        #expect(entry.runtime == .fluidAudio)
    }

    @Test("WhisperKit requires a language hint for reliable short dictation")
    func whisperKitEntry() throws {
        let entry = try #require(ModelCatalog.entry(for: .whisperKit))
        #expect(entry.runtime == .whisperKit)
        #expect(entry.languageMode == .hintRequired)
        #expect(
            AppSettings.resolvedLanguageCode(preferred: "auto", for: entry.id) == "en"
        )
    }

    @Test("All FluidAudio entries carry a HuggingFace source repo")
    func fluidAudioEntriesHaveSourceRepos() {
        for entry in ModelCatalog.entries where entry.runtime == .fluidAudio {
            #expect(entry.sourceRepo?.hasPrefix("FluidInference/") == true,
                    "\(entry.id.rawValue) missing FluidInference source repo")
        }
    }

    @Test("FluidAudio descriptors exhaustively match catalog repositories")
    func fluidAudioDescriptorsMatchCatalogRepositories() throws {
        let catalogEntries = ModelCatalog.entries.filter { $0.runtime == .fluidAudio }
        #expect(FluidAudioModelDescriptor.all.map(\.modelID) == catalogEntries.map(\.id))

        for entry in catalogEntries {
            let descriptor = try #require(FluidAudioModelDescriptor.descriptor(for: entry.id))
            #expect(descriptor.repo.remotePath == entry.sourceRepo)
        }
    }

    @Test("FluidAudio descriptors declare the exact repository and engine")
    func fluidAudioDescriptorsDeclareExactRouting() throws {
        let expected: [(TranscriptionModelID, Repo, FluidAudioEngine)] = [
            (TranscriptionModelID(rawValue: "parakeet-tdt-0.6b-v3"), .parakeetV3, .parakeetV3),
            (TranscriptionModelID(rawValue: "parakeet-tdt-0.6b-v2"), .parakeetV2, .parakeetV2),
            (
                TranscriptionModelID(rawValue: "cohere-transcribe-03-2026-int8"),
                .cohereTranscribeCoreml,
                .cohere
            ),
        ]

        for (modelID, repo, engine) in expected {
            let descriptor = try #require(FluidAudioModelDescriptor.descriptor(for: modelID))
            #expect(descriptor.repo == repo)
            #expect(descriptor.engine == engine)
        }
    }

    @Test("Unknown models have no FluidAudio descriptor")
    func unknownModelHasNoFluidAudioDescriptor() {
        let unknown = TranscriptionModelID(rawValue: "does-not-exist")
        #expect(FluidAudioModelDescriptor.descriptor(for: unknown) == nil)
    }
}
