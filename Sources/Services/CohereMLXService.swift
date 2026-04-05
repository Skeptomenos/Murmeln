import Foundation
import os

private let logger = Logger(subsystem: "com.skeptomenos.murmeln", category: "CohereMLX")

@MainActor
final class CohereMLXService: ObservableObject {

    // Singleton — used by TranscriptionPipelineService.shared.
    // MurmelnApp/AppState observe this via @StateObject referencing the same shared instance.
    static let shared = CohereMLXService()

    nonisolated static let modelID = "CohereLabs/cohere-transcribe-03-2026"

    enum ModelState: Equatable {
        case notLoaded
        case loading
        case ready
        case failed(String)
    }

    @Published private(set) var modelState: ModelState = .notLoaded

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var stdoutBuffer = ""
    private var pendingContinuation: CheckedContinuation<String, Error>?

    // MARK: - Lifecycle

    func startBridge() async throws {
        // Only start if not already loading or ready
        switch modelState {
        case .loading, .ready: return
        default: break
        }
        modelState = .loading

        let scriptURL = bridgeScriptURL()

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["python3", scriptURL.path]

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = stderr

        process = proc
        stdinPipe = stdin
        stdoutPipe = stdout
        stderrPipe = stderr

        // P1-1: Guard empty data (EOF) to stop handler when process exits
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            guard let self, let chunk = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in self.handleOutput(chunk) }
        }

        // P1-5: Capture stderr for diagnostics instead of discarding
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            guard let text = String(data: data, encoding: .utf8) else {
                return  // skip garbled chunk but keep handler alive
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                logger.warning("cohere_bridge stderr: \(trimmed, privacy: .public)")
            }
        }

        // P0-3: Resume pending continuation on unexpected process exit
        proc.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let cont = self.pendingContinuation
                self.pendingContinuation = nil
                cont?.resume(throwing: CohereMLXError.bridgeCrashed)
                if self.modelState == .ready || self.modelState == .loading {
                    self.modelState = .failed("Bridge process exited unexpectedly")
                }
            }
        }

        try proc.run()
    }

    // P0-3 + P1-2: Resume continuation and clear handlers before cleanup
    func stopBridge() {
        let cont = pendingContinuation
        pendingContinuation = nil
        cont?.resume(throwing: CohereMLXError.bridgeStopped)

        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        modelState = .notLoaded
    }

    // MARK: - Transcription

    // P0-1: Guard concurrent transcription
    // P1-3: Validate stdinPipe before registering continuation
    func transcribe(audioURL: URL, language: String = "en") async throws -> String {
        guard modelState == .ready else {
            throw CohereMLXError.bridgeNotReady
        }
        guard pendingContinuation == nil else {
            throw CohereMLXError.transcriptionInFlight
        }
        guard let pipe = stdinPipe else {
            throw CohereMLXError.bridgeNotReady
        }

        let message = "\(audioURL.path)|\(language)\n"
        guard let data = message.data(using: .utf8) else {
            throw CohereMLXError.encodingFailed
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.pendingContinuation = continuation
            pipe.fileHandleForWriting.write(data)
        }
    }

    // MARK: - Output handling

    // internal (not private) — allows @testable import tests to call directly
    // without spawning a real Python process
    func handleOutput(_ chunk: String) {
        stdoutBuffer += chunk
        let lines = stdoutBuffer.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            guard i < lines.count - 1 else {
                stdoutBuffer = line  // incomplete last line
                return
            }
            processLine(line)
        }
        stdoutBuffer = ""
    }

    // P0-2: Unescape \\n back to real newlines in protocol messages
    func processLine(_ line: String) {
        if line == "READY" {
            modelState = .ready
            return
        }
        if line.hasPrefix("LOAD_ERROR|") {
            let msg = String(line.dropFirst("LOAD_ERROR|".count))
                .replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\\\", with: "\\")
            modelState = .failed(msg)
            return
        }
        if line.hasPrefix("OK|") {
            let transcript = String(line.dropFirst("OK|".count))
                .replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\\\", with: "\\")
            pendingContinuation?.resume(returning: transcript)
            pendingContinuation = nil
            return
        }
        if line.hasPrefix("ERROR|") {
            let msg = String(line.dropFirst("ERROR|".count))
                .replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\\\", with: "\\")
            pendingContinuation?.resume(throwing: CohereMLXError.transcriptionFailed(msg))
            pendingContinuation = nil
        }
    }

    // MARK: - Test Helpers (internal access for @testable import)

    #if DEBUG
    // Test-only accessors — not available in release builds

    /// Exposes pendingContinuation for test assertions. Do not use in production code.
    var pendingContinuation_testAccess: CheckedContinuation<String, Error>? {
        pendingContinuation
    }

    /// Clears pendingContinuation without resuming. For test use only.
    func clearPendingContinuation_testAccess() {
        pendingContinuation = nil
    }

    /// Installs a dummy stdinPipe so transcribe() can register continuations
    /// without spawning a real Python process. For test use only.
    func installTestStdinPipe() {
        stdinPipe = Pipe()
    }
    #endif

    // MARK: - Helpers

    private func bridgeScriptURL() -> URL {
        // Xcode app bundle: Bundle.main has resources from Copy Bundle Resources phase
        if let bundled = Bundle.main.url(forResource: "cohere_bridge", withExtension: "py") {
            return bundled
        }
        // SPM build: resources land in Bundle.module (mrml_mrml.bundle sidecar)
        // Bundle.module is only available when built via SPM; use #if canImport guard
        // to avoid a compile error in Xcode builds where Bundle.module doesn't exist.
        // In practice for Murmeln Dev use xcodebuild, not swift build, for runtime.
        // This fallback is for test/CI environments only.
        fatalError("cohere_bridge.py not found in app bundle. Add it to the Xcode target's Copy Bundle Resources phase and to Package.swift resources.")
    }
}

enum CohereMLXError: Error, LocalizedError, Equatable {
    case bridgeNotReady
    case encodingFailed
    case transcriptionFailed(String)
    case transcriptionInFlight   // P0-1
    case bridgeStopped           // P0-3
    case bridgeCrashed           // P0-3

    var errorDescription: String? {
        switch self {
        case .bridgeNotReady: return "Cohere bridge is not ready. Wait for model to load."
        case .encodingFailed: return "Failed to encode transcription request."
        case .transcriptionFailed(let msg): return "Cohere transcription failed: \(msg)"
        case .transcriptionInFlight: return "A transcription is already in progress."
        case .bridgeStopped: return "Cohere bridge was stopped during transcription."
        case .bridgeCrashed: return "Cohere bridge process exited unexpectedly."
        }
    }
}
