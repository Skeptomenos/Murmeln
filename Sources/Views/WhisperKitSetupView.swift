import SwiftUI

struct WhisperKitSetupView: View {
    @StateObject private var service = WhisperKitService.shared
    @Environment(\.dismiss) private var dismiss
    
    struct ModelOption {
        let name: String
        let variant: String
        let size: String
        let speed: String
        let quality: String
        let recommendedRAM: String
    }
    
    // We map user-friendly names to actual variant names
    private let modelOptions: [ModelOption] = [
        ModelOption(name: "Tiny", variant: "openai_whisper-tiny", size: "~75 MB", speed: "Fastest", quality: "Basic", recommendedRAM: "< 4GB"),
        ModelOption(name: "Base", variant: "openai_whisper-base", size: "~142 MB", speed: "Fast", quality: "Good", recommendedRAM: "8GB"),
        ModelOption(name: "Small", variant: "openai_whisper-small", size: "~466 MB", speed: "Moderate", quality: "Better", recommendedRAM: "8GB"),
        ModelOption(name: "Medium", variant: "openai_whisper-medium", size: "~1.5 GB", speed: "Slower", quality: "High", recommendedRAM: "16GB"),
        ModelOption(name: "Large v3", variant: "openai_whisper-large-v3", size: "~2.9 GB", speed: "Slowest", quality: "Best", recommendedRAM: "16GB+")
    ]
    
    @State private var selectedVariant: String = Self.recommendedModelForSystem()
    
    /// System RAM in gigabytes
    private static var systemRAMGB: Double {
        Double(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024 * 1024)
    }
    
    /// Human-readable system RAM description
    private var systemRAMDescription: String {
        let gb = Self.systemRAMGB
        return String(format: "%.0f GB RAM", gb)
    }
    
    /// Returns the recommended model variant based on system RAM
    private static func recommendedModelForSystem() -> String {
        let gigabytes = systemRAMGB
        
        // Model recommendations based on RAM:
        // - large-v3: 32GB+ (best quality, ~3GB model)
        // - medium: 16GB+ (high quality, ~1.5GB model)
        // - small: 8GB+ (good quality, ~500MB model)
        // - base: 4GB+ (basic quality, ~150MB model)
        // - tiny: <4GB (minimal, ~75MB model)
        
        if gigabytes >= 32 {
            return "openai_whisper-large-v3"
        } else if gigabytes >= 16 {
            return "openai_whisper-medium"
        } else if gigabytes >= 8 {
            return "openai_whisper-small"
        } else if gigabytes >= 4 {
            return "openai_whisper-base"
        } else {
            return "openai_whisper-tiny"
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "waveform.circle.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 48, height: 48)
                    .foregroundColor(.accentColor)
                
                Text("WhisperKit Setup")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Download a model to enable offline transcription.\nModels are stored on your device.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
            .padding(.top)
            
            // Model Selection
            VStack(alignment: .leading) {
                Text("Select Model")
                    .font(.headline)
                
                List(modelOptions, id: \.variant) { model in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(model.name)
                                .font(.body)
                                .fontWeight(.medium)
                            Text(model.quality)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing) {
                            Text(model.size)
                                .font(.caption)
                                .monospacedDigit()
                            Text(model.speed)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        if service.downloadedModels.contains(where: { $0.contains(model.variant) }) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .padding(.leading, 8)
                        }
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedVariant = model.variant
                    }
                    .listRowBackground(selectedVariant == model.variant ? Color.accentColor.opacity(0.1) : Color.clear)
                }
                .frame(height: 200)
                .listStyle(.inset)
                .border(Color.secondary.opacity(0.2))
            }
            
            // Selected Model Info + System RAM
            if let selected = modelOptions.first(where: { $0.variant == selectedVariant }) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "info.circle")
                        Text("Recommended for devices with \(selected.recommendedRAM) RAM")
                        Spacer()
                    }
                    HStack {
                        Image(systemName: "memorychip")
                        Text("Your system: \(systemRAMDescription)")
                        Spacer()
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            }
            
            // Download Progress
            if service.isDownloading {
                VStack(spacing: 8) {
                    ProgressView(value: service.downloadProgress)
                    Text(service.downloadStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(8)
            }
            
            Divider()
            
            // Actions
            HStack {
                if service.isDownloading {
                    Button("Cancel Download") {
                        service.cancelDownload()
                    }
                    .keyboardShortcut(.cancelAction)
                } else {
                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
                
                Spacer()
                
                if service.downloadedModels.contains(where: { $0.contains(selectedVariant) }) {
                    Button("Select & Done") {
                        selectAndDismiss()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Download") {
                        Task {
                            await downloadSelected()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(service.isDownloading)
                }
            }
        }
        .padding(24)
        .frame(width: 450)
        .task {
            await service.fetchAvailableModels()
            
            // Auto-select smart default if nothing selected (simple RAM check logic could go here)
            // For now, default to base (already set)
        }
    }
    
    private func downloadSelected() async {
        do {
            _ = try await service.downloadModel(selectedVariant)
            selectAndDismiss()
        } catch WhisperKitService.ServiceError.downloadCancelled {
            // User cancelled - do nothing, stay on the dialog
            print("⚠️ Download cancelled by user")
        } catch {
            // Error is handled in service state, but we could show alert here
            print("❌ Download failed: \(error)")
        }
    }
    
    private func selectAndDismiss() {
        AppSettings.shared.whisperKitModel = selectedVariant
        if AppSettings.shared.transcriptionProvider == .whisperKit {
            AppSettings.shared.transcriptionModel = selectedVariant
        }
        
        // Trigger load
        Task {
            try? await service.loadModel(selectedVariant)
        }
        
        dismiss()
    }
}
