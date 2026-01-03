import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var selectedTab: SettingsTab = .transcription
    
    @State private var transcriptionModels: [ModelInfo] = []
    @State private var refinementModels: [ModelInfo] = []
    @State private var isLoadingTranscriptionModels = false
    @State private var isLoadingRefinementModels = false
    
    enum SettingsTab: String, CaseIterable {
        case transcription = "Transcription"
        case refinement = "Refinement"
        case prompt = "Prompt"
        case recording = "Recording"
        
        var icon: String {
            switch self {
            case .transcription: return "waveform"
            case .refinement: return "sparkles"
            case .prompt: return "text.quote"
            case .recording: return "mic"
            }
        }
    }
    
    var body: some View {
        HSplitView {
            sidebar
                .frame(width: 180)
            
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 650, height: 500)
    }
    
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: tab.icon)
                            .frame(width: 20)
                        Text(tab.rawValue)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(selectedTab == tab ? Color.accentColor.opacity(0.2) : Color.clear)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
            
            pipelineInfo
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    private var pipelineInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            
            Text("Current Pipeline")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            
            if settings.transcriptionProvider.supportsRefinementInOneCall {
                Label {
                    Text("1 API Call")
                        .font(.caption)
                } icon: {
                    Image(systemName: "bolt.fill")
                        .foregroundColor(.green)
                }
                
                Text("\(settings.transcriptionProvider.rawValue) handles both transcription and refinement")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                Label {
                    Text("2 API Calls")
                        .font(.caption)
                } icon: {
                    Image(systemName: "arrow.triangle.branch")
                        .foregroundColor(.orange)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("1. \(settings.transcriptionProvider.rawValue)")
                        .font(.caption2)
                    Text("2. \(settings.refinementProvider.rawValue)")
                        .font(.caption2)
                }
                .foregroundColor(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch selectedTab {
                case .transcription:
                    transcriptionContent
                case .refinement:
                    refinementContent
                case .prompt:
                    promptContent
                case .recording:
                    recordingContent
                }
            }
            .padding(20)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
    
    private var transcriptionContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Transcription")
                    .font(.title2.weight(.semibold))
                Text("Speech-to-text provider for converting audio to text")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Picker("Provider", selection: $settings.transcriptionProviderRaw) {
                    ForEach(TranscriptionProvider.allCases, id: \.rawValue) { provider in
                        HStack {
                            Text(provider.rawValue)
                            if provider.supportsRefinementInOneCall {
                                Text("+ Refinement")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                        .tag(provider.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: settings.transcriptionProviderRaw) { _, newValue in
                    if let provider = TranscriptionProvider(rawValue: newValue) {
                        settings.transcriptionBaseURL = provider.defaultBaseURL
                        settings.transcriptionModel = provider.defaultModel
                    }
                    loadTranscriptionModels()
                }
                
                if settings.transcriptionProvider.supportsRefinementInOneCall {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .foregroundColor(.green)
                        Text("This provider does transcription + refinement in one call. Refinement settings are ignored.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(10)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                }
                
                if settings.transcriptionProvider.requiresAPIKey {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("API Key")
                            .font(.caption.weight(.medium))
                        SecureField("Enter API key", text: $settings.transcriptionAPIKey)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: settings.transcriptionAPIKey) { _, _ in
                                loadTranscriptionModels()
                            }
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Base URL")
                        .font(.caption.weight(.medium))
                    TextField("https://...", text: $settings.transcriptionBaseURL)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Model")
                        .font(.caption.weight(.medium))
                    HStack {
                        if isLoadingTranscriptionModels {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                        
                        if transcriptionModels.isEmpty {
                            TextField("Model name", text: $settings.transcriptionModel)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            Picker("", selection: $settings.transcriptionModel) {
                                ForEach(transcriptionModels) { model in
                                    Text(model.name).tag(model.id)
                                }
                            }
                            .labelsHidden()
                        }
                        
                        Button(action: loadTranscriptionModels) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .onAppear { loadTranscriptionModels() }
    }
    
    private var refinementContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Refinement")
                    .font(.title2.weight(.semibold))
                Text("LLM provider for cleaning up and formatting transcribed text")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if settings.transcriptionProvider.supportsRefinementInOneCall {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.blue)
                        Text("Refinement is handled by your transcription provider")
                            .font(.callout.weight(.medium))
                    }
                    
                    Text("Since you're using \(settings.transcriptionProvider.rawValue), refinement happens in the same API call. These settings are only used if you switch to a transcription-only provider like OpenAI Whisper or Groq.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Picker("Provider", selection: $settings.refinementProviderRaw) {
                    ForEach(Provider.allCases, id: \.rawValue) { provider in
                        Text(provider.rawValue).tag(provider.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: settings.refinementProviderRaw) { _, newValue in
                    if let provider = Provider(rawValue: newValue) {
                        settings.refinementBaseURL = provider.defaultBaseURL
                    }
                    loadRefinementModels()
                }
                .disabled(settings.transcriptionProvider.supportsRefinementInOneCall)
                .opacity(settings.transcriptionProvider.supportsRefinementInOneCall ? 0.5 : 1)
                
                if settings.refinementProvider.requiresAPIKey {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("API Key")
                            .font(.caption.weight(.medium))
                        SecureField("Enter API key", text: $settings.refinementAPIKey)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: settings.refinementAPIKey) { _, _ in
                                loadRefinementModels()
                            }
                    }
                    .disabled(settings.transcriptionProvider.supportsRefinementInOneCall)
                    .opacity(settings.transcriptionProvider.supportsRefinementInOneCall ? 0.5 : 1)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Base URL")
                        .font(.caption.weight(.medium))
                    TextField("https://...", text: $settings.refinementBaseURL)
                        .textFieldStyle(.roundedBorder)
                }
                .disabled(settings.transcriptionProvider.supportsRefinementInOneCall)
                .opacity(settings.transcriptionProvider.supportsRefinementInOneCall ? 0.5 : 1)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Model")
                        .font(.caption.weight(.medium))
                    HStack {
                        if isLoadingRefinementModels {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                        
                        if refinementModels.isEmpty {
                            TextField("Model name", text: $settings.refinementModel)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            Picker("", selection: $settings.refinementModel) {
                                ForEach(refinementModels) { model in
                                    Text(model.name).tag(model.id)
                                }
                            }
                            .labelsHidden()
                        }
                        
                        Button(action: loadRefinementModels) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .disabled(settings.transcriptionProvider.supportsRefinementInOneCall)
                .opacity(settings.transcriptionProvider.supportsRefinementInOneCall ? 0.5 : 1)
            }
        }
        .onAppear { loadRefinementModels() }
    }
    
    @State private var showingAddPreset = false
    @State private var newPresetName = ""
    @State private var newPresetDescription = ""
    @State private var editingPrompt = ""
    
    private var promptContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Prompt Presets")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    showingAddPreset = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add custom preset")
            }
            
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Preset")
                        .font(.caption.weight(.medium))
                    
                    Picker("", selection: Binding(
                        get: { settings.selectedPreset },
                        set: { if let p = $0 { settings.selectedPreset = p } }
                    )) {
                        ForEach(settings.allPresets) { preset in
                            HStack {
                                Image(systemName: preset.icon)
                                Text(preset.name)
                                if settings.isPresetModified(preset) {
                                    Text("•").foregroundColor(.orange)
                                }
                            }
                            .tag(preset as PromptPreset?)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 200)
                }
                
                if let preset = settings.selectedPreset, !preset.isBuiltIn {
                    Button {
                        settings.deleteCustomPreset(preset)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                    .help("Delete preset")
                }
            }
            
            if let preset = settings.selectedPreset {
                Text(preset.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Prompt")
                        .font(.caption.weight(.medium))
                    
                    Spacer()
                    
                    if let preset = settings.selectedPreset, settings.isPresetModified(preset) {
                        Button("Reset") {
                            settings.resetPresetToDefault(preset)
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                    }
                }
                
                TextEditor(text: Binding(
                    get: { settings.systemPrompt },
                    set: { settings.systemPrompt = $0 }
                ))
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 120)
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
            }
        }
        .sheet(isPresented: $showingAddPreset) {
            addPresetSheet
        }
    }
    
    private var addPresetSheet: some View {
        VStack(spacing: 16) {
            Text("New Preset")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Name")
                    .font(.caption.weight(.medium))
                TextField("My Preset", text: $newPresetName)
                    .textFieldStyle(.roundedBorder)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Description")
                    .font(.caption.weight(.medium))
                TextField("Short description", text: $newPresetDescription)
                    .textFieldStyle(.roundedBorder)
            }
            
            HStack {
                Button("Cancel") {
                    showingAddPreset = false
                    newPresetName = ""
                    newPresetDescription = ""
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Add") {
                    settings.addCustomPreset(
                        name: newPresetName,
                        description: newPresetDescription,
                        icon: "star",
                        prompt: "Fix grammar and punctuation. Output only the cleaned text."
                    )
                    showingAddPreset = false
                    newPresetName = ""
                    newPresetDescription = ""
                }
                .keyboardShortcut(.return)
                .disabled(newPresetName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 300)
    }
    
    private var recordingContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Recording")
                    .font(.title2.weight(.semibold))
                Text("Audio capture settings")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 16) {
                Toggle(isOn: $settings.highQualityAudio) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("High Quality Audio")
                            .font(.body.weight(.medium))
                        Text(settings.highQualityAudio ? "44.1 kHz · Larger files · Slower upload" : "16 kHz · Optimized for speech · Faster processing")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)
                
                HStack(spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.orange)
                    Text("16 kHz is optimal for speech recognition. Use high quality only if you experience issues.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
        }
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
