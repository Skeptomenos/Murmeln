# Spec 005: Swift 6 Concurrency Safety Audit

## Problem Description

While the codebase uses Swift 6 and declares strict concurrency compliance, there are several potential issues and anti-patterns that could lead to data races or unexpected behavior:

### Identified Issues:

1. **NetworkService singleton access pattern** (`NetworkService.swift:18`):
   ```swift
   @MainActor static let shared = NetworkService()
   ```
   The class is declared `Sendable` but the singleton accessor is `@MainActor`. This is unusual - typically you'd want either the class to be an actor OR the singleton to not be main actor bound.

2. **AudioRecorder tap callback crosses isolation** (`AudioService.swift:85-122`):
   ```swift
   node.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { [weak self] buffer, _ in
       guard let self else { return }
       // ... file operations inside non-isolated callback
       Task {
           await self.sendLevel(level)
       }
   }
   ```
   The tap callback runs on the audio thread, but file writes (`try? file.write(from: outputBuffer)`) happen synchronously in that callback while `file` is owned by the actor.

3. **DispatchQueue.main.asyncAfter in PasteService** (`PasteService.swift:13-15`):
   ```swift
   DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
       self.simulatePasteViaCGEvent()
   }
   ```
   Using GCD in a `Sendable` class. The closure captures `self` without explicit Sendable handling.

4. **DispatchWorkItem in HotkeyService** (`HotkeyService.swift:68-78`):
   ```swift
   let work = DispatchWorkItem { [weak self] in
       Task { @MainActor in
           guard let self else { return }
           // ...
       }
   }
   ```
   While this works, the pattern of DispatchWorkItem -> Task -> MainActor is complex and error-prone.

5. **Callback closures stored as properties** (`HotkeyService.swift:21-26`):
   ```swift
   var onKeyDown: (() -> Void)?
   var onKeyUp: (() -> Void)?
   // ...
   ```
   These closures are mutable and accessed from different contexts. In Swift 6 strict concurrency, these should be `@Sendable` or the service should be an actor.

6. **ObservableObject with @Published in actors** (`OllamaService.swift:4-10`, `UpdateService.swift:5-12`):
   These classes are `@MainActor` singletons using `@Published` which is correct, but the pattern is inconsistent with other services.

7. **Potential race in async callback pattern** (`AppState.swift:160-186`):
   The `withTaskGroup` pattern is correct, but the `variants` and `variantPrompts` dictionaries are mutated in the `for await` loop. While this is safe because the loop is sequential, it's worth adding comments explaining this.

## Current Behavior

The code compiles with Swift 6 strict concurrency, but some patterns are fragile and may break with future Swift updates or under edge conditions.

## Expected Behavior

All concurrency patterns should be:
- Explicit about isolation requirements
- Using modern async/await patterns consistently
- Free of potential data races
- Well-documented where complex patterns are necessary

## Acceptance Criteria

- [ ] Audit `NetworkService` singleton pattern - consider making it an actor or removing `@MainActor` from singleton
- [ ] Review `AudioRecorder` tap callback - ensure file writes are safe (actor re-entrancy)
- [ ] Replace `DispatchQueue.main.asyncAfter` with `Task.sleep` pattern where possible
- [ ] Simplify `HotkeyService` DispatchWorkItem pattern
- [ ] Mark callback closures as `@Sendable` where appropriate
- [ ] Add documentation comments explaining complex concurrency patterns
- [ ] Run with `-strict-concurrency=complete` and fix any warnings
- [ ] Consider extracting mutable state into actors where shared across boundaries
- [ ] Add concurrency-focused tests using Swift Testing's async testing features

## Technical Notes

**Key files:**
- `Sources/Services/NetworkService.swift`
- `Sources/Services/AudioService.swift`
- `Sources/Services/PasteService.swift`
- `Sources/Services/HotkeyService.swift`
- `Sources/Models/AppState.swift`

**Swift 6 Concurrency resources:**
- Actor isolation rules
- Sendable protocol requirements
- MainActor inference rules

**Compiler flags for stricter checking:**
```swift
// Package.swift
swiftSettings: [
    .enableExperimentalFeature("StrictConcurrency")
]
```

**Severity:** Medium (code works but patterns are fragile)

**Impact:** Long-term maintainability, future Swift version compatibility, potential subtle bugs
