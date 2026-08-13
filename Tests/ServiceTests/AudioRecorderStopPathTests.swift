import Foundation
import Testing
@preconcurrency import AVFoundation
@testable import mrml

@Suite("AudioRecorder Stop Path Tests", .serialized)
struct AudioRecorderStopPathTests {
    @Test("Immediate release preserves a final buffer delivered during stop grace")
    func immediateReleasePreservesFinalBufferedAudio() async throws {
        let inputSampleRate = 48_000.0
        let outputSampleRate = 16_000.0
        let framesPerBuffer = 1_024
        let leadingBufferCount = 3
        let totalInputFrames = framesPerBuffer * (leadingBufferCount + 1)
        let expectedOutputFrames = Int(
            (Double(totalInputFrames) * outputSampleRate / inputSampleRate).rounded()
        )

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("audio-stop-tail-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let stopGraceGate = StopGraceGate()
        let recorder = AudioRecorder { duration in
            await stopGraceGate.wait(duration)
        }
        try await recorder.prepareCaptureForTesting(
            inputSampleRate: inputSampleRate,
            outputSampleRate: outputSampleRate,
            fileURL: fileURL
        )

        let inputFormat = try #require(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: inputSampleRate,
            channels: 1,
            interleaved: false
        ))

        for _ in 0..<leadingBufferCount {
            recorder.processInputBufferForTesting(
                makeConstantBuffer(format: inputFormat, frameCount: framesPerBuffer, value: 0)
            )
        }

        let stopTask = Task { await recorder.stopRecording() }
        await stopGraceGate.waitUntilEntered()

        recorder.processInputBufferForTesting(
            makeConstantBuffer(format: inputFormat, frameCount: framesPerBuffer, value: 0.75)
        )
        await stopGraceGate.release()

        let recordedURL = try #require(await stopTask.value)
        let recordedFile = try AVAudioFile(forReading: recordedURL)
        let recordedFrames = Int(recordedFile.length)

        #expect(
            abs(recordedFrames - expectedOutputFrames) <= 1,
            "Expected about \(expectedOutputFrames) converted frames; recorded \(recordedFrames)"
        )

        let recordedBuffer = try #require(AVAudioPCMBuffer(
            pcmFormat: recordedFile.processingFormat,
            frameCapacity: AVAudioFrameCount(recordedFrames)
        ))
        try recordedFile.read(into: recordedBuffer)
        let samples = try #require(recordedBuffer.floatChannelData?[0])
        let tailFrameCount = min(128, Int(recordedBuffer.frameLength))
        let tailStart = Int(recordedBuffer.frameLength) - tailFrameCount
        let tailMeanSquare = (tailStart..<Int(recordedBuffer.frameLength)).reduce(Float.zero) { sum, index in
            sum + samples[index] * samples[index]
        } / Float(tailFrameCount)
        let tailRMS = sqrt(tailMeanSquare)

        #expect(
            tailRMS > 0.5,
            "Final-buffer marker is missing: tail RMS was \(tailRMS)"
        )
    }

    private func makeConstantBuffer(
        format: AVAudioFormat,
        frameCount: Int,
        value: Float
    ) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(frameCount)
        )!
        buffer.frameLength = AVAudioFrameCount(frameCount)

        let channelData = buffer.floatChannelData![0]
        for index in 0..<frameCount {
            channelData[index] = value
        }
        return buffer
    }
}

private actor StopGraceGate {
    private var entered = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func wait(_ duration: Duration) async {
        _ = duration
        entered = true
        let waiters = enteredWaiters
        enteredWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }

        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { continuation in
            enteredWaiters.append(continuation)
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}
