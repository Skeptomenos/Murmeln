import SwiftUI

struct TranscriptionSettingsSection: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var whisperKitService: WhisperKitService

    @Binding var showingWhisperKitSetup: Bool
    @Binding var transcriptionModels: [ModelInfo]
    @Binding var isLoadingTranscriptionModels: Bool

    let loadTranscriptionModels: () -> Void

    @State private var apiKeyDraft = ""
    @FocusState private var apiKeyFocused: Bool

    static func showsWhisperKitVariantManagement(
        for selection: AppSettings.TranscriptionSelection
    ) -> Bool {
        switch selection {
        case .catalog(let modelID):
            return modelID == .whisperKit
        case .legacy(let provider):
            return provider == .whisperKit
        }
    }

    private func commitAPIKey() {
        let previous = settings.transcriptionAPIKey
        guard apiKeyDraft != previous else { return }
        settings.transcriptionAPIKey = apiKeyDraft
        if AppSettings.shouldTriggerModelDiscovery(committedKey: apiKeyDraft, previousKey: previous) {
            loadTranscriptionModels()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsGroup(title: "Speech recognition", subtitle: "Run transcription on this Mac, or connect a cloud service.") {
                // Keep the existing selection setter as the only path that
                // updates provider values and model change signals.
                Picker("Model", selection: Binding(
                    get: { settings.transcriptionSelection },
                    set: { settings.transcriptionSelection = $0 }
                )) {
                    Section("On-Device") {
                        ForEach(ModelCatalog.entries, id: \.id) { entry in
                            Text(entry.displayName)
                                .tag(AppSettings.TranscriptionSelection.catalog(entry.id))
                        }
                    }
                    Section("Cloud & Server") {
                        ForEach(TranscriptionProvider.allCases.filter { !$0.isLocalNativeProvider },
                                id: \.rawValue) { provider in
                            Text(provider.supportsRefinementInOneCall ? "\(provider.displayName) + Refinement" : provider.displayName)
                                .tag(AppSettings.TranscriptionSelection.legacy(provider))
                        }
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: settings.transcriptionProviderRaw) { _, _ in
                    loadTranscriptionModels()
                }

                if case .catalog = settings.transcriptionSelection {
                    SettingsNote(text: "Speech recognition runs on this Mac.", icon: "laptopcomputer")
                }

                if settings.selectedModelID == nil, settings.transcriptionProvider.supportsRefinementInOneCall {
                    SettingsNote(text: "This provider handles final text in one call. Separate refinement settings are ignored.", icon: "sparkles")
                }
            }

            if case .catalog(let modelID) = settings.transcriptionSelection,
               let entry = ModelCatalog.entry(for: modelID) {
                CatalogModelSection(settings: settings, entry: entry)
                    .id(modelID)
            }

            if Self.showsWhisperKitVariantManagement(for: settings.transcriptionSelection) {
                WhisperKitSettingsSection(
                    settings: settings,
                    whisperKitService: whisperKitService,
                    showingWhisperKitSetup: $showingWhisperKitSetup,
                    showsLegacyDecodingSettings: settings.selectedModelID == nil
                )
            }

            if settings.selectedModelID == nil, !settings.transcriptionProvider.isLocalNativeProvider {
                SettingsGroup(title: "Cloud & server") {
                    if settings.transcriptionProvider.requiresAPIKey {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("API key")
                                .font(.caption.weight(.medium))
                            // M5: persist and discover models only on Enter or
                            // focus loss, never for each keystroke.
                            SecureField("Enter API key", text: $apiKeyDraft)
                                .textFieldStyle(.roundedBorder)
                                .focused($apiKeyFocused)
                                .onSubmit { commitAPIKey() }
                                .onChange(of: apiKeyFocused) { _, focused in
                                    if !focused { commitAPIKey() }
                                }
                                .onAppear { apiKeyDraft = settings.transcriptionAPIKey }
                                .onChange(of: settings.transcriptionProviderRaw) { _, _ in
                                    apiKeyDraft = settings.transcriptionAPIKey
                                }
                                .accessibilityLabel("Transcription API key")
                            KeychainSecurityNoticeBanner(settings: settings)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Model")
                            .font(.caption.weight(.medium))
                        HStack(spacing: 10) {
                            if isLoadingTranscriptionModels {
                                ProgressView()
                                    .controlSize(.small)
                                    .accessibilityLabel("Loading transcription models")
                            }

                            if transcriptionModels.isEmpty {
                                TextField("Model name", text: $settings.transcriptionModel)
                                    .textFieldStyle(.roundedBorder)
                                    .accessibilityLabel("Transcription model name")
                            } else {
                                Picker("Transcription model", selection: $settings.transcriptionModel) {
                                    ForEach(transcriptionModels) { model in
                                        Text(model.name).tag(model.id)
                                    }
                                }
                                .labelsHidden()
                            }

                            Button(action: loadTranscriptionModels) {
                                Image(systemName: "arrow.clockwise")
                            }
                            .help("Refresh transcription models")
                            .accessibilityLabel("Refresh transcription models")
                        }
                        if transcriptionModels.isEmpty && !isLoadingTranscriptionModels {
                            Text("Enter a model name, or refresh to load available models.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()
                    DisclosureGroup("Server connection") {
                        ValidatedURLField(title: "Base URL", url: $settings.transcriptionBaseURL)
                            .padding(.top, 12)
                    }
                    if !URLValidation.isValid(settings.transcriptionBaseURL) {
                        SettingsNote(text: "The server URL is invalid. Open Server connection to correct it.", icon: "exclamationmark.circle", color: .red)
                    }
                }
            }
        }
        .onAppear { loadTranscriptionModels() }
        .sheet(isPresented: $showingWhisperKitSetup) {
            WhisperKitSetupView()
        }
    }
}
