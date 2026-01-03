import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    
    @State private var transcriptionModels: [ModelInfo] = []
    @State private var refinementModels: [ModelInfo] = []
    @State private var isLoadingTranscriptionModels = false
    @State private var isLoadingRefinementModels = false
    
    var body: some View {
        TabView {
            transcriptionSettingsTab
                .tabItem {
                    Label("Transcription", systemImage: "waveform")
                }
            
            refinementSettingsTab
                .tabItem {
                    Label("Refinement", systemImage: "sparkles")
                }
            
            promptSettingsTab
                .tabItem {
                    Label("Prompt", systemImage: "text.quote")
                }
            
            recordingSettingsTab
                .tabItem {
                    Label("Recording", systemImage: "mic")
                }
        }
        .padding()
        .frame(width: 500, height: 400)
    }
    
    private var transcriptionSettingsTab: some View {
        Form {
            Section {
                Picker("Provider", selection: $settings.transcriptionProviderRaw) {
                    ForEach(TranscriptionProvider.allCases, id: \.rawValue) { provider in
                        Text(provider.rawValue).tag(provider.rawValue)
                    }
                }
                .onChange(of: settings.transcriptionProviderRaw) { _, newValue in
                    if let provider = TranscriptionProvider(rawValue: newValue) {
                        settings.transcriptionBaseURL = provider.defaultBaseURL
                        settings.transcriptionModel = provider.defaultModel
                    }
                    loadTranscriptionModels()
                }
                
                if settings.transcriptionProvider.requiresAPIKey {
                    SecureField("API Key", text: $settings.transcriptionAPIKey)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: settings.transcriptionAPIKey) { _, _ in
                            loadTranscriptionModels()
                        }
                }
                
                TextField("Base URL", text: $settings.transcriptionBaseURL)
                    .textFieldStyle(.roundedBorder)
                
                HStack {
                    if isLoadingTranscriptionModels {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                    
                    if transcriptionModels.isEmpty {
                        TextField("Model", text: $settings.transcriptionModel)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        Picker("Model", selection: $settings.transcriptionModel) {
                            ForEach(transcriptionModels) { model in
                                Text(model.name).tag(model.id)
                            }
                        }
                    }
                    
                    Button(action: loadTranscriptionModels) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh models")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { loadTranscriptionModels() }
    }
    
    private var refinementSettingsTab: some View {
        Form {
            Section {
                Picker("Provider", selection: $settings.refinementProviderRaw) {
                    ForEach(Provider.allCases, id: \.rawValue) { provider in
                        Text(provider.rawValue).tag(provider.rawValue)
                    }
                }
                .onChange(of: settings.refinementProviderRaw) { _, newValue in
                    if let provider = Provider(rawValue: newValue) {
                        settings.refinementBaseURL = provider.defaultBaseURL
                    }
                    loadRefinementModels()
                }
                
                if settings.refinementProvider.requiresAPIKey {
                    SecureField("API Key", text: $settings.refinementAPIKey)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: settings.refinementAPIKey) { _, _ in
                            loadRefinementModels()
                        }
                }
                
                TextField("Base URL", text: $settings.refinementBaseURL)
                    .textFieldStyle(.roundedBorder)
                
                HStack {
                    if isLoadingRefinementModels {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                    
                    if refinementModels.isEmpty {
                        TextField("Model", text: $settings.refinementModel)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        Picker("Model", selection: $settings.refinementModel) {
                            ForEach(refinementModels) { model in
                                Text(model.name).tag(model.id)
                            }
                        }
                    }
                    
                    Button(action: loadRefinementModels) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh models")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { loadRefinementModels() }
    }
    
    private var promptSettingsTab: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("System Prompt")
                        .font(.headline)
                    
                    Text("Instructions for refining and formatting the transcribed text.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextEditor(text: $settings.systemPrompt)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 200)
                        .padding(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                    
                    Button("Reset to Default") {
                        settings.systemPrompt = "You are a transcription refiner. Clean up the following speech-to-text input. Remove filler words, fix grammar, and structure it as clear, professional text or a concise command. Output ONLY the refined text."
                    }
                    .buttonStyle(.link)
                }
            }
        }
        .formStyle(.grouped)
    }
    
    private var recordingSettingsTab: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: $settings.highQualityAudio) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("High Quality Audio")
                                .font(.headline)
                            Text(settings.highQualityAudio ? "44.1 kHz · Larger files · Slower upload" : "16 kHz · Optimized for speech · Faster processing")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Recommended Settings", systemImage: "lightbulb")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.orange)
                        
                        Text("16 kHz is optimal for speech recognition APIs. Use high quality only if you experience transcription issues.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .formStyle(.grouped)
    }
    
    private func loadTranscriptionModels() {
        isLoadingTranscriptionModels = true
        Task {
            let models = await ModelDiscoveryService.shared.fetchTranscriptionModels(
                provider: settings.transcriptionProvider,
                apiKey: settings.transcriptionAPIKey,
                baseURL: settings.transcriptionBaseURL
            )
            await MainActor.run {
                transcriptionModels = models
                if !models.isEmpty && !models.contains(where: { $0.id == settings.transcriptionModel }) {
                    settings.transcriptionModel = models.first?.id ?? ""
                }
                isLoadingTranscriptionModels = false
            }
        }
    }
    
    private func loadRefinementModels() {
        isLoadingRefinementModels = true
        Task {
            let models = await ModelDiscoveryService.shared.fetchModels(
                provider: settings.refinementProvider,
                apiKey: settings.refinementAPIKey,
                baseURL: settings.refinementBaseURL
            )
            await MainActor.run {
                refinementModels = models
                if !models.isEmpty && !models.contains(where: { $0.id == settings.refinementModel }) {
                    settings.refinementModel = models.first?.id ?? ""
                }
                isLoadingRefinementModels = false
            }
        }
    }
}
