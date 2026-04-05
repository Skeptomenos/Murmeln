import Testing
@preconcurrency import WhisperKit
@testable import mrml

@Suite("WhisperKit VAD Chunk Diagnostics Tests")
struct WhisperKitVADChunkDiagnosticsTests {
    @MainActor
    @Test("Chunk summary reports real boundaries and tail gap")
    func chunkSummaryReportsBoundariesAndTailGap() {
        let chunks = [
            AudioChunk(seekOffsetIndex: 0, audioSamples: Array(repeating: 0, count: 3_000)),
            AudioChunk(seekOffsetIndex: 4_000, audioSamples: Array(repeating: 0, count: 2_000))
        ]

        let diagnostics = WhisperKitService.summarizeVADChunks(
            chunks,
            audioDurationMs: 65_000,
            maxChunkLengthSamples: 3_000,
            sampleRate: 100,
            logBoundaryLimit: 8
        )

        #expect(diagnostics.chunkCount == 2)
        #expect(diagnostics.boundaries == [
            WhisperKitVADChunkBoundary(startMs: 0, endMs: 30_000),
            WhisperKitVADChunkBoundary(startMs: 40_000, endMs: 60_000)
        ])
        #expect(diagnostics.totalCoveredAudioMs == 50_000)
        #expect(diagnostics.leadingGapMs == 0)
        #expect(diagnostics.tailGapMs == 5_000)
        #expect(diagnostics.longestChunkMs == 30_000)
        #expect(diagnostics.shortestChunkMs == 20_000)
        #expect(diagnostics.maxChunkLengthMs == 30_000)
        #expect(diagnostics.diagnosticsMetadata["chunk_boundaries_ms"] == "0-30000;40000-60000")
    }
}
