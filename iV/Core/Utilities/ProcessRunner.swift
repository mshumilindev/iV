import Foundation

enum ProcessRunner {
    struct Result: Sendable {
        let stdout: String
        let stderr: String
        let exitCode: Int32
    }

    static func run(
        executableURL: URL,
        arguments: [String] = [],
        environment: [String: String] = [:],
        timeout: TimeInterval = 120
    ) async throws -> Result {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = executableURL
                process.arguments = arguments
                if !environment.isEmpty {
                    var merged = ProcessInfo.processInfo.environment
                    for (key, value) in environment {
                        merged[key] = value
                    }
                    process.environment = merged
                }

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                let group = DispatchGroup()
                group.enter()

                process.terminationHandler = { _ in
                    group.leave()
                }

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    if process.isRunning {
                        process.terminate()
                    }
                }

                group.wait()

                let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                continuation.resume(returning: Result(stdout: stdout, stderr: stderr, exitCode: process.terminationStatus))
            }
        }
    }
}
