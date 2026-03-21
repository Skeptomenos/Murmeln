# Spec 004: Move Gemini API Key to Header

## Problem Description

The Gemini API key is passed as a URL query parameter, which exposes it in logs, network monitors, and proxy servers.

### Current Implementation

```swift
// NetworkService.swift:188, 288
let url = URL(string: "\(baseURL)/models/\(model):generateContent?key=\(apiKey)")
```

### Security Risk

- Query parameters are logged by:
  - macOS Console/system logs
  - Corporate proxy servers
  - Network debugging tools (Charles, Proxyman)
  - Browser developer tools (if debugging)
- API keys in URLs may appear in crash reports
- URLs are often cached or stored in history

## Expected Behavior

API keys should be passed via HTTP headers, which are:
- Not logged by default in most systems
- Encrypted in transit (HTTPS)
- Not cached in URL history

## Acceptance Criteria

- [ ] Research if Gemini API supports header-based authentication
- [ ] If supported: Move API key to `x-goog-api-key` header
- [ ] If not supported: Ensure URL is never logged (remove from error messages)
- [ ] Update error sanitization to strip API keys from any error output
- [ ] Verify no API keys appear in console logs during normal operation

## Technical Notes

**Files to modify:**
- `Sources/Services/NetworkService.swift`

**Gemini API header authentication:**
```swift
// If Gemini supports header auth:
var request = URLRequest(url: URL(string: "\(baseURL)/models/\(model):generateContent")!)
request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
```

**Fallback - sanitize URLs in errors:**
```swift
private func sanitizeURL(_ url: URL) -> String {
    var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    components?.queryItems?.removeAll { $0.name == "key" }
    return components?.string ?? url.absoluteString
}
```

**Severity:** High

**Impact:** API key exposure, security

**Effort:** Low (30 minutes)

**Success Confidence:** 95%
