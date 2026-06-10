import Testing
import Foundation
@preconcurrency import AVFoundation
@testable import mrml

@Suite("TapState Concurrency Tests")
struct TapStateConcurrencyTests {

    private static func makeBuffer(format: AVAudioFormat, frames: AVAudioFrameCount) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        return buffer
    }

    /// H1 regression: hammers TapState from a fake render thread (appending
    /// pre-roll buffers / writing) while a second thread runs begin/stop
    /// capture cycles — the exact two-party access pattern of the production
    /// tap callback vs. the AudioRecorder actor. Run under Thread Sanitizer
    /// this fails if any TapState access bypasses the lock.
    @Test("Rapid begin/stop cycles against a concurrent buffer source keep state consistent")
    func rapidBeginStopCyclesKeepStateConsistent() async throws {
        let tapState = AudioRecorder.TapState()
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tapstate-stress-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let file = try AVAudioFile(forWriting: fileURL, settings: format.settings)

        tapState.withLock { state in
            state.outputFormat = format
            state.preRollMaxFrames = 4_096
        }

        let iterations = 2_000

        // Fake render thread: mimics the tap callback body.
        let tapThread = Thread {
            for _ in 0..<iterations {
                let buffer = Self.makeBuffer(format: format, frames: 256)
                tapState.withLock { state in
                    state.lastBufferTime = Date()
                    if state.isWriting, let file = state.audioFile {
                        if state.pendingPreRollFlush {
                            _ = try? AudioRecorder.flushPreRollBuffers(
                                to: file,
                                buffers: &state.preRollBuffers,
                                totalFrames: &state.preRollFrameCount,
                                pendingFlush: &state.pendingPreRollFlush
                            )
                        }
                        try? file.write(from: buffer)
                    } else {
                        AudioRecorder.appendPreRollBuffer(
                            buffer,
                            to: &state.preRollBuffers,
                            totalFrames: &state.preRollFrameCount,
                            maxFrames: state.preRollMaxFrames
                        )
                    }
                }
            }
        }

        // Fake actor thread: mimics beginCapture/stopRecording cycles.
        let controlThread = Thread {
            for cycle in 0..<(iterations / 20) {
                tapState.withLock { state in
                    state.audioFile = file
                    _ = (try? AudioRecorder.flushPreRollBuffers(
                        to: file,
                        buffers: &state.preRollBuffers,
                        totalFrames: &state.preRollFrameCount,
                        pendingFlush: &state.pendingPreRollFlush
                    )) ?? 0
                    state.pendingPreRollFlush = true
                    state.isWriting = true
                    state.captureStartedAtNs = UInt64(cycle)
                }
                tapState.withLock { state in
                    state.isWriting = false
                    _ = (try? AudioRecorder.flushPreRollBuffers(
                        to: file,
                        buffers: &state.preRollBuffers,
                        totalFrames: &state.preRollFrameCount,
                        pendingFlush: &state.pendingPreRollFlush
                    )) ?? 0
                    state.audioFile = nil
                }
            }
        }

        tapThread.start()
        controlThread.start()

        let deadline = Date().addingTimeInterval(30)
        while (!tapThread.isFinished || !controlThread.isFinished) && Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(tapThread.isFinished && controlThread.isFinished)

        // Frame accounting must be internally consistent after the storm.
        let (bufferedFrames, countedFrames) = tapState.withLock { state in
            (state.preRollBuffers.reduce(0) { $0 + Int($1.frameLength) }, state.preRollFrameCount)
        }
        #expect(bufferedFrames == countedFrames)
        #expect(bufferedFrames <= 4_096)
    }
}

