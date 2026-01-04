import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    
    @Published private(set) var isRecording = false
    @Published private(set) var isProcessing = false
    @Published private(set) var audioLevel: Float = 0
    @Published var lastError: String?
    
    private let audioRecorder = AudioRecorder()
    private let overlay = OverlayWindowController.shared
    private var recordingTask: Task<Void, Never>?
    
    private var capturedPresetName: String = ""
    private var capturedSystemPrompt: String = ""
    private var capturedPresetsWithPrompts: [(name: String, prompt: String)] = []
    
    private init() {}
    
    func startRecording() {
        guard !isRecording, !isProcessing else { return }
        
        let settings = AppSettings.shared
        capturedPresetName = settings.selectedPreset?.name ?? "Custom"
        capturedSystemPrompt = settings.systemPrompt
        
        // Capture all presets and their CURRENT prompts at the moment recording starts
        capturedPresetsWithPrompts = settings.allPresets.map { preset in
            (name: preset.name, prompt: settings.promptForPreset(preset))
        }
        
        recordingTask = Task {
            let hasPermission = await PermissionService.shared.checkMicrophonePermission()
            guard hasPermission else {
                lastError = "Microphone permission denied"
                return
            }
            
            do {
                print("📝 Starting recording with preset: \(capturedPresetName)")
                isRecording = true
                lastError = nil
                overlay.show()
                
                let highQuality = AppSettings.shared.highQualityAudio
                let levelStream = try await audioRecorder.startRecording(highQuality: highQuality)
                print("✅ Recording started")
                for await level in levelStream {
                    audioLevel = level
                    overlay.updateAudioLevel(level)
                }
            } catch {
                print("❌ Recording failed: \(error.localizedDescription)")
                lastError = error.localizedDescription
                isRecording = false
                overlay.hide()
            }
        }
    }
    
    func stopAndProcess() {
        guard isRecording else { return }
        
        recordingTask?.cancel()
        recordingTask = nil
        
        Task {
            print("⏹️ Stopping recording...")
            let audioURL = await audioRecorder.stopRecording()
            isRecording = false
            audioLevel = 0
            
            guard let url = audioURL else {
                print("❌ No audio file URL returned")
                overlay.hide()
                return
            }
            
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            print("📁 Audio file size: \(fileSize) bytes")
            if fileSize == 0 {
                lastError = "No audio recorded"
                overlay.hide()
                return
            }
            
            isProcessing = true
            overlay.setProcessing()
            
            do {
                print("🚀 Starting multi-refinement audit...")
                let settings = AppSettings.shared
                
                // 1. Get raw transcription (Baseline)
                let originalText = try await NetworkService.shared.transcribeAndRefine(
                    audioURL: url,
                    provider: settings.transcriptionProvider,
                    apiKey: settings.transcriptionAPIKey,
                    baseURL: settings.transcriptionBaseURL,
                    model: settings.transcriptionModel,
                    systemPrompt: "" 
                )
                
                print("✅ Baseline obtained: '\(originalText)'")
                
                // 2. Process all captured presets in parallel
                var variants: [String: String] = [:]
                var variantPrompts: [String: String] = [:]
                
                // Capture these for the closure
                let refinementProvider = settings.refinementProvider
                let refinementAPIKey = settings.refinementAPIKey
                let refinementBaseURL = settings.refinementBaseURL
                let refinementModel = settings.refinementModel
                let presets = capturedPresetsWithPrompts
                
                await withTaskGroup(of: (String, String, String)?.self) { group in
                    for p in presets {
                        group.addTask {
                            do {
                                let refined = try await NetworkService.shared.refine(
                                    text: originalText,
                                    provider: refinementProvider,
                                    apiKey: refinementAPIKey,
                                    baseURL: refinementBaseURL,
                                    model: refinementModel,
                                    systemPrompt: p.prompt
                                )
                                return (p.name, refined, p.prompt)
                            } catch {
                                print("⚠️ Variant \(p.name) failed: \(error.localizedDescription)")
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
                
                // 3. Paste the result of the SELECTED preset
                let finalResult = variants[capturedPresetName] ?? originalText
                print("📋 Pasting result for \(capturedPresetName)...")
                PasteService.shared.paste(text: finalResult)
                
                // 4. Save to history with all variants and their respective prompts
                HistoryStore.shared.add(
                    original: originalText,
                    refined: finalResult,
                    presetName: capturedPresetName,
                    systemPrompt: capturedSystemPrompt,
                    variants: variants,
                    variantPrompts: variantPrompts
                )
                
                lastError = nil
            } catch {
                print("❌ Multi-refinement failed: \(error.localizedDescription)")
                lastError = error.localizedDescription
            }
            
            isProcessing = false
            overlay.hide()
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    private struct TranscriptionResult {
        let original: String
        let refined: String
    }
    
    private func transcribeAndRefineWithOriginal(url: URL, prompt: String) async throws -> TranscriptionResult {
        let settings = AppSettings.shared
        
        if settings.transcriptionProvider.supportsRefinementInOneCall {
            let refined = try await NetworkService.shared.transcribeAndRefine(
                audioURL: url,
                provider: settings.transcriptionProvider,
                apiKey: settings.transcriptionAPIKey,
                baseURL: settings.transcriptionBaseURL,
                model: settings.transcriptionModel,
                systemPrompt: prompt
            )
            return TranscriptionResult(original: refined, refined: refined)
        } else {
            let original = try await NetworkService.shared.transcribeAndRefine(
                audioURL: url,
                provider: settings.transcriptionProvider,
                apiKey: settings.transcriptionAPIKey,
                baseURL: settings.transcriptionBaseURL,
                model: settings.transcriptionModel,
                systemPrompt: ""
            )
            
            let refined = try await NetworkService.shared.refine(
                text: original,
                provider: settings.refinementProvider,
                apiKey: settings.refinementAPIKey,
                baseURL: settings.refinementBaseURL,
                model: settings.refinementModel,
                systemPrompt: prompt
            )
            
            return TranscriptionResult(original: original, refined: refined)
        }
    }
}
