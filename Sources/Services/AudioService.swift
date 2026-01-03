import Foundation
import AVFoundation

actor AudioRecorder {
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var tempFileURL: URL?
    private var levelContinuation: AsyncStream<Float>.Continuation?
    private var converter: AVAudioConverter?
    
    enum AudioError: Error, LocalizedError {
        case noInput
        case formatError
        case converterError
        case engineStartFailed(Error)
        
        var errorDescription: String? {
            switch self {
            case .noInput: return "No audio input available. Check microphone permissions."
            case .formatError: return "Audio format error."
            case .converterError: return "Audio converter error."
            case .engineStartFailed(let error): return "Audio engine failed: \(error.localizedDescription)"
            }
        }
    }
    
    struct AudioQuality {
        let sampleRate: Double
        let label: String
        
        static let optimized = AudioQuality(sampleRate: 16000, label: "16kHz")
        static let high = AudioQuality(sampleRate: 44100, label: "44.1kHz")
    }
    
    func startRecording(highQuality: Bool = false) async throws -> AsyncStream<Float> {
        let engine = AVAudioEngine()
        let node = engine.inputNode
        let inputFormat = node.inputFormat(forBus: 0)
        
        guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0 else {
            throw AudioError.noInput
        }
        
        let quality: AudioQuality = highQuality ? .high : .optimized
        let targetSampleRate = quality.sampleRate
        
        let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        )!
        
        let tapFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: inputFormat.sampleRate,
            channels: 1,
            interleaved: false
        )!
        
        let needsConversion = inputFormat.sampleRate != targetSampleRate
        var audioConverter: AVAudioConverter?
        
        if needsConversion {
            guard let converter = AVAudioConverter(from: tapFormat, to: outputFormat) else {
                throw AudioError.converterError
            }
            audioConverter = converter
            self.converter = converter
        }
        
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("recording_\(UUID().uuidString).wav")
        
        let file = try AVAudioFile(forWriting: fileURL, settings: outputFormat.settings)
        
        self.audioEngine = engine
        self.audioFile = file
        self.tempFileURL = fileURL
        
        let stream = AsyncStream<Float> { continuation in
            self.levelContinuation = continuation
        }
        
        node.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { [weak self] buffer, _ in
            guard let self else { return }
            
            let level = Self.calculateRMS(buffer: buffer)
            
            if let converter = audioConverter {
                let ratio = targetSampleRate / inputFormat.sampleRate
                let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
                
                guard let outputBuffer = AVAudioPCMBuffer(
                    pcmFormat: outputFormat,
                    frameCapacity: outputFrameCount
                ) else { return }
                
                var error: NSError?
                var hasData = true
                
                converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                    if hasData {
                        hasData = false
                        outStatus.pointee = .haveData
                        return buffer
                    }
                    outStatus.pointee = .noDataNow
                    return nil
                }
                
                if error == nil && outputBuffer.frameLength > 0 {
                    try? file.write(from: outputBuffer)
                }
            } else {
                try? file.write(from: buffer)
            }
            
            Task {
                await self.sendLevel(level)
            }
        }
        
        engine.prepare()
        
        do {
            try engine.start()
        } catch {
            throw AudioError.engineStartFailed(error)
        }
        
        return stream
    }
    
    private func sendLevel(_ level: Float) {
        levelContinuation?.yield(level)
    }
    
    nonisolated private static func calculateRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<frameLength {
            sum += channelData[i] * channelData[i]
        }
        return sqrt(sum / Float(frameLength))
    }
    
    func stopRecording() -> URL? {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        levelContinuation?.finish()
        
        let url = tempFileURL
        
        audioEngine = nil
        audioFile = nil
        tempFileURL = nil
        levelContinuation = nil
        converter = nil
        
        return url
    }
}