@Suite("AudioService Tests")
struct AudioServiceTests {
    @Test("Converter flush emits trailing frames")
    func converterFlushEmitsTrailingFrames() {
        let inputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)!
        let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        let totalInputFrames = 48_000
        let chunkSize = 1024
        let expectedOutputFrames = Int(Double(totalInputFrames) * (outputFormat.sampleRate / inputFormat.sampleRate))

        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            Issue.record("Failed to create AVAudioConverter")
            return
        }

        var producedWithoutFlush = 0
        var currentFrame = 0

        while currentFrame < totalInputFrames {
            let frameCount = min(chunkSize, totalInputFrames - currentFrame)
            let inputBuffer = makeSineBuffer(
                format: inputFormat,
                startFrame: currentFrame,
                frameCount: frameCount,
                frequency: 440
            )
            currentFrame += frameCount

            let ratio = outputFormat.sampleRate / inputFormat.sampleRate
            let outputFrameCount = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio)
            let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: max(outputFrameCount, 1)
            )!

            var conversionError: NSError?
            final class InputState: @unchecked Sendable {
                var hasData = true
            }
            let inputState = InputState()

            converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
                if inputState.hasData {
                    inputState.hasData = false
                    outStatus.pointee = .haveData
                    return inputBuffer
                }

                outStatus.pointee = .noDataNow
                return nil
            }

            #expect(conversionError == nil)
            producedWithoutFlush += Int(outputBuffer.frameLength)
        }

        var flushedViaCallback = 0
        let flushedFrames = AudioRecorder.flushConverter(converter, outputFormat: outputFormat) { buffer in
            flushedViaCallback += Int(buffer.frameLength)
        }

        let totalProduced = producedWithoutFlush + flushedFrames

        #expect(flushedFrames > 0)
        #expect(flushedFrames == flushedViaCallback)
        #expect(producedWithoutFlush < expectedOutputFrames)
        #expect(totalProduced == expectedOutputFrames)
    }

    @Test("Converter flush is zero when no pending data")
    func converterFlushIsZeroWithoutPendingData() {
        let inputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)!
        let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            Issue.record("Failed to create AVAudioConverter")
            return
        }

        let flushedFrames = AudioRecorder.flushConverter(converter, outputFormat: outputFormat) { _ in }
        #expect(flushedFrames == 0)
    }

    @Test("Pre-roll buffer keeps latest frames within cap")
    func preRollBufferKeepsLatestFramesWithinCap() {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

        var buffers: [AVAudioPCMBuffer] = []
        var totalFrames = 0
        let maxFrames = 500

        AudioRecorder.appendPreRollBuffer(
            makeConstantBuffer(format: format, frameCount: 220, value: 0.1),
            to: &buffers,
            totalFrames: &totalFrames,
            maxFrames: maxFrames
        )
        AudioRecorder.appendPreRollBuffer(
            makeConstantBuffer(format: format, frameCount: 220, value: 0.2),
            to: &buffers,
            totalFrames: &totalFrames,
            maxFrames: maxFrames
        )
        AudioRecorder.appendPreRollBuffer(
            makeConstantBuffer(format: format, frameCount: 220, value: 0.3),
            to: &buffers,
            totalFrames: &totalFrames,
            maxFrames: maxFrames
        )

        #expect(totalFrames <= maxFrames)
        #expect(buffers.count == 2)
        #expect(totalFrames == 440)

        let firstRemaining = buffers[0].floatChannelData![0][0]
        let secondRemaining = buffers[1].floatChannelData![0][0]
        #expect(abs(firstRemaining - 0.2) < 0.0001)
        #expect(abs(secondRemaining - 0.3) < 0.0001)
    }

    @Test("Buffer copy preserves audio samples")
    func bufferCopyPreservesAudioSamples() {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        let original = makeSineBuffer(format: format, startFrame: 0, frameCount: 256, frequency: 440)

        guard let copied = AudioRecorder.copyBuffer(original) else {
            Issue.record("copyBuffer returned nil")
            return
        }

        #expect(copied.frameLength == original.frameLength)

        let originalData = original.floatChannelData![0]
        let copiedData = copied.floatChannelData![0]
        #expect(abs(originalData[0] - copiedData[0]) < 0.0001)
        #expect(abs(originalData[64] - copiedData[64]) < 0.0001)
        #expect(abs(originalData[128] - copiedData[128]) < 0.0001)
    }

    @Test("Pre-roll flush writes buffered audio without post-threshold callback")
    func preRollFlushWritesBufferedAudioWithoutPostThresholdCallback() throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("audio-preroll-flush-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var buffers = [
            makeConstantBuffer(format: format, frameCount: 160, value: 0.1),
            makeConstantBuffer(format: format, frameCount: 160, value: 0.2)
        ]
        var totalFrames = 320
        var pendingFlush = true

        do {
            let file = try AVAudioFile(forWriting: fileURL, settings: format.settings)
            let flushedFrames = try AudioRecorder.flushPreRollBuffers(
                to: file,
                buffers: &buffers,
                totalFrames: &totalFrames,
                pendingFlush: &pendingFlush
            )

            #expect(flushedFrames == 320)
            #expect(buffers.isEmpty)
            #expect(totalFrames == 0)
            #expect(pendingFlush == false)
            #expect(Int(file.framePosition) == 320)
        }

        let writtenFile = try AVAudioFile(forReading: fileURL)
        #expect(Int(writtenFile.length) == 320)
    }

    private func makeSineBuffer(
        format: AVAudioFormat,
        startFrame: Int,
        frameCount: Int,
        frequency: Float
    ) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)

        let sampleRate = Float(format.sampleRate)
        let channelData = buffer.floatChannelData![0]

        for i in 0..<frameCount {
            let t = Float(startFrame + i) / sampleRate
            channelData[i] = sin(2 * .pi * frequency * t)
        }

        return buffer
    }

    private func makeConstantBuffer(
        format: AVAudioFormat,
        frameCount: Int,
        value: Float
    ) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)

        let channelData = buffer.floatChannelData![0]
        for i in 0..<frameCount {
            channelData[i] = value
        }

        return buffer
    }
}
