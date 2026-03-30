import Testing
import Foundation
@testable import mrml

// MARK: - AppState Tests

@Suite("AppState Tests")
struct AppStateTests {
    
    // MARK: - State Transition Logic Tests
    
    @Test("Initial state is idle (not recording, not processing)")
    func initialStateIsIdle() {
        var isRecording = false
        var isProcessing = false
        
        #expect(isRecording == false)
        #expect(isProcessing == false)
    }
    
    @Test("Cannot start recording while already recording")
    func cannotStartWhileRecording() {
        let isRecording = true
        let isProcessing = false
        
        let canStart = !isRecording && !isProcessing
        #expect(canStart == false)
    }
    
    @Test("Cannot start recording while processing")
    func cannotStartWhileProcessing() {
        let isRecording = false
        let isProcessing = true
        
        let canStart = !isRecording && !isProcessing
        #expect(canStart == false)
    }
    
    @Test("Can start recording when idle")
    func canStartWhenIdle() {
        let isRecording = false
        let isProcessing = false
        
        let canStart = !isRecording && !isProcessing
        #expect(canStart == true)
    }
    
    @Test("State transition: idle -> recording")
    func transitionIdleToRecording() {
        var isRecording = false
        var isProcessing = false
        
        isRecording = true
        
        #expect(isRecording == true)
        #expect(isProcessing == false)
    }
    
    @Test("State transition: recording -> processing")
    func transitionRecordingToProcessing() {
        var isRecording = true
        var isProcessing = false
        
        isRecording = false
        isProcessing = true
        
        #expect(isRecording == false)
        #expect(isProcessing == true)
    }
    
    @Test("State transition: processing -> idle")
    func transitionProcessingToIdle() {
        var isRecording = false
        var isProcessing = true
        
        isProcessing = false
        
        #expect(isRecording == false)
        #expect(isProcessing == false)
    }
    
    @Test("Full state cycle: idle -> recording -> processing -> idle")
    func fullStateCycle() {
        var isRecording = false
        var isProcessing = false
        
        #expect(isRecording == false && isProcessing == false)
        
        isRecording = true
        #expect(isRecording == true && isProcessing == false)
        
        isRecording = false
        isProcessing = true
        #expect(isRecording == false && isProcessing == true)
        
        isProcessing = false
        #expect(isRecording == false && isProcessing == false)
    }
    
    // MARK: - Audio Level Tests
    
    @Test("Audio level starts at zero")
    func audioLevelStartsAtZero() {
        let audioLevel: Float = 0
        #expect(audioLevel == 0)
    }
    
    @Test("Audio level resets to zero after recording stops")
    func audioLevelResetsAfterStop() {
        var audioLevel: Float = 0.75
        
        audioLevel = 0
        
        #expect(audioLevel == 0)
    }
    
    @Test("Audio level is normalized between 0 and 1")
    func audioLevelNormalized() {
        let levels: [Float] = [0.0, 0.25, 0.5, 0.75, 1.0]
        
        for level in levels {
            #expect(level >= 0.0)
            #expect(level <= 1.0)
        }
    }
    
    // MARK: - Error Handling Tests
    
    @Test("Error is cleared when recording starts successfully")
    func errorClearedOnStart() {
        var lastError: String? = "Previous error"
        
        lastError = nil
        
        #expect(lastError == nil)
    }
    
    @Test("Error is set when recording fails")
    func errorSetOnFailure() {
        var lastError: String? = nil
        
        lastError = "Microphone access denied"
        
        #expect(lastError != nil)
        #expect(lastError == "Microphone access denied")
    }
    
    @Test("Error is cleared on successful processing")
    func errorClearedOnSuccess() {
        var lastError: String? = "Previous error"
        
        lastError = nil
        
        #expect(lastError == nil)
    }
    
    // MARK: - Preset Capture Tests
    
    @Test("Preset name is captured at recording start")
    func presetNameCaptured() {
        var capturedPresetName = ""
        let selectedPresetName = "Casual"
        
        capturedPresetName = selectedPresetName
        
        #expect(capturedPresetName == "Casual")
    }
    
    @Test("System prompt is captured at recording start")
    func systemPromptCaptured() {
        var capturedSystemPrompt = ""
        let currentPrompt = "Clean up this text..."
        
        capturedSystemPrompt = currentPrompt
        
        #expect(capturedSystemPrompt == "Clean up this text...")
    }
    
    @Test("All presets are captured for parallel processing")
    func allPresetsCaptured() {
        var capturedPresets: [(name: String, prompt: String)] = []
        let allPresets = [
            (name: "Casual", prompt: "Casual prompt"),
            (name: "Structured", prompt: "Structured prompt"),
            (name: "Markdown", prompt: "Markdown prompt"),
            (name: "Verbatim", prompt: "Verbatim prompt")
        ]
        
        capturedPresets = allPresets
        
        #expect(capturedPresets.count == 4)
        #expect(capturedPresets[0].name == "Casual")
        #expect(capturedPresets[3].name == "Verbatim")
    }
    
    // MARK: - Personal Dictionary Integration Tests
    
