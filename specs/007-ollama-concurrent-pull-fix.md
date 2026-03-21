# Spec 007: Fix Ollama Concurrent Model Pull Race Condition

## Problem Description

The `OllamaService` has an unused `pullTask` variable that was intended to prevent concurrent model pulls. Without proper task management, multiple simultaneous pulls cause UI flickering and incorrect progress display.

### Current Implementation

```swift
// OllamaService.swift:19
private var pullTask: Task<Void, Never>?  // Declared but NEVER USED

func pullModel(_ modelName: String) async -> Bool {
    isPulling = true
    pullProgress = "Starting download..."
    // ... no check for existing pull, no task assignment
}
```

### Bug Scenario

1. User clicks "Download" on Model A
2. Progress shows "Downloading Model A: 25%"
3. User clicks "Download" on Model B
4. Both downloads run concurrently
5. `pullProgress` flickers between "Model A: 30%" and "Model B: 5%"
6. `isPulling` state becomes inconsistent
7. User confusion about which model is downloading

## Expected Behavior

- Only one model pull at a time
- New pull request cancels existing pull (or is rejected)
- Clear UI indication of which model is downloading
- Proper cleanup on cancellation

## Acceptance Criteria

- [ ] Use `pullTask` to track active pull operation
- [ ] Cancel existing pull before starting new one (or reject new pull)
- [ ] Show which model is currently being pulled in UI
- [ ] Handle cancellation gracefully (cleanup progress state)
- [ ] Add test for concurrent pull prevention

## Technical Notes

**Files to modify:**
- `Sources/Services/OllamaService.swift`

**Fix:**
```swift
@MainActor
final class OllamaService: ObservableObject {
    private var pullTask: Task<Bool, Never>?
    @Published var currentlyPullingModel: String?
    
    func pullModel(_ modelName: String) async -> Bool {
        // Cancel existing pull
        if let existingTask = pullTask {
            existingTask.cancel()
            // Wait briefly for cleanup
            _ = await existingTask.value
        }
        
        currentlyPullingModel = modelName
        isPulling = true
        pullProgress = "Starting download..."
        
        pullTask = Task {
            defer {
                Task { @MainActor in
                    self.isPulling = false
                    self.currentlyPullingModel = nil
                    self.pullProgress = ""
                }
            }
            
            // Check for cancellation periodically
            guard !Task.isCancelled else { return false }
            
            // ... existing pull logic with cancellation checks
        }
        
        return await pullTask!.value
    }
    
    func cancelPull() {
        pullTask?.cancel()
    }
}
```

**Severity:** High

**Impact:** Confusing UX, potential resource waste

**Effort:** Low (30 minutes)

**Success Confidence:** 95%
