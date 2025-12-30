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
                isRecording = true
                lastError = nil
                overlay.show()
                
                let levelStream = try await audioRecorder.startRecording()
                for await level in levelStream {
                    audioLevel = level
                    overlay.updateAudioLevel(level)
                }
            } catch {
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
            let audioURL = await audioRecorder.stopRecording()
            isRecording = false
            audioLevel = 0
            
            guard let url = audioURL else {
                overlay.hide()
                return
            }
            
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            if fileSize == 0 {
                lastError = "No audio recorded"
                overlay.hide()
                return
            }
            
            isProcessing = true
            overlay.setProcessing()
            
            do {
                let text = try await transcribeAndRefine(url: url)
                PasteService.shared.paste(text: text)
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
            
            isProcessing = false
            overlay.hide()
            
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    private func transcribeAndRefine(url: URL) async throws -> String {
        let settings = AppSettings.shared
        
        if settings.transcriptionProvider.supportsRefinementInOneCall {
            return try await NetworkService.shared.transcribeAndRefine(
                audioURL: url,
                provider: settings.transcriptionProvider,
                apiKey: settings.transcriptionAPIKey,
                baseURL: settings.transcriptionBaseURL,
                model: settings.transcriptionModel,
                systemPrompt: settings.systemPrompt
            )
        } else {
            let transcription = try await NetworkService.shared.transcribeAndRefine(
                audioURL: url,
                provider: settings.transcriptionProvider,
                apiKey: settings.transcriptionAPIKey,
                baseURL: settings.transcriptionBaseURL,
                model: settings.transcriptionModel,
                systemPrompt: ""
            )
            
            return try await NetworkService.shared.refine(
                text: transcription,
                provider: settings.refinementProvider,
                apiKey: settings.refinementAPIKey,
                baseURL: settings.refinementBaseURL,
                model: settings.refinementModel,
                systemPrompt: settings.systemPrompt
            )
        }
    }
}
