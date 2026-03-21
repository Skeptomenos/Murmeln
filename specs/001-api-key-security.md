# Spec 001: Secure API Key Storage

## Problem Description

API keys are stored in plain text in `UserDefaults`, which writes to a `.plist` file readable by any process with access to the user's home directory.

### Current Implementation

```swift
// AppSettings.swift:206, 212
private func getAPIKey(for providerRaw: String, isTranscription: Bool) -> String {
    let key = "\(prefix)APIKey_\(providerRaw)"
    return UserDefaults.standard.string(forKey: key) ?? ""
}

private func setAPIKey(_ value: String, for providerRaw: String, isTranscription: Bool) {
    let key = "\(prefix)APIKey_\(providerRaw)"
    UserDefaults.standard.set(value, forKey: key)
}
```

### Security Risk

- API keys are stored in `~/Library/Preferences/com.murmeln.plist`
- Any malware or script with file access can read these keys
- Keys could be exposed in Time Machine backups
- Potential for unauthorized API usage and billing fraud

## Expected Behavior

API keys should be stored in the macOS Keychain, which provides:
- Encryption at rest
- Access control per-application
- Secure deletion
- No exposure in backups

## Acceptance Criteria

- [ ] Create `KeychainService` using Security framework
- [ ] Migrate API key storage from UserDefaults to Keychain
- [ ] Handle migration of existing keys on first launch after update
- [ ] Provide fallback/error handling if Keychain access fails
- [ ] Remove old UserDefaults keys after successful migration
- [ ] Verify keys are not logged or exposed in error messages

## Technical Notes

**Files to modify:**
- `Sources/Models/AppSettings.swift` - Replace UserDefaults with KeychainService
- Create new `Sources/Services/KeychainService.swift`

**Implementation approach:**
```swift
import Security

final class KeychainService {
    static func save(key: String, value: String) throws {
        let data = value.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }
    
    static func retrieve(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
```

**Severity:** Critical

**Impact:** Security, user trust, potential financial liability

**Effort:** Medium (2-4 hours)

**Success Confidence:** 95%
