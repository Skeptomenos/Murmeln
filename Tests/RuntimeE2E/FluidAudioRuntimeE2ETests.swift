import Foundation
import Testing
@testable import mrml

/// Tier 1.5 gate (validate-e2e.sh): real-model end-to-end tests. Downloads
/// (or reuses) actual FluidAudio models and transcribes the real fixture
/// corpus supplied through MURMELN_E2E_FIXTURES_DIR. In the private monorepo,
/// the default corpus lives below _planning/ so the public split cannot expose
/// the project owner's voice. Excluded from Tier 1 via the MURMELN_E2E env
/// gate — multi-GB downloads must not gate every checkbox.
///
/// Fixture corpus is user-dictated (Slice 0b); until those clips land, the
/// suite fails with a clear message listing what is missing.
@MainActor
@Suite(
    "FluidAudio Runtime E2E",
    .enabled(if: ProcessInfo.processInfo.environment["MURMELN_E2E"] == "1")
)
struct FluidAudioRuntimeE2ETests {

    private static var fixturesDir: URL {
        if let configured = ProcessInfo.processInfo.environment["MURMELN_E2E_FIXTURES_DIR"],
           !configured.isEmpty
        {
            return URL(fileURLWithPath: configured, isDirectory: true)
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("_planning/artifacts/phase-8/audio-fixtures", isDirectory: true)
    }

    private func fixture(_ name: String) throws -> (audio: URL, reference: String) {
        let audio = Self.fixturesDir.appendingPathComponent("\(name).wav")
        let text = Self.fixturesDir.appendingPathComponent("\(name).txt")
        guard FileManager.default.fileExists(atPath: audio.path) else {
            throw E2EError.missingFixture(
                "\(name).wav in \(Self.fixturesDir.path) — set MURMELN_E2E_FIXTURES_DIR to a private corpus"
            )
        }
        let reference = try String(contentsOf: text, encoding: .utf8)
            .components(separatedBy: "#")[0]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (audio, reference)
    }

    /// Keyword-hit assertion: at least 60% of the reference's significant
    /// words (4+ chars) must appear in the transcript. Deliberately loose —
    /// this is an integration proof, not a WER benchmark (that's the probe).
    private func assertKeywordCoverage(_ transcript: String, reference: String, label: String) {
        let significant = reference.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 4 }
        guard !significant.isEmpty else { return }
        let haystack = transcript.lowercased()
        let hits = significant.filter { haystack.contains($0) }
        let coverage = Double(hits.count) / Double(significant.count)
        #expect(
            coverage >= 0.6,
            "\(label): keyword coverage \(String(format: "%.0f", coverage * 100))% < 60%. transcript='\(transcript)' reference='\(reference)'"
        )
    }

    /// Whole-file coverage can pass while the last phrase is absent. Keep a
    /// separate end-of-utterance assertion for the reported release-boundary
    /// regression without exposing private fixture text in failure output.
    private func assertFinalReferenceWordsPreserved(
        _ transcript: String,
        reference: String,
        label: String
    ) {
        let significant = reference.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 4 }
        let expectedTail = Array(significant.suffix(2))
        let transcriptWords = transcript.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 4 }
        let searchStart = max(0, transcriptWords.count - 4)
        let candidateStarts: ClosedRange<Int>? = transcriptWords.count >= expectedTail.count
            ? searchStart...(transcriptWords.count - expectedTail.count)
            : nil
        let tailIsPresent = candidateStarts?.contains { start in
            Array(transcriptWords[start..<(start + expectedTail.count)]) == expectedTail
        } ?? false

        #expect(
            !expectedTail.isEmpty && tailIsPresent,
            "\(label): final reference phrase is absent from the transcript tail"
        )
    }

    /// The whole-file coverage check is intentionally loose, but it must not
    /// allow an entire chunk-boundary span to disappear. These distinctive
    /// words surround the seam that was truncated during Tier 2 dogfood.
    private func assertLongFormBoundaryPreserved(_ transcript: String) {
        let haystack = transcript.lowercased()
        let boundaryWords = ["milliseconds", "result", "pasted", "cursor"]
        let missing = boundaryWords.filter { !haystack.contains($0) }
        #expect(
            missing.isEmpty,
            "cohere/long_en: chunk-boundary content missing \(missing). transcript='\(transcript)'"
        )
    }

    @Test("Parakeet v3 transcribes the English fixture")
    func parakeetV3English() async throws {
        let clip = try fixture("short_en")
        let runtime = FluidAudioRuntime()
        try await runtime.load(TranscriptionModelID(rawValue: "parakeet-tdt-0.6b-v3"))
        let text = try await runtime.transcribe(audioURL: clip.audio, options: TranscriptionOptions())
        #expect(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        assertKeywordCoverage(text, reference: clip.reference, label: "parakeet-v3/short_en")
        assertFinalReferenceWordsPreserved(text, reference: clip.reference, label: "parakeet-v3/short_en")
    }

    @Test("Parakeet v3 transcribes the German fixture")
    func parakeetV3German() async throws {
        let clip = try fixture("short_de")
        let runtime = FluidAudioRuntime()
        try await runtime.load(TranscriptionModelID(rawValue: "parakeet-tdt-0.6b-v3"))
        let text = try await runtime.transcribe(audioURL: clip.audio, options: TranscriptionOptions())
        assertKeywordCoverage(text, reference: clip.reference, label: "parakeet-v3/short_de")
        assertFinalReferenceWordsPreserved(text, reference: clip.reference, label: "parakeet-v3/short_de")
    }

    @Test("Parakeet v2 transcribes the English fixture")
    func parakeetV2English() async throws {
        let clip = try fixture("short_en")
        let runtime = FluidAudioRuntime()
        try await runtime.load(TranscriptionModelID(rawValue: "parakeet-tdt-0.6b-v2"))
        let text = try await runtime.transcribe(audioURL: clip.audio, options: TranscriptionOptions())
        assertKeywordCoverage(text, reference: clip.reference, label: "parakeet-v2/short_en")
    }

    @Test("Cohere INT8 transcribes DE + EN and handles the >35s long fixture")
    func cohereAllPaths() async throws {
        let en = try fixture("short_en")
        let de = try fixture("short_de")
        let long = try fixture("long_en")

        let runtime = FluidAudioRuntime()
        try await runtime.load(TranscriptionModelID(rawValue: "cohere-transcribe-03-2026-int8"))

        let enText = try await runtime.transcribe(
            audioURL: en.audio, options: TranscriptionOptions(languageCode: "en"))
        assertKeywordCoverage(enText, reference: en.reference, label: "cohere/short_en")

        let deText = try await runtime.transcribe(
            audioURL: de.audio, options: TranscriptionOptions(languageCode: "de"))
        assertKeywordCoverage(deText, reference: de.reference, label: "cohere/short_de")

        // >35s: exercises Murmeln's locally owned long-form chunk/stitch path.
        let longText = try await runtime.transcribe(
            audioURL: long.audio, options: TranscriptionOptions(languageCode: "en"))
        assertKeywordCoverage(longText, reference: long.reference, label: "cohere/long_en")
        assertLongFormBoundaryPreserved(longText)
    }

    @Test("Cohere preserves the Tier 2 chunk-boundary regression span")
    func cohereBoundaryRegression() async throws {
        let clip = try fixture("long_en_boundary_repro")
        let runtime = FluidAudioRuntime()
        try await runtime.load(TranscriptionModelID(rawValue: "cohere-transcribe-03-2026-int8"))

        let text = try await runtime.transcribe(
            audioURL: clip.audio, options: TranscriptionOptions(languageCode: "en"))

        assertKeywordCoverage(text, reference: clip.reference, label: "cohere/long_en_boundary_repro")
        assertLongFormBoundaryPreserved(text)
    }

    @Test("WhisperKit and FluidAudio coexist in one process")
    func runtimesCoexist() async throws {
        // Plan assumption check: no GPU/ANE contention at one-at-a-time usage.
        // FluidAudio first, then WhisperKit through its existing service.
        let clip = try fixture("short_en")
        let fluid = FluidAudioRuntime()
        try await fluid.load(TranscriptionModelID(rawValue: "parakeet-tdt-0.6b-v3"))
        let fluidText = try await fluid.transcribe(audioURL: clip.audio, options: TranscriptionOptions())
        #expect(!fluidText.isEmpty)
        fluid.unload()

        let whisper = WhisperKitService.shared
        // WhisperKit model download is its own heavyweight path. Tier 1.5 must
        // exercise the actual coexistence boundary, so an absent selected
        // variant is a gate failure rather than an acknowledged pass.
        let variant = ProcessInfo.processInfo.environment["MURMELN_E2E_WHISPERKIT_VARIANT"]
            ?? AppSettings.shared.whisperKitModel
        let shouldProvision = ProcessInfo.processInfo.environment["MURMELN_E2E_PROVISION_WHISPERKIT"] == "1"
        if !whisper.isModelDownloaded(variant), shouldProvision {
            _ = try await whisper.downloadModel(variant)
        }
        let message: Comment = "WhisperKit variant '\(variant)' is required for Tier 1.5 coexistence. Download it in the production-context model store before running validate-e2e.sh."
        try #require(whisper.isModelDownloaded(variant), message)
        try await whisper.loadModel(variant)
        let wkText = try await whisper.transcribe(audioURL: clip.audio)
        #expect(!wkText.isEmpty)
    }
}

private enum E2EError: Error, CustomStringConvertible {
    case missingFixture(String)
    var description: String {
        switch self {
        case .missingFixture(let what): return "Missing E2E fixture: \(what)"
        }
    }
}
