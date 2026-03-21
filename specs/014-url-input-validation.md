# Spec 014: Add URL Input Validation in Settings

## Problem Description

Base URL fields in Settings accept any text without validation. Malformed URLs cause runtime errors during API calls with no clear indication of the cause.

### Current Behavior

1. User enters "not a url" in Base URL field
2. Setting is saved without validation
3. User tries to transcribe
4. `NetworkError.invalidURL` thrown
5. User sees generic error, doesn't connect it to the URL setting

### Affected Fields

- Transcription Base URL (`AppSettings.transcriptionBaseURL`)
- Refinement Base URL (`AppSettings.refinementBaseURL`)
- (Future) Ollama Base URL

## Expected Behavior

- Validate URL format on input
- Show visual feedback for invalid URLs (red border, warning icon)
- Prevent saving invalid URLs
- Show helpful error message

## Acceptance Criteria

- [ ] Add URL validation helper function
- [ ] Show validation state in UI (valid/invalid indicator)
- [ ] Prevent form submission with invalid URLs
- [ ] Add helpful hint text for URL format
- [ ] Test with various invalid inputs (spaces, missing scheme, etc.)

## Technical Notes

**Files to modify:**
- `Sources/Views/SettingsView.swift`

**Implementation:**
```swift
struct ValidatedURLField: View {
    let title: String
    @Binding var url: String
    
    private var isValid: Bool {
        guard let url = URL(string: url.trimmingCharacters(in: .whitespaces)) else {
            return false
        }
        return url.scheme == "http" || url.scheme == "https"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField(title, text: $url)
                    .textFieldStyle(.roundedBorder)
                
                if !url.isEmpty {
                    Image(systemName: isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(isValid ? .green : .red)
                }
            }
            
            if !url.isEmpty && !isValid {
                Text("Enter a valid URL starting with http:// or https://")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }
}

// Usage:
ValidatedURLField(title: "Base URL", url: $settings.transcriptionBaseURL)
```

**Validation rules:**
- Must start with `http://` or `https://`
- Must be parseable by `URL(string:)`
- Should not end with `/` (normalize on save)
- Should not contain spaces (trim on save)

**Severity:** Low

**Impact:** User experience, error clarity

**Effort:** Low (1 hour)

**Success Confidence:** 95%
