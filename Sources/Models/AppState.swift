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
    
    private init() {}
    
    func startRecording() {
        guard !isRecording, !isProcessing else { return }
        
        recordingTask = Task {
            let hasPermission = await PermissionService.shared.checkMicrophonePermission()
            guard hasPermission else {
                lastError = "Microphone permission denied"
                return
            }
            
            do {
                print("📝 Starting recording...")
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
                print("🚀 Starting transcription...")
                let result = try await transcribeAndRefineWithOriginal(url: url)
                print("✅ Transcription result: '\(result.refined)'")
                
                HistoryStore.shared.add(original: result.original, refined: result.refined)
                
                print("📋 Pasting text...")
                PasteService.shared.paste(text: result.refined)
                lastError = nil
            } catch {
                print("❌ Transcription/Refinement failed: \(error.localizedDescription)")
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
    
    private func transcribeAndRefineWithOriginal(url: URL) async throws -> TranscriptionResult {
        let settings = AppSettings.shared
        
        if settings.transcriptionProvider.supportsRefinementInOneCall {
            let refined = try await NetworkService.shared.transcribeAndRefine(
                audioURL: url,
                provider: settings.transcriptionProvider,
                apiKey: settings.transcriptionAPIKey,
                baseURL: settings.transcriptionBaseURL,
                model: settings.transcriptionModel,
                systemPrompt: settings.systemPrompt
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
                systemPrompt: settings.systemPrompt
            )
            
            return TranscriptionResult(original: original, refined: refined)
        }
    }
}
