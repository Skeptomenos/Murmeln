import AVFoundation
import FluidAudio
import Foundation
import Testing
@testable import mrml

@MainActor
@Suite("Audio preparation measurements", .serialized, .enabled(if: ProcessInfo.processInfo.environment["MURMELN_AUDIO_BENCHMARK"] == "1"))
struct AudioPreparationPerformanceTests {
    @Test("Bounded 48 kHz short and long recordings", arguments: [5, 180])
    func measure(seconds: Int) async throws {
        let url = try makePreparationWAV(seconds: seconds)
        defer { try? FileManager.default.removeItem(at: url) }
        var preparation: [Double] = []
        var mainQueueDelay: [Double] = []
        var trimming: [Double] = []
        for _ in 0..<5 {
            let start = DispatchTime.now().uptimeNanoseconds
            let heartbeat = Task { @MainActor in DispatchTime.now().uptimeNanoseconds }
            let samples = try await FluidAudioPreparationWorker.shared.prepare(url)
            preparation.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
            mainQueueDelay.append(Double(await heartbeat.value - start) / 1e6)
            #expect(samples.count == seconds * 16_000)
            let trimStart = DispatchTime.now().uptimeNanoseconds
            let result = try #require(await AudioRecorder.trimSilence(audioURL: url))
            trimming.append(Double(DispatchTime.now().uptimeNanoseconds - trimStart) / 1e6)
            if result != url { try FileManager.default.removeItem(at: result) }
        }
        print("AUDIO_BENCH seconds=\(seconds) repeats=5 prep_ms=\(preparation.sorted()) main_queue_ms=\(mainQueueDelay.sorted()) trim_ms=\(trimming.sorted())")
    }
}

func makePreparationWAV(seconds: Int, silenceEdges: Bool = false) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("audio-prep-\(UUID()).wav")
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000)!
    buffer.frameLength = 48_000
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    for second in 0..<seconds {
        let silent = silenceEdges && (second < 2 || second >= seconds - 2)
        for frame in 0..<48_000 { buffer.floatChannelData![0][frame] = silent ? 0 : 0.25 }
        try file.write(from: buffer)
    }
    return url
}
