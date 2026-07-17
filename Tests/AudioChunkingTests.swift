import Testing
@testable import mrml

/// Phase 8 long-utterance contract for capped models (Cohere: 35 s), including
/// Murmeln's locally owned overlap and transcript stitching regression seam.
@Suite("Audio Chunking Route Tests")
struct AudioChunkingTests {

    @Test("Audio within the cap routes to the single-call path")
    func withinCapRoutesSingleCall() {
        #expect(AudioChunkingRoute.route(durationSeconds: 10, maxUtteranceSeconds: 35) == .singleCall)
        #expect(AudioChunkingRoute.route(durationSeconds: 35, maxUtteranceSeconds: 35) == .singleCall)
    }

    @Test("Audio beyond the cap routes to the long-form path")
    func beyondCapRoutesLongForm() {
        #expect(AudioChunkingRoute.route(durationSeconds: 35.01, maxUtteranceSeconds: 35) == .longForm)
        #expect(AudioChunkingRoute.route(durationSeconds: 120, maxUtteranceSeconds: 35) == .longForm)
    }

    @Test("Uncapped models always take the single-call path")
    func uncappedAlwaysSingleCall() {
        #expect(AudioChunkingRoute.route(durationSeconds: 3_600, maxUtteranceSeconds: nil) == .singleCall)
    }

    @Test("Zero and negative durations are single-call (defensive)")
    func degenerateDurations() {
        #expect(AudioChunkingRoute.route(durationSeconds: 0, maxUtteranceSeconds: 35) == .singleCall)
        #expect(AudioChunkingRoute.route(durationSeconds: -1, maxUtteranceSeconds: 35) == .singleCall)
    }

    @Test("Catalog cap wires through: Cohere routes long, Parakeet never does")
    func catalogCapsRoute() throws {
        let cohere = try #require(ModelCatalog.entry(for: TranscriptionModelID(rawValue: "cohere-transcribe-03-2026-int8")))
        let parakeet = try #require(ModelCatalog.entry(for: TranscriptionModelID(rawValue: "parakeet-tdt-0.6b-v3")))

        #expect(AudioChunkingRoute.route(durationSeconds: 45, maxUtteranceSeconds: cohere.maxUtteranceSeconds.map(Double.init)) == .longForm)
        #expect(AudioChunkingRoute.route(durationSeconds: 45, maxUtteranceSeconds: parakeet.maxUtteranceSeconds.map(Double.init)) == .singleCall)
    }

    @MainActor
    @Test("FluidAudio derives the Cohere chunk cap from the catalog")
    func fluidAudioUsesCatalogCap() {
        let cohereID = TranscriptionModelID(rawValue: "cohere-transcribe-03-2026-int8")
        #expect(FluidAudioRuntime.maxUtteranceSeconds(for: cohereID) == 35)
    }

    @Test("Cohere long form uses a ten-second overlap for the Tier 2 seam")
    func cohereLongFormRangesUseTenSecondOverlap() {
        let ranges = CohereLongFormChunking.ranges(
            sampleCount: 747_200,
            sampleRate: 16_000,
            maxChunkSeconds: 35
        )

        #expect(ranges == [0..<560_000, 400_000..<747_200])
    }

    @Test("Cohere stitcher preserves the captured chunk-boundary phrase")
    func cohereStitcherPreservesBoundaryPhrase() {
        let prefix = "The model converts the audio into text within a few hundred"
        let suffix = "Converts the audio into text within a few hundred milliseconds, and the result is then pasted directly at your cursor position."

        let merged = CohereLongFormChunking.merge(prefix: prefix, suffix: suffix)

        #expect(merged == "The model converts the audio into text within a few hundred milliseconds, and the result is then pasted directly at your cursor position.")
    }

    @Test("Cohere stitcher concatenates when no confident overlap exists")
    func cohereStitcherFallsBackWithoutDroppingContent() {
        #expect(
            CohereLongFormChunking.merge(prefix: "alpha beta", suffix: "gamma delta")
                == "alpha beta gamma delta"
        )
    }
}
