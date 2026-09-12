import SwiftUI

@MainActor
struct WhisperKitSetupView: View {
    @StateObject private var service = WhisperKitService.shared
    @State private var controller = WhisperKitSelectionController()
    @Environment(\.dismiss) private var dismiss

    private static let modelOptions = WhisperKitModelOption.all
    @State private var selectedVariant = Self.initialVariant()
    
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

    private static func initialVariant() -> String {
        let persistedVariant = AppSettings.shared.whisperKitModel
        guard modelOptions.contains(where: { $0.variant == persistedVariant }) else {
            return recommendedModelForSystem()
        }
        return persistedVariant
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "waveform.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                    .foregroundStyle(Color.accentColor)
                
                Text("WhisperKit Setup")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Download a model to enable offline transcription.\nModels are stored on your device.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding(.top)
            
            // Model Selection
            VStack(alignment: .leading) {
                Text("Select Model")
                    .font(.headline)
                
                List(Self.modelOptions) { model in
                    Button {
                        selectedVariant = model.variant
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(model.name)
                                    .font(.body)
                                    .fontWeight(.medium)
                                Text(model.quality)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            VStack(alignment: .trailing) {
                                Text(model.size)
                                    .font(.caption)
                                    .monospacedDigit()
                                Text(model.speed)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            if service.isModelDownloaded(model.variant) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .padding(.leading, 8)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                    .disabled(controller.isLoading || controller.errorMessage != nil)
                    .accessibilityValue(selectedVariant == model.variant ? "Selected" : "Not selected")
                    .listRowBackground(selectedVariant == model.variant ? Color.accentColor.opacity(0.1) : Color.clear)
                }
                .frame(height: 200)
                .listStyle(.inset)
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(.secondary.opacity(0.2))
                }
            }
            
            // Selected Model Info + System RAM
            if let selected = Self.modelOptions.first(where: { $0.variant == selectedVariant }) {
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
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            }

            if controller.isLoading {
                VStack(spacing: 8) {
                    if service.isDownloading {
                        ProgressView(value: service.downloadProgress)
                    } else {
                        ProgressView()
                    }
                    Text(service.isDownloading ? service.downloadStatus : "Loading selected model…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            } else if let errorMessage = controller.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
            
            Divider()
            
            // Actions
            HStack {
                Button("Cancel") {
                    controller.cancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()

                if controller.canRetry {
                    Button("Retry") {
                        controller.retry()
                    }
                    .buttonStyle(.borderedProminent)
                } else if service.isModelDownloaded(selectedVariant) {
                    Button("Select & Done") {
                        submitSelection()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(controller.isLoading)
                } else {
                    Button("Download") {
                        submitSelection()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(controller.isLoading)
                }
            }
        }
        .padding(24)
        .frame(width: 450)
        .task {
            await service.fetchAvailableModels()
        }
        .onDisappear { controller.cancel() }
    }

    private func submitSelection() {
        controller.submit(selectedVariant) {
            dismiss()
        }
    }
}
