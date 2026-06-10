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
        var preRollBuffers: [AVAudioPCMBuffer] = []
        var preRollFrameCount = 0
        var preRollMaxFrames = 0
        var pendingPreRollFlush = false
        var captureStartedAtNs: UInt64?
        var firstCaptureBufferLogged = false
    }
    
    private let tapState = TapState()
    
    // Warm-up state
    private var isWarmedUp = false
    private var cachedHighQuality = false
    private var cachedOutputFormat: AVAudioFormat?
    private var cachedTapFormat: AVAudioFormat?
    private var activeCaptureID: String?
    private let preRollDurationSeconds: Double = 0.35
    
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
    func prepareEngine(highQuality: Bool = false, captureID: String? = nil) async throws -> AsyncStream<Float> {
        if let captureID {
            activeCaptureID = captureID
        }

        logDiagnostics("audio.warmup.prepare_start", [
            "high_quality": String(highQuality)
        ])

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
        tapState.preRollBuffers.removeAll(keepingCapacity: true)
        tapState.preRollFrameCount = 0
        tapState.preRollMaxFrames = Int(outputFormat.sampleRate * preRollDurationSeconds)
        tapState.pendingPreRollFlush = false
        
        let stream = AsyncStream<Float> { continuation in
            self.levelContinuation = continuation
        }
        
        // Install a single persistent tap
        node.installTap(onBus: 0, bufferSize: 1024, format: tapFormat) { [weak self, tapState] buffer, _ in
            // Track buffer arrival time for drain detection
            tapState.lastBufferTime = Date()
            
            let level = Self.calculateRMS(buffer: buffer)
            
            func handleOutputBuffer(_ processedBuffer: AVAudioPCMBuffer) {
                if tapState.isWriting, let file = tapState.audioFile {
                    let hadPendingPreRollFlush = tapState.pendingPreRollFlush
                    if tapState.pendingPreRollFlush {
                        _ = try? Self.flushPreRollBuffers(
                            to: file,
                            buffers: &tapState.preRollBuffers,
                            totalFrames: &tapState.preRollFrameCount,
                            pendingFlush: &tapState.pendingPreRollFlush
                        )
                    }

                    if !tapState.firstCaptureBufferLogged {
                        tapState.firstCaptureBufferLogged = true
                        let captureStartNs = tapState.captureStartedAtNs
                        let firstBufferElapsedMs: UInt64
                        if let captureStartNs {
                            firstBufferElapsedMs = (DispatchTime.now().uptimeNanoseconds - captureStartNs) / 1_000_000
                        } else {
                            firstBufferElapsedMs = 0
                        }

                        if let self {
                            Task {
                                await self.recordFirstCaptureBuffer(
                                    frameCount: Int(processedBuffer.frameLength),
                                    elapsedMs: firstBufferElapsedMs,
                                    pendingPreRollFlush: hadPendingPreRollFlush
                                )
                            }
                        }
                    }

                    try? file.write(from: processedBuffer)
                } else {
                    Self.appendPreRollBuffer(
                        processedBuffer,
                        to: &tapState.preRollBuffers,
                        totalFrames: &tapState.preRollFrameCount,
                        maxFrames: tapState.preRollMaxFrames
                    )
                }
            }

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
                        handleOutputBuffer(outputBuffer)
                    }
                }
            } else {
                handleOutputBuffer(buffer)
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
            logDiagnostics("audio.warmup.prepare_complete", [
                "input_sample_rate": String(format: "%.0f", inputFormat.sampleRate),
                "output_sample_rate": String(format: "%.0f", outputFormat.sampleRate)
            ])
        } catch {
            logDiagnostics("audio.warmup.prepare_failed", ["error": error.localizedDescription])
            throw AudioError.engineStartFailed(error)
        }
        
        isWarmedUp = true
        return stream
    }
    
    // MARK: - Phase 2: Begin Capture (called after 400ms threshold)
    
    /// Starts actual recording to file. Must call prepareEngine() first.
    func beginCapture(captureID: String? = nil) async throws {
        if let captureID {
            activeCaptureID = captureID
        }

        guard isWarmedUp, let outputFormat = cachedOutputFormat else {
            logDiagnostics("audio.capture.begin_failed", ["reason": "not_warmed_up"])
            throw AudioError.notWarmedUp
        }
        
        // Create the output file
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("recording_\(UUID().uuidString).wav")
        
        let file = try AVAudioFile(forWriting: fileURL, settings: outputFormat.settings)
        
        self.audioFile = file
        self.tempFileURL = fileURL

        let preRollFrames = tapState.preRollFrameCount
        let preRollMs = Int((Double(preRollFrames) / outputFormat.sampleRate) * 1000)
        
        tapState.audioFile = file
        let flushedPreRollFrames = (try? Self.flushPreRollBuffers(
            to: file,
            buffers: &tapState.preRollBuffers,
            totalFrames: &tapState.preRollFrameCount,
            pendingFlush: &tapState.pendingPreRollFlush
        )) ?? 0

        // Signal the tap to start writing. Keep one deferred flush armed so
        // any buffers that arrive between the synchronous flush above and the
        // next tap callback still get written in-order before live audio.
        tapState.captureStartedAtNs = DispatchTime.now().uptimeNanoseconds
        tapState.firstCaptureBufferLogged = false
        tapState.pendingPreRollFlush = true
        tapState.isWriting = true

        logDiagnostics("audio.capture.begin", [
            "file": fileURL.lastPathComponent,
            "sample_rate": String(format: "%.0f", outputFormat.sampleRate),
            "pre_roll_frames": String(preRollFrames),
            "pre_roll_ms": String(preRollMs),
            "pre_roll_flushed_frames": String(flushedPreRollFrames)
        ])
        
        #if DEBUG
        print("🎙️ Capture started (zero latency, no tap gap)")
        #endif
    }
    
    // MARK: - Cancel Warm-up (called if user releases before 400ms)
    
    /// Stops the warmed-up engine without saving any audio.
    func cancelWarmUp() async {
        logDiagnostics("audio.warmup.cancel")
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
        activeCaptureID = nil
        
        tapState.isWriting = false
        tapState.audioFile = nil
        tapState.converter = nil
        tapState.preRollBuffers.removeAll(keepingCapacity: true)
        tapState.preRollFrameCount = 0
        tapState.preRollMaxFrames = 0
        tapState.pendingPreRollFlush = false
        tapState.captureStartedAtNs = nil
        tapState.firstCaptureBufferLogged = false
        
        #if DEBUG
        print("❄️ Warm-up cancelled")
        #endif
    }
    
    // MARK: - Legacy API (for backward compatibility)
    
    func startRecording(highQuality: Bool = false, captureID: String? = nil) async throws -> AsyncStream<Float> {
        let stream = try await prepareEngine(highQuality: highQuality, captureID: captureID)
        try await beginCapture(captureID: captureID)
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

    static func copyBuffer(_ source: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard source.frameLength > 0,
              let copiedBuffer = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: source.frameLength),
              let sourceChannelData = source.floatChannelData,
              let destinationChannelData = copiedBuffer.floatChannelData else {
            return nil
        }

        copiedBuffer.frameLength = source.frameLength
        let channelCount = Int(source.format.channelCount)
        let frameCount = Int(source.frameLength)

        for channel in 0..<channelCount {
            destinationChannelData[channel].update(from: sourceChannelData[channel], count: frameCount)
        }

        return copiedBuffer
    }

    static func appendPreRollBuffer(
        _ sourceBuffer: AVAudioPCMBuffer,
        to buffers: inout [AVAudioPCMBuffer],
        totalFrames: inout Int,
        maxFrames: Int
    ) {
        guard maxFrames > 0,
              let copiedBuffer = copyBuffer(sourceBuffer) else {
            return
        }

        buffers.append(copiedBuffer)
        totalFrames += Int(copiedBuffer.frameLength)

        while totalFrames > maxFrames, !buffers.isEmpty {
            let removed = buffers.removeFirst()
            totalFrames -= Int(removed.frameLength)
        }
    }

    static func flushPreRollBuffers(
        to file: AVAudioFile,
        buffers: inout [AVAudioPCMBuffer],
        totalFrames: inout Int,
        pendingFlush: inout Bool
    ) throws -> Int {
        let flushedFrames = totalFrames

        for preRollBuffer in buffers {
            try file.write(from: preRollBuffer)
        }

        buffers.removeAll(keepingCapacity: true)
        totalFrames = 0
        pendingFlush = false

        return flushedFrames
    }
    
    func stopRecording(captureID: String? = nil) async -> URL? {
        if let captureID {
            activeCaptureID = captureID
        }

        // Wait briefly for trailing buffers before stopping.
        // Current tap behavior tends to update buffer timestamps continuously,
        // so this branch is primarily a bounded grace period.
        let drainThreshold: TimeInterval = 0.12
        let maxWait: TimeInterval = 0.35
        let startTime = Date()

        logDiagnostics("audio.capture.stop_requested", [
            "drain_threshold_ms": String(Int(drainThreshold * 1000)),
            "max_wait_ms": String(Int(maxWait * 1000))
        ])
        
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
                logDiagnostics("audio.capture.stop_drain_detected", [
                    "wait_ms": String(Int(totalWaitTime * 1000)),
                    "since_last_buffer_ms": String(Int(timeSinceLastBuffer * 1000))
                ])
                break
            }
            
            if totalWaitTime >= maxWait {
                #if DEBUG
                print("⚠️ Buffer drain timeout after \(String(format: "%.0f", maxWait * 1000))ms")
                #endif
                logDiagnostics("audio.capture.stop_drain_timeout", [
                    "wait_ms": String(Int(totalWaitTime * 1000)),
                    "since_last_buffer_ms": String(Int(timeSinceLastBuffer * 1000))
                ])
                break
            }
            
            try? await Task.sleep(for: .milliseconds(20))
        }
        
        tapState.isWriting = false
        
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        levelContinuation?.finish()

        let flushedPreRollFrames = if let file = tapState.audioFile {
            (try? Self.flushPreRollBuffers(
                to: file,
                buffers: &tapState.preRollBuffers,
                totalFrames: &tapState.preRollFrameCount,
                pendingFlush: &tapState.pendingPreRollFlush
            )) ?? 0
        } else {
            0
        }

        if flushedPreRollFrames > 0 {
            logDiagnostics("audio.capture.pre_roll_flushed_on_stop", [
                "flushed_frames": String(flushedPreRollFrames)
            ])
        }

        let flushedFrames = flushPendingConvertedFrames()
        if flushedFrames > 0 {
            logDiagnostics("audio.capture.converter_flushed", [
                "flushed_frames": String(flushedFrames)
            ])
        }

        let recordedFrames = audioFile?.length ?? 0
        let sampleRate = cachedOutputFormat?.sampleRate ?? tapState.outputFormat?.sampleRate ?? 0
        let audioDurationMs: UInt64
        if sampleRate > 0 {
            audioDurationMs = UInt64((Double(recordedFrames) / sampleRate * 1000).rounded())
        } else {
            audioDurationMs = 0
        }
        
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
        tapState.preRollBuffers.removeAll(keepingCapacity: true)
        tapState.preRollFrameCount = 0
        tapState.preRollMaxFrames = 0
        tapState.pendingPreRollFlush = false
        tapState.captureStartedAtNs = nil
        tapState.firstCaptureBufferLogged = false

        if let url {
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? -1
            logDiagnostics("audio.capture.stop_complete", [
                "file": url.lastPathComponent,
                "file_size_bytes": String(fileSize),
                "recorded_frames": String(recordedFrames),
                "sample_rate": String(format: "%.0f", sampleRate),
                "audio_duration_ms": String(audioDurationMs)
            ])
        } else {
            logDiagnostics("audio.capture.stop_complete", ["file": "nil"])
        }

        activeCaptureID = nil
        
        return url
    }

    private func logDiagnostics(_ event: String, _ metadata: [String: String] = [:]) {
        let captureID = activeCaptureID
        Task {
            await CaptureDiagnostics.shared.mark(event, captureID: captureID, metadata: metadata)
        }
    }

    private func recordFirstCaptureBuffer(frameCount: Int, elapsedMs: UInt64, pendingPreRollFlush: Bool) {
        logDiagnostics("audio.capture.first_buffer_received", [
            "frame_count": String(frameCount),
            "elapsed_ms": String(elapsedMs),
            "pending_pre_roll_flush": String(pendingPreRollFlush)
        ])
    }

    private func flushPendingConvertedFrames() -> Int {
        guard let converter = tapState.converter,
              let outputFormat = tapState.outputFormat,
              let file = tapState.audioFile else {
            return 0
        }

        return Self.flushConverter(converter, outputFormat: outputFormat) { buffer in
            try file.write(from: buffer)
        }
    }

    static func flushConverter(
        _ converter: AVAudioConverter,
        outputFormat: AVAudioFormat,
        maxIterations: Int = 16,
        writeBuffer: (AVAudioPCMBuffer) throws -> Void
    ) -> Int {
        var totalFlushedFrames = 0

        for _ in 0..<maxIterations {
            guard let flushBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 2048) else {
                break
            }

            var conversionError: NSError?
            converter.convert(to: flushBuffer, error: &conversionError) { _, outStatus in
                outStatus.pointee = .endOfStream
                return nil
            }

            if conversionError != nil || flushBuffer.frameLength == 0 {
                break
            }

            do {
                try writeBuffer(flushBuffer)
            } catch {
                break
            }

            totalFlushedFrames += Int(flushBuffer.frameLength)
        }

        return totalFlushedFrames
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