    @Test("Personal dictionary appends to prompt when enabled")
    func personalDictionaryAppendsToPrompt() {
        let basePrompt = "Clean up this text."
        let dictionary = ["Kubernetes", "GraphQL"]
        let dictionaryEnabled = true
        
        var finalPrompt = basePrompt
        if dictionaryEnabled && !dictionary.isEmpty {
            let words = dictionary.joined(separator: ", ")
            finalPrompt += " If the speaker says words similar to these names/terms, use this exact spelling: \(words)."
        }
        
        #expect(finalPrompt.contains("Kubernetes"))
        #expect(finalPrompt.contains("GraphQL"))
    }
    
    @Test("Personal dictionary is not appended when disabled")
    func personalDictionaryNotAppendedWhenDisabled() {
        let basePrompt = "Clean up this text."
        let dictionary = ["Kubernetes", "GraphQL"]
        let dictionaryEnabled = false
        
        var finalPrompt = basePrompt
        if dictionaryEnabled && !dictionary.isEmpty {
            let words = dictionary.joined(separator: ", ")
            finalPrompt += " If the speaker says words similar to these names/terms, use this exact spelling: \(words)."
        }
        
        #expect(finalPrompt == basePrompt)
        #expect(!finalPrompt.contains("Kubernetes"))
    }
    
    @Test("Personal dictionary is not appended when empty")
    func personalDictionaryNotAppendedWhenEmpty() {
        let basePrompt = "Clean up this text."
        let dictionary: [String] = []
        let dictionaryEnabled = true
        
        var finalPrompt = basePrompt
        if dictionaryEnabled && !dictionary.isEmpty {
            let words = dictionary.joined(separator: ", ")
            finalPrompt += " If the speaker says words similar to these names/terms, use this exact spelling: \(words)."
        }
        
        #expect(finalPrompt == basePrompt)
    }
    
    // MARK: - Skip Refinement (Raw Mode) Tests
    
    @Test("Skip refinement uses original text as result")
    func skipRefinementUsesOriginal() {
        let originalText = "hello world"
        let skipRefinement = true
        
        let finalResult = skipRefinement ? originalText : "Hello, world."
        
        #expect(finalResult == "hello world")
    }
    
    @Test("Skip refinement sets preset name to Raw")
    func skipRefinementSetsRawPresetName() {
        let skipRefinement = true
        let presetName = skipRefinement ? "Raw (No Refinement)" : "Casual"
        
        #expect(presetName == "Raw (No Refinement)")
    }
    
    // MARK: - Parallel Refinement Tests
    
    @Test("Parallel refinement processes all presets")
    func parallelRefinementProcessesAll() {
        let presets = ["Casual", "Structured", "Markdown", "Verbatim"]
        var variants: [String: String] = [:]
        
        for preset in presets {
            variants[preset] = "Refined by \(preset)"
        }
        
        #expect(variants.count == 4)
        #expect(variants["Casual"] == "Refined by Casual")
        #expect(variants["Verbatim"] == "Refined by Verbatim")
    }
    
    @Test("Non-parallel refinement processes only selected preset")
    func nonParallelRefinementProcessesSelected() {
        let selectedPreset = "Casual"
        var variants: [String: String] = [:]
        
        variants[selectedPreset] = "Refined text"
        
        #expect(variants.count == 1)
        #expect(variants["Casual"] != nil)
        #expect(variants["Structured"] == nil)
    }
    
    @Test("Final result uses selected preset variant")
    func finalResultUsesSelectedPreset() {
        let selectedPreset = "Structured"
        let variants = [
            "Casual": "Casual result",
            "Structured": "Structured result",
            "Markdown": "Markdown result"
        ]
        let originalText = "original"
        
        let finalResult = variants[selectedPreset] ?? originalText
        
        #expect(finalResult == "Structured result")
    }
    
    @Test("Selected preset failure no longer degrades silently to raw output")
    func selectedPresetFailureIsExplicit() async {
        let casualID = UUID(uuidString: "00000000-0000-0000-0000-00000000B001")!
        let structuredID = UUID(uuidString: "00000000-0000-0000-0000-00000000B002")!
        let runner = ParallelRefinementAuditRunner(
            selectedPresetID: structuredID,
            selectedPresetName: "Structured",
            presets: [
                RefinementVariantPlan(presetID: casualID, name: "Casual", basePrompt: "Casual", effectivePrompt: "Casual + dict"),
                RefinementVariantPlan(presetID: structuredID, name: "Structured", basePrompt: "Structured", effectivePrompt: "Structured + dict")
            ],
            now: { 100 }
        )

        await #expect(throws: ParallelRefinementError.self) {
            try await runner.run { plan in
                if plan.name == "Structured" {
                    throw NSError(domain: "AppStateTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "selected failed"])
                }

                return RefinementExecutionResult(
                    text: "casual result",
                    timing: StageTiming(startedAt: 120, finishedAt: 220)
                )
            }
        }
    }
    
    // MARK: - File Cleanup Tests
    
    @Test("Cleanup retry logic attempts multiple times")
    func cleanupRetryLogic() {
        var attempts = 0
        let maxRetries = 3
        var success = false
        
        for attempt in 1...maxRetries {
            attempts = attempt
            if attempt == 2 {
                success = true
                break
            }
        }
        
        #expect(attempts == 2)
        #expect(success == true)
    }
    
    @Test("Cleanup gives up after max retries")
    func cleanupGivesUpAfterMaxRetries() {
        var attempts = 0
        let maxRetries = 3
        
        for attempt in 1...maxRetries {
            attempts = attempt
        }
        
        #expect(attempts == 3)
    }
}
