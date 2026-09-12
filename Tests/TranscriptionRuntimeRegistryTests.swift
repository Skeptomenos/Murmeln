import Testing
@testable import mrml

@MainActor
@Suite("Transcription Runtime Registry Tests")
struct TranscriptionRuntimeRegistryTests {
    @Test("Every runtime ID resolves to its single injected instance")
    func runtimeIDsResolveToInjectedIdentity() {
        let fluidAudio = MockRuntime(id: .fluidAudio)
        let whisperKit = MockRuntime(id: .whisperKit)
        let registry = makeRegistry(fluidAudio: fluidAudio, whisperKit: whisperKit)

        let resolved = RuntimeID.allCases.map { runtimeID in
            let runtime = registry.runtime(for: runtimeID)
            #expect(runtime.id == runtimeID)
            return ObjectIdentifier(runtime)
        }
        #expect(Set(resolved).count == RuntimeID.allCases.count)
        #expect(registry.runtime(for: RuntimeID.fluidAudio) === fluidAudio)
        #expect(registry.runtime(for: RuntimeID.whisperKit) === whisperKit)
        #expect(
            registry.runtime(for: RuntimeID.fluidAudio)
                === registry.runtime(for: RuntimeID.fluidAudio)
        )
        #expect(
            registry.runtime(for: RuntimeID.whisperKit)
                === registry.runtime(for: RuntimeID.whisperKit)
        )
    }

    @Test("Every catalog entry resolves through its declared runtime")
    func catalogEntriesResolveToDeclaredRuntime() {
        let fluidAudio = MockRuntime(id: .fluidAudio)
        let whisperKit = MockRuntime(id: .whisperKit)
        let registry = makeRegistry(fluidAudio: fluidAudio, whisperKit: whisperKit)

        for entry in ModelCatalog.entries {
            let declaredRuntime = registry.runtime(for: entry.runtime)
            #expect(registry.runtime(forModel: entry.id) === declaredRuntime)
        }

        #expect(registry.runtime(forModel: TranscriptionModelID(rawValue: "unknown")) == nil)
    }

    @Test("Catalog settings resolves the exact registry runtime")
    func catalogSettingsUsesInjectedRuntime() throws {
        let fluidAudio = MockRuntime(id: .fluidAudio)
        let whisperKit = MockRuntime(id: .whisperKit)
        let registry = makeRegistry(fluidAudio: fluidAudio, whisperKit: whisperKit)
        let fluidEntry = try #require(ModelCatalog.entry(for: ModelCatalog.defaultModelID))
        let whisperEntry = try #require(ModelCatalog.entry(for: .whisperKit))

        #expect(CatalogModelSection.resolveRuntime(for: fluidEntry, in: registry) === fluidAudio)
        #expect(CatalogModelSection.resolveRuntime(for: whisperEntry, in: registry) === whisperKit)
    }

    private func makeRegistry(
        fluidAudio: MockRuntime,
        whisperKit: MockRuntime
    ) -> TranscriptionRuntimeRegistry {
        TranscriptionRuntimeRegistry(runtimes: [
            .fluidAudio: fluidAudio,
            .whisperKit: whisperKit,
        ])
    }
}
