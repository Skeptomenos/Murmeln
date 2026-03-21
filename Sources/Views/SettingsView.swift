import SwiftUI

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }
    
    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            
            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            totalHeight = currentY + lineHeight
        }
        
        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}

// MARK: - URL Validation

/// Validates and normalizes URL strings for API base URLs
enum URLValidation {
    /// Validation result with normalized URL or error message
    enum Result {
        case valid(normalized: String)
        case invalid(reason: String)
        case empty
    }
    
    /// Validates a URL string for use as an API base URL
    /// - Parameter urlString: The URL string to validate
    /// - Returns: Validation result with normalized URL or error
    static func validate(_ urlString: String) -> Result {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty else {
            return .empty
        }
        
        guard let url = URL(string: trimmed) else {
            return .invalid(reason: "Invalid URL format")
        }
        
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return .invalid(reason: "URL must start with http:// or https://")
        }
        
        guard url.host != nil else {
            return .invalid(reason: "URL must include a host")
        }
        
        // Normalize: remove trailing slash
        var normalized = trimmed
        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        
        return .valid(normalized: normalized)
    }
    
    /// Quick check if URL is valid (for UI state)
    static func isValid(_ urlString: String) -> Bool {
        switch validate(urlString) {
        case .valid, .empty:
            return true
        case .invalid:
            return false
        }
    }
}

/// A text field with real-time URL validation feedback
struct ValidatedURLField: View {
    let title: String
    @Binding var url: String
    var placeholder: String = "https://..."
    
    private var validationResult: URLValidation.Result {
        URLValidation.validate(url)
    }
    
    private var isValid: Bool {
        switch validationResult {
        case .valid, .empty:
            return true
        case .invalid:
            return false
        }
    }
    
    private var errorMessage: String? {
        switch validationResult {
        case .invalid(let reason):
            return reason
        case .valid, .empty:
            return nil
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.medium))
            
            HStack {
                TextField(placeholder, text: $url)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: url) { _, newValue in
                        // Auto-normalize on paste or when user finishes typing
                        // We normalize when the field loses focus via onSubmit
                    }
                    .onSubmit {
                        normalizeURL()
                    }
                
