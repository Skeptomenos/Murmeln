import SwiftUI

struct OllamaManagementSection: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var ollamaService: OllamaService

    let loadRefinementModels: () -> Void

    var body: some View {
        SettingsGroup(title: "Ollama service") {
            HStack {
                if ollamaService.isOllamaRunning {
                    Label("Ollama Running", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                } else {
                    Label("Ollama Not Running", systemImage: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                }

                Spacer()

                Button(action: {
                    Task { await ollamaService.checkOllamaStatus() }
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh Ollama status")
                .accessibilityLabel("Refresh Ollama status")
            }

            if !ollamaService.isOllamaRunning {
                Text("To start Ollama: brew install ollama && ollama serve")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }

            DisclosureGroup("Ollama connection") {
                ValidatedURLField(title: "Ollama URL", url: $settings.ollamaBaseURL)
                    .padding(.top, 12)
            }
            if !URLValidation.isValid(settings.ollamaBaseURL) {
                SettingsNote(text: "The Ollama URL is invalid. Open Ollama connection to correct it.", icon: "exclamationmark.circle", color: .red)
            }

            if ollamaService.isOllamaRunning {
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recommended Models")
                        .font(.caption.weight(.medium))

                    ForEach(OllamaService.recommendedModels, id: \.self) { model in
                        HStack {
                            Text(model)
                                .font(.caption)

                            Spacer()

                            if ollamaService.isModelInstalled(model) {
                                Label("Installed", systemImage: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption2)

                                Button("Update") {
                                    Task { await ollamaService.updateModel(model) }
                                }
                                .font(.caption2)
                                .buttonStyle(.borderless)
                                .disabled(ollamaService.isPulling)
                            } else {
                                Button("Download") {
                                    Task {
                                        if await ollamaService.pullModel(model) {
                                            loadRefinementModels()
                                        }
                                    }
                                }
                                .font(.caption2)
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(ollamaService.isPulling)
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    if ollamaService.isPulling {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text(ollamaService.pullProgress)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    if let error = ollamaService.pullError {
                        Text(error)
                            .font(.caption2)
                            .foregroundColor(.red)
                    }

                    Button("Keep Model Loaded") {
                        Task { await ollamaService.keepModelLoaded(settings.refinementModel) }
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                    .padding(.top, 4)
                }
            }
        }
        .disabled(settings.skipRefinement || settings.transcriptionProvider.supportsRefinementInOneCall)
        .onChange(of: settings.ollamaBaseURL) { _, _ in
            Task { await ollamaService.checkOllamaStatus() }
        }
    }
}
