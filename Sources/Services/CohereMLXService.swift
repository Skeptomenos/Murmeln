import Foundation

@MainActor
final class CohereMLXService: ObservableObject {

    // Singleton — used by TranscriptionPipelineService.shared.
    // MurmelnApp/AppState observe this via @StateObject referencing the same shared instance.
    static let shared = CohereMLXService()

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
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = FileHandle.nullDevice

        process = proc
        stdinPipe = stdin
        stdoutPipe = stdout

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self, let chunk = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in self.handleOutput(chunk) }
        }

        proc.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.modelState == .ready {
                    self.modelState = .failed("Bridge process exited unexpectedly")
                }
            }
        }

        try proc.run()
    }

    func stopBridge() {
        process?.terminate()
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        modelState = .notLoaded
    }

    // MARK: - Transcription

    func transcribe(audioURL: URL, language: String = "en") async throws -> String {
        guard modelState == .ready else {
            throw CohereMLXError.bridgeNotReady
        }
        let message = "\(audioURL.path)|\(language)\n"
        guard let data = message.data(using: .utf8) else {
            throw CohereMLXError.encodingFailed
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.pendingContinuation = continuation
            self.stdinPipe?.fileHandleForWriting.write(data)
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

    func processLine(_ line: String) {
        if line == "READY" {
            modelState = .ready
            return
        }
        if line.hasPrefix("LOAD_ERROR|") {
            let msg = String(line.dropFirst("LOAD_ERROR|".count))
            modelState = .failed(msg)
            return
        }
        if line.hasPrefix("OK|") {
            let transcript = String(line.dropFirst("OK|".count))
            pendingContinuation?.resume(returning: transcript)
            pendingContinuation = nil
            return
        }
        if line.hasPrefix("ERROR|") {
            let msg = String(line.dropFirst("ERROR|".count))
            pendingContinuation?.resume(throwing: CohereMLXError.transcriptionFailed(msg))
            pendingContinuation = nil
        }
    }

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

    var errorDescription: String? {
        switch self {
        case .bridgeNotReady: return "Cohere bridge is not ready. Wait for model to load."
        case .encodingFailed: return "Failed to encode transcription request."
        case .transcriptionFailed(let msg): return "Cohere transcription failed: \(msg)"
        }
    }
}