                if !url.isEmpty {
                    Image(systemName: isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(isValid ? .green : .red)
                        .accessibilityLabel(isValid ? "Valid URL" : "Invalid URL")
                }
            }
            
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .accessibilityLabel("Error: \(error)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title) URL field")
        .accessibilityValue(url.isEmpty ? "Empty" : (isValid ? "Valid: \(url)" : "Invalid"))
    }
    
    private func normalizeURL() {
        if case .valid(let normalized) = validationResult {
            if normalized != url {
                url = normalized
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var ollamaService = OllamaService.shared
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
                .accessibilityLabel("\(tab.rawValue) settings")
                .accessibilityHint(accessibilityHintForTab(tab))
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
            
            Spacer()
            
            pipelineInfo
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings navigation")
    }
    
    private func accessibilityHintForTab(_ tab: SettingsTab) -> String {
        switch tab {
        case .transcription:
            return "Configure speech-to-text provider"
        case .refinement:
            return "Configure text cleanup and formatting"
        case .prompt:
            return "Manage prompt presets and personal dictionary"
        case .recording:
            return "Configure audio capture settings"
        }
    }
    
    private var pipelineInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            
            Text("Current Pipeline")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            
            if settings.skipRefinement {
                Label {
                    Text("Raw Mode")
                        .font(.caption)
                } icon: {
                    Image(systemName: "waveform")
                        .foregroundColor(.orange)
                }
                
                Text("Transcription only, no LLM refinement")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else if settings.transcriptionProvider.supportsRefinementInOneCall {
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
                    .accessibilityAddTraits(.isHeader)
                Text("Speech-to-text provider for converting audio to text")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .accessibilityElement(children: .combine)
            
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
                
                ValidatedURLField(title: "Base URL", url: $settings.transcriptionBaseURL)
                
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
                    .accessibilityAddTraits(.isHeader)
                Text("LLM provider for cleaning up and formatting transcribed text")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .accessibilityElement(children: .combine)
            
            Toggle(isOn: $settings.skipRefinement) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Skip Refinement (Raw Mode)")
                        .font(.body.weight(.medium))
                    Text("Use original transcript without LLM processing")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.switch)
            .padding(12)
            .background(settings.skipRefinement ? Color.orange.opacity(0.15) : Color.clear)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(settings.skipRefinement ? Color.orange.opacity(0.5) : Color.clear, lineWidth: 1)
            )
            .accessibilityLabel("Skip Refinement")
            .accessibilityValue(settings.skipRefinement ? "On, raw mode enabled" : "Off, LLM refinement active")
            .accessibilityHint("Toggle to use original transcript without LLM processing")
            
            Toggle(isOn: $settings.disableSilenceTrimming) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Disable Silence Trimming")
                        .font(.body.weight(.medium))
                    Text("Send full audio without trimming silence from start/end")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.switch)
            .padding(12)
            .background(settings.disableSilenceTrimming ? Color.orange.opacity(0.15) : Color.clear)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(settings.disableSilenceTrimming ? Color.orange.opacity(0.5) : Color.clear, lineWidth: 1)
            )
            
            if settings.transcriptionProvider.supportsRefinementInOneCall && !settings.skipRefinement {
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
                .disabled(settings.skipRefinement || settings.transcriptionProvider.supportsRefinementInOneCall)
                .opacity(settings.skipRefinement || settings.transcriptionProvider.supportsRefinementInOneCall ? 0.5 : 1)
                
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
                    .disabled(settings.skipRefinement || settings.transcriptionProvider.supportsRefinementInOneCall)
                    .opacity(settings.skipRefinement || settings.transcriptionProvider.supportsRefinementInOneCall ? 0.5 : 1)
                }
                
                ValidatedURLField(title: "Base URL", url: $settings.refinementBaseURL)
                    .disabled(settings.skipRefinement || settings.transcriptionProvider.supportsRefinementInOneCall)
                    .opacity(settings.skipRefinement || settings.transcriptionProvider.supportsRefinementInOneCall ? 0.5 : 1)
                
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
                .disabled(settings.skipRefinement || settings.transcriptionProvider.supportsRefinementInOneCall)
                .opacity(settings.skipRefinement || settings.transcriptionProvider.supportsRefinementInOneCall ? 0.5 : 1)
                
                if settings.refinementProvider == .ollama {
                    ollamaManagementSection
                }
            }
        }
        .onAppear { 
            loadRefinementModels()
            if settings.refinementProvider == .ollama {
                Task { await ollamaService.checkOllamaStatus() }
            }
        }
    }
    
    @State private var showingAddPreset = false
    @State private var newPresetName = ""
    @State private var newPresetDescription = ""
    @State private var editingPrompt = ""
    @State private var newDictionaryWord = ""
    
    @ViewBuilder
    private var ollamaManagementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            
            ValidatedURLField(title: "Ollama URL", url: $settings.ollamaBaseURL)
                .onChange(of: settings.ollamaBaseURL) { _, _ in
                    Task { await ollamaService.checkOllamaStatus() }
                }
            
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
                .buttonStyle(.borderless)
            }
            
            if !ollamaService.isOllamaRunning {
                Text("To start Ollama: brew install ollama && ollama serve")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
            
            if ollamaService.isOllamaRunning {
                VStack(alignment: .leading, spacing: 8) {
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
                .padding(10)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .disabled(settings.skipRefinement || settings.transcriptionProvider.supportsRefinementInOneCall)
        .opacity(settings.skipRefinement || settings.transcriptionProvider.supportsRefinementInOneCall ? 0.5 : 1)
    }
    
    private var promptContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Prompt Presets")
                    .font(.title2.weight(.semibold))
                
                Spacer()
                
                Toggle(isOn: $settings.parallelRefinementEnabled) {
                    Label("Parallel Audit", systemImage: "bolt.horizontal.circle")
                        .font(.caption.weight(.medium))
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .help("Process all presets in parallel for the history audit trail")
                
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
            
            personalDictionarySection
        }
        .sheet(isPresented: $showingAddPreset) {
            addPresetSheet
        }
    }
    
    private var personalDictionarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
                .padding(.top, 8)
            
            Toggle(isOn: $settings.personalDictionaryEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Personal Dictionary")
                        .font(.body.weight(.medium))
                    Text("Teach the refiner how to spell names and terms")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.switch)
            .accessibilityLabel("Personal Dictionary")
            .accessibilityValue(settings.personalDictionaryEnabled ? "On, \(settings.personalDictionary.count) words" : "Off")
            .accessibilityHint("Toggle to enable custom spelling for names and terms")
            
            if settings.personalDictionaryEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("Add name or term...", text: $newDictionaryWord)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                addDictionaryWord()
                            }
                        
                        Button {
                            addDictionaryWord()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .disabled(newDictionaryWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    
                    if settings.personalDictionary.isEmpty {
                        Text("No words added yet. Add names, technical terms, or brand names that are often misspelled.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        FlowLayout(spacing: 6) {
                            ForEach(settings.personalDictionary, id: \.self) { word in
                                HStack(spacing: 4) {
                                    Text(word)
                                        .font(.caption)
                                    Button {
                                        settings.removeFromDictionary(word)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.15))
                                .cornerRadius(12)
                            }
                        }
                    }
                    
                    Text("\(settings.personalDictionary.count)/20 words")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
            }
        }
    }
    
    private func addDictionaryWord() {
        let trimmed = newDictionaryWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        settings.addToDictionary(trimmed)
        newDictionaryWord = ""
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
                    .accessibilityAddTraits(.isHeader)
                Text("Audio capture settings")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .accessibilityElement(children: .combine)
            
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
                .accessibilityLabel("High Quality Audio")
                .accessibilityValue(settings.highQualityAudio ? "On, 44.1 kHz" : "Off, 16 kHz optimized")
                .accessibilityHint("Toggle between high quality 44.1 kHz and optimized 16 kHz recording")
                
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
