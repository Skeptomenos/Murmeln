import Testing
import Foundation
@preconcurrency import AVFoundation
@testable import mrml

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
