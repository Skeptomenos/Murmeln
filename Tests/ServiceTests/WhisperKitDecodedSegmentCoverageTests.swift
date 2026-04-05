import Testing
@preconcurrency import WhisperKit
@testable import mrml

@Suite("WhisperKit Decoded Segment Coverage Tests")
struct WhisperKitDecodedSegmentCoverageTests {
    @MainActor
    @Test("Segment coverage reports decoded tail gap against processed audio")
    func segmentCoverageReportsTailGap() {
        let segments = [
            TranscriptionSegment(start: 0.0, end: 4.25, text: "first"),
            TranscriptionSegment(start: 4.40, end: 8.90, text: "second")
        ]

        let diagnostics = WhisperKitService.summarizeDecodedSegmentCoverage(
            segments,
            processedAudioDurationMs: 10_000,
            logBoundaryLimit: 8
        )

        #expect(diagnostics.segmentCount == 2)
        #expect(diagnostics.nonEmptySegmentCount == 2)
        #expect(diagnostics.firstSegmentStartMs == 0)
        #expect(diagnostics.lastSegmentStartMs == 4_400)
        #expect(diagnostics.lastSegmentEndMs == 8_900)
        #expect(diagnostics.maxSegmentEndMs == 8_900)
        #expect(diagnostics.decodedTailGapMs == 1_100)
        #expect(diagnostics.boundaries == [
            WhisperKitVADChunkBoundary(startMs: 0, endMs: 4_250),
            WhisperKitVADChunkBoundary(startMs: 4_400, endMs: 8_900)
        ])
        #expect(diagnostics.diagnosticsMetadata["segment_boundaries_ms"] == "0-4250;4400-8900")
    }
}
