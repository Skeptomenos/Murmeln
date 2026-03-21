import Foundation
import SwiftUI
import AppKit

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    
    /// Internal state machine to prevent race conditions during async operations
    enum RecordingPhase {
        case idle
        case warmingUp             // Engine running, waiting for hold threshold
        case requestingPermission  // Set synchronously before permission check
        case recording             // Actively recording audio
        case processing            // Transcribing and refining
    }
    
    @Published private(set) var recordingPhase: RecordingPhase = .idle
    @Published private(set) var audioLevel: Float = 0
    @Published var lastError: String?
    
    /// Backward-compatible computed property for UI bindings
    var isRecording: Bool {
        recordingPhase == .recording || recordingPhase == .requestingPermission
    }
    
    /// Backward-compatible computed property for UI bindings
    var isProcessing: Bool {
        recordingPhase == .processing
    }
    
    private let audioRecorder = AudioRecorder()
    private let overlay = OverlayWindowController.shared
    private var recordingTask: Task<Void, Never>?
    private var warmUpTask: Task<Void, Never>?
    
    private var capturedPresetName: String = ""
    private var capturedSystemPrompt: String = ""
    private var capturedPresetsWithPrompts: [(name: String, prompt: String)] = []
    
    private init() {}
    
    private func announceForAccessibility(_ message: String) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high]
        )
    }
    
    private func promptWithDictionary(_ basePrompt: String) -> String {
        let settings = AppSettings.shared
        guard settings.personalDictionaryEnabled, !settings.personalDictionary.isEmpty else {
            return basePrompt
        }
        let words = settings.personalDictionary.joined(separator: ", ")
        let dictionaryInstruction = " If the speaker says words similar to these names/terms, use this exact spelling: \(words)."
        return basePrompt + dictionaryInstruction
    }
    
    // MARK: - Warm-up Flow (called on Fn press, before 400ms threshold)
    
    /// Starts engine warm-up immediately on Fn press.
    /// This eliminates audio startup latency by the time recording actually begins.
    func warmUpEngine() {
        guard recordingPhase == .idle else { return }
        
        recordingPhase = .warmingUp
        
        warmUpTask = Task {
            let hasPermission = await PermissionService.shared.checkMicrophonePermission()
            guard hasPermission else {
                lastError = "Microphone access denied. Open System Settings → Privacy & Security → Microphone to grant access."
                recordingPhase = .idle
                return
            }
            
            do {
                let highQuality = AppSettings.shared.highQualityAudio
                let levelStream = try await audioRecorder.prepareEngine(highQuality: highQuality)
                #if DEBUG
                print("🔥 Engine warm-up complete")
                #endif
                
                // Show overlay during warm-up for visual feedback
                overlay.show()
                
                // Stream levels during warm-up (visual feedback only, not recording)
                for await level in levelStream {
                    audioLevel = level
                    overlay.updateAudioLevel(level)
                }
            } catch {
                #if DEBUG
                print("❌ Warm-up failed: \(error.localizedDescription)")
                #endif
                lastError = error.localizedDescription
                recordingPhase = .idle
                overlay.hide()
            }
        }
    }
    
    /// Cancels warm-up if user releases Fn before 400ms threshold.
    func cancelWarmUp() {
        guard recordingPhase == .warmingUp else { return }
        
        warmUpTask?.cancel()
        warmUpTask = nil
        
        Task {
            await audioRecorder.cancelWarmUp()
            audioLevel = 0
            recordingPhase = .idle
            overlay.hide()
        }
    }
    
    /// Begins actual recording after 400ms threshold is met.
    /// Engine is already warm, so this is near-instant.
    func beginRecording() {
        guard recordingPhase == .warmingUp else {
            // Fallback: if not warmed up, use legacy flow
            startRecording()
            return
        }
        
        let settings = AppSettings.shared
        capturedPresetName = settings.selectedPreset?.name ?? "Custom"
        capturedSystemPrompt = settings.systemPrompt
        
        // Capture all presets and their CURRENT prompts at the moment recording starts
        capturedPresetsWithPrompts = settings.allPresets.map { preset in
            (name: preset.name, prompt: settings.promptForPreset(preset))
        }
        
        recordingPhase = .recording
        lastError = nil
        announceForAccessibility("Recording started")
        
        recordingTask = Task {
            do {
                try await audioRecorder.beginCapture()
                #if DEBUG
                print("🎙️ Recording started (zero latency)")
                #endif
            } catch {
                #if DEBUG
                print("❌ Begin capture failed: \(error.localizedDescription)")
                #endif
                lastError = error.localizedDescription
                recordingPhase = .idle
                overlay.hide()
            }
        }
    }
    
    // MARK: - Legacy Flow (for backward compatibility and lock mode)
    
    func startRecording() {
        guard recordingPhase == .idle else { return }
        
        let settings = AppSettings.shared
        capturedPresetName = settings.selectedPreset?.name ?? "Custom"
        capturedSystemPrompt = settings.systemPrompt
        
        // Capture all presets and their CURRENT prompts at the moment recording starts
        capturedPresetsWithPrompts = settings.allPresets.map { preset in
            (name: preset.name, prompt: settings.promptForPreset(preset))
        }
        
        // Set state SYNCHRONOUSLY before any async work to prevent race conditions
        // This ensures stopAndProcess() knows we're in the recording flow
        recordingPhase = .requestingPermission
        
        recordingTask = Task {
            let hasPermission = await PermissionService.shared.checkMicrophonePermission()
            guard hasPermission else {
                lastError = "Microphone access denied. Open System Settings → Privacy & Security → Microphone to grant access."
                recordingPhase = .idle
                return
            }
            
            do {
                #if DEBUG
                print("📝 Starting recording with preset: \(capturedPresetName)")
                #endif
                recordingPhase = .recording
                lastError = nil
                overlay.show()
                announceForAccessibility("Recording started")
                
                let highQuality = AppSettings.shared.highQualityAudio
                let levelStream = try await audioRecorder.startRecording(highQuality: highQuality)
                #if DEBUG
                print("✅ Recording started")
                #endif
                for await level in levelStream {
                    audioLevel = level
                    overlay.updateAudioLevel(level)
                }
            } catch {
                #if DEBUG
                print("❌ Recording failed: \(error.localizedDescription)")
                #endif
                lastError = error.localizedDescription
                recordingPhase = .idle
                overlay.hide()
            }
        }
    }
    
    func stopAndProcess() {
        // Handle .recording, .requestingPermission, and .warmingUp states
        // This fixes race conditions during various phases
        guard recordingPhase == .recording || recordingPhase == .requestingPermission || recordingPhase == .warmingUp else { return }
        
        // If still warming up, just cancel (no audio to process)
        if recordingPhase == .warmingUp {
            cancelWarmUp()
            return
        }
        
        recordingTask?.cancel()
        recordingTask = nil
        warmUpTask?.cancel()
        warmUpTask = nil
        
        Task {
            #if DEBUG
            print("⏹️ Stopping recording...")
            #endif
            let audioURL = await audioRecorder.stopRecording()
            // Stay in .recording state during VAD/trim to prevent race conditions
            // Only transition to .idle on early returns, or to .processing on success
            audioLevel = 0
            
            guard let url = audioURL else {
                #if DEBUG
                print("❌ No audio file URL returned")
                #endif
                recordingPhase = .idle
                overlay.hide()
                return
            }
            
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            #if DEBUG
            print("📁 Audio file size: \(fileSize) bytes")
            #endif
            if fileSize == 0 {
                lastError = "No audio recorded"
                recordingPhase = .idle
                overlay.hide()
                return
            }
            
            let hasSpeech = await AudioRecorder.hasAudibleSpeech(audioURL: url)
            if !hasSpeech {
                #if DEBUG
                print("🔇 No speech detected, skipping transcription")
                #endif
                lastError = nil
                recordingPhase = .idle
                overlay.hide()
                try? FileManager.default.removeItem(at: url)
                return
            }
            
            let audioToProcess: URL
            let settings = AppSettings.shared
            if settings.disableSilenceTrimming {
                audioToProcess = url
                #if DEBUG
                print("🔪 Trim: disabled by user setting")
                #endif
            } else if let trimmedURL = await AudioRecorder.trimSilence(audioURL: url) {
                audioToProcess = trimmedURL
                #if DEBUG
                let originalSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
                let trimmedSize = (try? FileManager.default.attributesOfItem(atPath: trimmedURL.path)[.size] as? Int) ?? 0
                print("🔪 Trim: \(originalSize) bytes → \(trimmedSize) bytes")
                #endif
            } else {
                audioToProcess = url
                #if DEBUG
                print("🔪 Trim: skipped (returned nil)")
                #endif
            }
            
            recordingPhase = .processing
            overlay.setProcessing()
            announceForAccessibility("Processing speech")
            
            do {
                #if DEBUG
                print("🚀 Starting transcription phase...")
                #endif
                let settings = AppSettings.shared
                
                // For native audio models (GPT-4o/Gemini), provide a dictionary-enhanced verbatim prompt
                // even for the baseline transcription. This improves accuracy for names/terms.
                let baselinePrompt = settings.transcriptionProvider.isNativeAudioModel 
                    ? self.promptWithDictionary("") 
                    : ""
                
                let originalText = try await NetworkService.shared.transcribeAndRefine(
                    audioURL: audioToProcess,
                    provider: settings.transcriptionProvider,
                    apiKey: settings.transcriptionAPIKey,
                    baseURL: settings.transcriptionBaseURL,
                    model: settings.transcriptionModel,
                    systemPrompt: baselinePrompt
                )
                
                #if DEBUG
                print("✅ Baseline obtained: '\(originalText)'")
                #endif
                
                // 2. Check if refinement is skipped (Raw Mode)
                if settings.skipRefinement {
                    #if DEBUG
                    print("📋 Skip refinement enabled - using raw transcript")
                    #endif
                    PasteService.shared.paste(text: originalText)
                    announceForAccessibility("Text pasted")
                    
                    HistoryStore.shared.add(
                        original: originalText,
                        refined: originalText,
                        presetName: "Raw (No Refinement)",
                        systemPrompt: "",
                        variants: [:],
                        variantPrompts: [:]
                    )
                } else {
                    // 3. Process all captured presets in parallel (if enabled)
                    var variants: [String: String] = [:]
                    var variantPrompts: [String: String] = [:]
                    
                    // Capture these for the closure
                    let refinementProvider = settings.refinementProvider
                    let refinementAPIKey = settings.refinementAPIKey
                    let refinementBaseURL = settings.refinementBaseURL
                    let refinementModel = settings.refinementModel
                    let presets = capturedPresetsWithPrompts
                    
                    if settings.parallelRefinementEnabled {
                        await withTaskGroup(of: (String, String, String)?.self) { group in
                            for p in presets {
                                let enhancedPrompt = self.promptWithDictionary(p.prompt)
                                group.addTask {
                                    do {
                                        let refined = try await NetworkService.shared.refine(
                                            text: originalText,
                                            provider: refinementProvider,
                                            apiKey: refinementAPIKey,
                                            baseURL: refinementBaseURL,
                                            model: refinementModel,
                                            systemPrompt: enhancedPrompt
                                        )
                                        return (p.name, refined, p.prompt)
                                    } catch {
                                        #if DEBUG
                                        print("⚠️ Variant \(p.name) failed: \(error.localizedDescription)")
                                        #endif
                                        return nil
                                    }
                                }
                            }
                            
                            for await result in group {
                                if let (name, text, prompt) = result {
                                    variants[name] = text
                                    variantPrompts[name] = prompt
                                }
                            }
                        }
                    } else {
                        // Only process the selected preset
                        let enhancedPrompt = promptWithDictionary(capturedSystemPrompt)
                        let refined = try await NetworkService.shared.refine(
                            text: originalText,
                            provider: refinementProvider,
                            apiKey: refinementAPIKey,
                            baseURL: refinementBaseURL,
                            model: refinementModel,
                            systemPrompt: enhancedPrompt
                        )
                        variants[capturedPresetName] = refined
                        variantPrompts[capturedPresetName] = capturedSystemPrompt
                    }
                    
                    // 4. Paste the result of the SELECTED preset
                    let finalResult = variants[capturedPresetName] ?? originalText
                    #if DEBUG
                    print("📋 Pasting result for \(capturedPresetName)...")
                    #endif
                    PasteService.shared.paste(text: finalResult)
                    announceForAccessibility("Text pasted")
                    
                    // 5. Save to history with all variants and their respective prompts
                    HistoryStore.shared.add(
                        original: originalText,
                        refined: finalResult,
                        presetName: capturedPresetName,
                        systemPrompt: capturedSystemPrompt,
                        variants: variants,
                        variantPrompts: variantPrompts
                    )
                }
                
                lastError = nil
            } catch {
                #if DEBUG
                print("❌ Multi-refinement failed: \(error.localizedDescription)")
                #endif
                lastError = error.localizedDescription
            }
            
            recordingPhase = .idle
            overlay.hide()
            await cleanupTempFile(at: url)
            if audioToProcess != url {
                await cleanupTempFile(at: audioToProcess)
            }
        }
    }
    
    private func cleanupTempFile(at url: URL, maxRetries: Int = 3) async {
        for attempt in 1...maxRetries {
            do {
                try FileManager.default.removeItem(at: url)
                return
            } catch {
                if attempt == maxRetries {
                    #if DEBUG
                    print("⚠️ Failed to cleanup temp file after \(maxRetries) attempts: \(url.lastPathComponent) - \(error.localizedDescription)")
                    #endif
                } else {
                    try? await Task.sleep(for: .milliseconds(100 * attempt))
                }
            }
        }
    }
    
}
