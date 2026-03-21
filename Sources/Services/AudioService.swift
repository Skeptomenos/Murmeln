import Foundation
@preconcurrency import AVFoundation

actor AudioRecorder {
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var tempFileURL: URL?
    private var levelContinuation: AsyncStream<Float>.Continuation?
    private var converter: AVAudioConverter?
    
    /// Thread-safe state for the audio tap callback
    private final class TapState: @unchecked Sendable {
        var isWriting = false
        var lastBufferTime = Date()
        var audioFile: AVAudioFile?
        var converter: AVAudioConverter?
        var outputFormat: AVAudioFormat?
        var inputFormat: AVAudioFormat?
    }
    
    private let tapState = TapState()
    
    // Warm-up state
    private var isWarmedUp = false
    private var cachedHighQuality = false
    private var cachedOutputFormat: AVAudioFormat?
    private var cachedTapFormat: AVAudioFormat?
    
    enum AudioError: Error, LocalizedError {
        case noInput
        case formatError
        case converterError
        case engineStartFailed(Error)
        case notWarmedUp
        
        var errorDescription: String? {
            switch self {
            case .noInput: return "No audio input available. Check microphone permissions."
            case .formatError: return "Audio format error."
            case .converterError: return "Audio converter error."
            case .engineStartFailed(let error): return "Audio engine failed: \(error.localizedDescription)"
            case .notWarmedUp: return "Audio engine not warmed up. Call prepareEngine() first."
            }
        }
    }
    
    struct AudioQuality {
        let sampleRate: Double
        let label: String
        
        static let optimized = AudioQuality(sampleRate: 16000, label: "16kHz")
        static let high = AudioQuality(sampleRate: 44100, label: "44.1kHz")
    }
    
    // MARK: - Phase 1: Warm-up (called on Fn press, before 400ms threshold)
    
    /// Prepares and starts the audio engine without recording to file.
    /// Call this during the hold threshold delay to eliminate startup latency.
    func prepareEngine(highQuality: Bool = false) async throws -> AsyncStream<Float> {
        // Clean up any previous state
        if audioEngine != nil {
            await cancelWarmUp()
        }
        
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
        
        // Cache formats for beginCapture()
        self.cachedHighQuality = highQuality
        self.cachedOutputFormat = outputFormat
        self.cachedTapFormat = tapFormat
        self.audioEngine = engine
        
        // Set up converter if needed
        let needsConversion = inputFormat.sampleRate != targetSampleRate
        if needsConversion {
            guard let converter = AVAudioConverter(from: tapFormat, to: outputFormat) else {
                throw AudioError.converterError
            }
            self.converter = converter
            tapState.converter = converter
        }
        
        tapState.isWriting = false
        tapState.lastBufferTime = Date()
        tapState.outputFormat = outputFormat
        tapState.inputFormat = inputFormat
        
        let stream = AsyncStream<Float> { continuation in
            self.levelContinuation = continuation
        }
        
        // Install a single persistent tap
        node.installTap(onBus: 0, bufferSize: 1024, format: tapFormat) { [weak self, tapState] buffer, _ in
            // Track buffer arrival time for drain detection
            tapState.lastBufferTime = Date()
            
            let level = Self.calculateRMS(buffer: buffer)
            
            // Write to file if capture is active
            if tapState.isWriting, let file = tapState.audioFile {
                if let converter = tapState.converter, let outFormat = tapState.outputFormat, let inFormat = tapState.inputFormat {
                    let ratio = outFormat.sampleRate / inFormat.sampleRate
                    let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
                    
                    if let outputBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: outputFrameCount) {
                        var error: NSError?
                        nonisolated(unsafe) var hasData = true
                        
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
                    }
                } else {
                    try? file.write(from: buffer)
                }
            }
            
            if let self {
                Task { await self.sendLevel(level) }
            }
        }
        
        engine.prepare()
        
        do {
            try engine.start()
            #if DEBUG
            print("🔥 Engine warmed up (persistent tap installed)")
            #endif
        } catch {
            throw AudioError.engineStartFailed(error)
        }
        
        isWarmedUp = true
        return stream
    }
    
    // MARK: - Phase 2: Begin Capture (called after 400ms threshold)
    
    /// Starts actual recording to file. Must call prepareEngine() first.
    func beginCapture() async throws {
        guard isWarmedUp, let outputFormat = cachedOutputFormat else {
            throw AudioError.notWarmedUp
        }
        
        // Create the output file
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("recording_\(UUID().uuidString).wav")
        
        let file = try AVAudioFile(forWriting: fileURL, settings: outputFormat.settings)
        
        self.audioFile = file
        self.tempFileURL = fileURL
        
        // Signal the tap to start writing
        tapState.audioFile = file
        tapState.isWriting = true
        
        #if DEBUG
        print("🎙️ Capture started (zero latency, no tap gap)")
        #endif
    }
    
    // MARK: - Cancel Warm-up (called if user releases before 400ms)
    
    /// Stops the warmed-up engine without saving any audio.
    func cancelWarmUp() async {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        levelContinuation?.finish()
        
        audioEngine = nil
        audioFile = nil
        tempFileURL = nil
        levelContinuation = nil
        converter = nil
        cachedOutputFormat = nil
        cachedTapFormat = nil
        isWarmedUp = false
        
        tapState.isWriting = false
        tapState.audioFile = nil
        tapState.converter = nil
        
        #if DEBUG
        print("❄️ Warm-up cancelled")
        #endif
    }
    
    // MARK: - Legacy API (for backward compatibility)
    
    func startRecording(highQuality: Bool = false) async throws -> AsyncStream<Float> {
        let stream = try await prepareEngine(highQuality: highQuality)
        try await beginCapture()
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
    
    func stopRecording() async -> URL? {
        // Wait for audio pipeline to drain (no new buffers for 300ms)
        // with a maximum timeout of 1000ms to ensure all trailing speech is captured
        let drainThreshold: TimeInterval = 0.3  // 300ms silence = drained
        let maxWait: TimeInterval = 1.0         // 1.0s max wait
        let startTime = Date()
        
        #if DEBUG
        print("⏳ Waiting for pipeline drain...")
        #endif
        
        while true {
            let lastTime = tapState.lastBufferTime
            let timeSinceLastBuffer = Date().timeIntervalSince(lastTime)
            let totalWaitTime = Date().timeIntervalSince(startTime)
            
            if timeSinceLastBuffer >= drainThreshold {
                #if DEBUG
                print("🔊 Buffer drain detected after \(String(format: "%.0f", totalWaitTime * 1000))ms")
                #endif
                break
            }
            
            if totalWaitTime >= maxWait {
                #if DEBUG
                print("⚠️ Buffer drain timeout after \(String(format: "%.0f", maxWait * 1000))ms")
                #endif
                break
            }
            
            try? await Task.sleep(for: .milliseconds(20))
        }
        
        // Stop writing first
        tapState.isWriting = false
        
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        levelContinuation?.finish()
        
        let url = tempFileURL
        
        audioEngine = nil
        audioFile = nil
        tempFileURL = nil
        levelContinuation = nil
        converter = nil
        cachedOutputFormat = nil
        cachedTapFormat = nil
        isWarmedUp = false
        
        tapState.audioFile = nil
        tapState.converter = nil
        
        return url
    }
    
    /// Trims silence from audio using chunked processing to minimize memory usage.
    static func trimSilence(audioURL: URL, threshold: Float = 0.005) async -> URL? {
        do {
            let file = try AVAudioFile(forReading: audioURL)
            let sampleRate = file.fileFormat.sampleRate
            let totalFrames = file.length
            
            guard let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: 1,
                interleaved: false
            ) else { return nil }
            
            guard totalFrames > 0 else { return nil }
            
            let chunkDuration: Double = 1.0
            let chunkSize = AVAudioFrameCount(sampleRate * chunkDuration)
            let windowSize = Int(sampleRate * 0.02)  // 20ms analysis window
            
            guard chunkSize > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkSize) else {
                return nil
            }
            
            // PASS 1: Forward scan to find start of speech
            var startFrame: AVAudioFramePosition = 0
            var foundStart = false
            file.framePosition = 0
            
            while file.framePosition < totalFrames && !foundStart {
                let chunkStartPosition = file.framePosition
                buffer.frameLength = 0
                try file.read(into: buffer)
                
                guard let channelData = buffer.floatChannelData?[0] else { continue }
                let length = Int(buffer.frameLength)
                
                for i in stride(from: 0, to: length - windowSize, by: windowSize / 2) {
                    var windowRMS: Float = 0
                    for j in 0..<windowSize {
                        let sample = channelData[i + j]
                        windowRMS += sample * sample
                    }
                    windowRMS = sqrt(windowRMS / Float(windowSize))
                    
                    if windowRMS > threshold {
                        // Found speech - add 300ms padding before (increased from 150ms)
                        let paddingFrames = AVAudioFramePosition(sampleRate * 0.3)
                        startFrame = max(0, chunkStartPosition + AVAudioFramePosition(i) - paddingFrames)
                        foundStart = true
                        break
                    }
                }
            }
            
            // PASS 2: Backward scan to find end of speech
            var endFrame: AVAudioFramePosition = totalFrames
            var foundEnd = false
            let numChunks = Int((totalFrames + AVAudioFramePosition(chunkSize) - 1) / AVAudioFramePosition(chunkSize))
            
            for chunkIndex in stride(from: numChunks - 1, through: 0, by: -1) {
                let chunkStartPosition = AVAudioFramePosition(chunkIndex) * AVAudioFramePosition(chunkSize)
                file.framePosition = chunkStartPosition
                buffer.frameLength = 0
                try file.read(into: buffer)
                
                guard let channelData = buffer.floatChannelData?[0] else { continue }
                let length = Int(buffer.frameLength)
                
                for i in stride(from: max(0, length - windowSize), through: windowSize, by: -windowSize / 2) {
                    var windowRMS: Float = 0
                    for j in 0..<windowSize {
                        let sample = channelData[i + j]
                        windowRMS += sample * sample
                    }
                    windowRMS = sqrt(windowRMS / Float(windowSize))
                    
                    if windowRMS > threshold {
                        // Found speech - add 1000ms padding after (increased from 800ms)
                        let paddingFrames = AVAudioFramePosition(sampleRate * 1.0)
                        endFrame = min(totalFrames, chunkStartPosition + AVAudioFramePosition(i + windowSize) + paddingFrames)
                        foundEnd = true
                        break
                    }
                }
                
                if foundEnd { break }
            }
            
            // Validate trim boundaries
            let trimmedFrameCount = endFrame - startFrame
            if startFrame >= endFrame || trimmedFrameCount < AVAudioFramePosition(sampleRate * 0.3) {
                #if DEBUG
                print("🔊 Trim: No significant change, using original")
                #endif
                return audioURL
            }
            
            let originalDuration = Double(totalFrames) / sampleRate
            let trimmedDuration = Double(trimmedFrameCount) / sampleRate
            let savedPercent = (1.0 - trimmedDuration / originalDuration) * 100
            
            #if DEBUG
            print("✂️ Trim: \(String(format: "%.2f", originalDuration))s → \(String(format: "%.2f", trimmedDuration))s (saved \(String(format: "%.0f", savedPercent))%)")
            #endif
            
            // PASS 3: Copy trimmed portion in chunks
            let trimmedURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("trimmed_\(UUID().uuidString).wav")
            
            let outputFile = try AVAudioFile(forWriting: trimmedURL, settings: format.settings)
            
            file.framePosition = startFrame
            var remainingFrames = trimmedFrameCount
            
            while remainingFrames > 0 {
                buffer.frameLength = 0
                try file.read(into: buffer)
                
                let framesToWrite = min(AVAudioFramePosition(buffer.frameLength), remainingFrames)
                if framesToWrite <= 0 { break }
                
                if AVAudioFramePosition(buffer.frameLength) > remainingFrames {
                    buffer.frameLength = AVAudioFrameCount(remainingFrames)
                }
                
                try outputFile.write(from: buffer)
                remainingFrames -= AVAudioFramePosition(buffer.frameLength)
            }
            
            return trimmedURL
        } catch {
            #if DEBUG
            print("⚠️ Trim failed: \(error.localizedDescription)")
            #endif
            return nil
        }
    }
    
    /// Analyzes audio for audible speech using chunked reading to minimize memory usage.
    /// Reads audio in 10-second chunks instead of loading the entire file into memory.
    static func hasAudibleSpeech(audioURL: URL, threshold: Float = 0.005) async -> Bool {
        do {
            let file = try AVAudioFile(forReading: audioURL)
            let sampleRate = file.fileFormat.sampleRate
            
            guard let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: 1,
                interleaved: false
            ) else { return true }
            
            // Use 10-second chunks to minimize memory usage
            // At 16kHz: 160,000 frames, at 44.1kHz: 441,000 frames
            let chunkDuration: Double = 10.0
            let chunkSize = AVAudioFrameCount(sampleRate * chunkDuration)
            
            guard chunkSize > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkSize) else {
                return true
            }
            
            var totalSumSquares: Float = 0
            var totalFrames: Int = 0
            var maxLevel: Float = 0
            
            // Read and analyze in chunks
            while file.framePosition < file.length {
                buffer.frameLength = 0  // Reset buffer for next read
                try file.read(into: buffer)
                
                guard let channelData = buffer.floatChannelData?[0] else { continue }
                let length = Int(buffer.frameLength)
                
                for i in 0..<length {
                    let sample = abs(channelData[i])
                    maxLevel = max(maxLevel, sample)
                    totalSumSquares += sample * sample
                }
                totalFrames += length
                
                // Early exit: if we already found speech above threshold, no need to continue
                let currentRMS = sqrt(totalSumSquares / Float(totalFrames))
                if currentRMS > threshold || maxLevel > threshold * 3 {
                    #if DEBUG
                    print("🔊 Audio analysis (early exit): RMS=\(String(format: "%.4f", currentRMS)), Max=\(String(format: "%.4f", maxLevel)), threshold=\(threshold), hasSpeech=true")
                    #endif
                    return true
                }
            }
            
            guard totalFrames > 0 else { return true }
            
            let rms = sqrt(totalSumSquares / Float(totalFrames))
            let hasSpeech = rms > threshold || maxLevel > threshold * 3
            
            #if DEBUG
            print("🔊 Audio analysis: RMS=\(String(format: "%.4f", rms)), Max=\(String(format: "%.4f", maxLevel)), threshold=\(threshold), hasSpeech=\(hasSpeech)")
            #endif
            
            return hasSpeech
        } catch {
            #if DEBUG
            print("⚠️ Audio analysis failed: \(error.localizedDescription), assuming speech present")
            #endif
            return true
        }
    }
}
