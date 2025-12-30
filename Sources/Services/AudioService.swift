import Foundation
import AVFoundation

actor AudioRecorder {
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var tempFileURL: URL?
    private var levelContinuation: AsyncStream<Float>.Continuation?
    
    enum AudioError: Error, LocalizedError {
        case noInput
        case formatError
        case engineStartFailed(Error)
        
        var errorDescription: String? {
            switch self {
            case .noInput: return "No audio input available. Check microphone permissions."
            case .formatError: return "Audio format error."
            case .engineStartFailed(let error): return "Audio engine failed: \(error.localizedDescription)"
            }
        }
    }
    
    func startRecording() async throws -> AsyncStream<Float> {
        let engine = AVAudioEngine()
        let node = engine.inputNode
        let inputFormat = node.inputFormat(forBus: 0)
        
        guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0 else {
            throw AudioError.noInput
        }
        
        let recordingFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: inputFormat.sampleRate,
            channels: 1,
            interleaved: false
        )!
        
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("recording_\(UUID().uuidString).wav")
        
        let file = try AVAudioFile(forWriting: fileURL, settings: recordingFormat.settings)
        
        self.audioEngine = engine
        self.audioFile = file
        self.tempFileURL = fileURL
        
        let stream = AsyncStream<Float> { continuation in
            self.levelContinuation = continuation
        }
        
        node.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
            guard let self else { return }
            
            try? file.write(from: buffer)
            
            let level = Self.calculateRMS(buffer: buffer)
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
        
        return url
    }
}
