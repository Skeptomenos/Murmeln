# Spec 012: Support Remote Ollama Instances

## Problem Description

The Ollama service hardcodes `localhost:11434`, preventing users from connecting to Ollama running on a different machine (home server, cloud instance).

### Current Implementation

```swift
// OllamaService.swift:22, 41, 53, 103
let url = URL(string: "http://localhost:11434/api/tags")!
let url = URL(string: "http://localhost:11434/api/pull")!
let url = URL(string: "http://localhost:11434/api/generate")!
```

### User Impact

- Cannot use Ollama on a home server
- Cannot use Ollama in Docker on a different port
- Cannot use cloud-hosted Ollama instances
- Contradicts "Bring Your Own API" philosophy

## Expected Behavior

- Ollama URL configurable in Settings
- Default to `http://localhost:11434`
- Validate URL format before saving
- Show connection status for remote instances

## Acceptance Criteria

- [ ] Add `ollamaBaseURL` setting to AppSettings
- [ ] Add URL input field in Settings → Refinement (when Ollama selected)
- [ ] Replace hardcoded URLs with setting value
- [ ] Validate URL format on input
- [ ] Test connection when URL changes
- [ ] Handle connection failures gracefully

## Technical Notes

**Files to modify:**
- `Sources/Models/AppSettings.swift`
- `Sources/Services/OllamaService.swift`
- `Sources/Views/SettingsView.swift`

**AppSettings addition:**
```swift
@AppStorage("ollamaBaseURL") var ollamaBaseURL = "http://localhost:11434"
```

**OllamaService refactor:**
```swift
private var baseURL: String {
    AppSettings.shared.ollamaBaseURL.trimmingCharacters(in: .whitespaces)
        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
}

func checkOllamaStatus() async {
    guard let url = URL(string: "\(baseURL)/api/tags") else {
        isOllamaRunning = false
        return
    }
    // ... rest of implementation
}
```

**SettingsView addition:**
```swift
if settings.refinementProvider == .ollama {
    TextField("Ollama URL", text: $settings.ollamaBaseURL)
        .textFieldStyle(.roundedBorder)
        .onSubmit {
            Task { await OllamaService.shared.checkOllamaStatus() }
        }
    
    if OllamaService.shared.isOllamaRunning {
        Label("Connected", systemImage: "checkmark.circle.fill")
            .foregroundColor(.green)
    } else {
        Label("Not connected", systemImage: "xmark.circle.fill")
            .foregroundColor(.red)
    }
}
```

**Severity:** Low

**Impact:** Flexibility, power user feature

**Effort:** Low (1 hour)

**Success Confidence:** 95%
