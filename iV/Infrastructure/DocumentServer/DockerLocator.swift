import Foundation

/// Finds the Docker CLI on macOS, including Homebrew installs outside the app sandbox search path.
enum DockerLocator {
    static let candidatePaths = [
        "/opt/homebrew/bin/docker",
        "/usr/local/bin/docker",
        "/Applications/Docker.app/Contents/Resources/bin/docker",
        "/opt/homebrew/Cellar/docker/current/bin/docker",
    ]
    static let colimaSocketPaths = [
        "\(NSHomeDirectory())/.colima/default/docker.sock",
        "\(NSHomeDirectory())/.colima/docker.sock",
    ]

    static func locate() async -> URL? {
        if let custom = customPathURL() { return custom }
        for path in candidatePaths {
            if let url = resolveExecutable(at: path) { return url }
        }
        return await locateViaShell()
    }

    /// Synchronous lookup — does not fall back to shell PATH.
    static func executableURL() -> URL? {
        if let custom = customPathURL() { return custom }
        for path in candidatePaths {
            if let url = resolveExecutable(at: path) { return url }
        }
        return nil
    }

    /// Environment required by non-Docker-Desktop runtimes such as Colima.
    static func dockerEnvironment() -> [String: String] {
        if let existing = ProcessInfo.processInfo.environment["DOCKER_HOST"], !existing.isEmpty {
            return ["DOCKER_HOST": existing]
        }
        for path in colimaSocketPaths where FileManager.default.fileExists(atPath: path) {
            return ["DOCKER_HOST": "unix://\(path)"]
        }
        return [:]
    }

    static func resolveExecutable(at path: String) -> URL? {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return nil
        }

        var resolvedPath = path
        if let linkTarget = try? fm.destinationOfSymbolicLink(atPath: path) {
            if linkTarget.hasPrefix("/") {
                resolvedPath = linkTarget
            } else {
                resolvedPath = URL(fileURLWithPath: path).deletingLastPathComponent()
                    .appendingPathComponent(linkTarget).standardized.path
            }
        }

        guard fm.isExecutableFile(atPath: resolvedPath) else { return nil }
        return URL(fileURLWithPath: resolvedPath)
    }

    static func cliNotFoundHelp() -> String {
        """
        Docker CLI not found. iV checked Homebrew and Docker Desktop install paths.
        • Install Docker Desktop and launch it, or
        • Homebrew: brew install docker && colima start, or
        • Set a custom docker path in Settings → Document editor.
        """
    }

    static func daemonNotRunningHelp(cliPath: String, detail: String) -> String {
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines = [
            "Docker CLI found at \(cliPath), but the Docker daemon is not running.",
            "Start Docker Desktop, OrbStack, or Colima (colima start), then retry.",
        ]
        if !trimmed.isEmpty {
            lines.append(trimmed)
        }
        return lines.joined(separator: "\n")
    }

    private static func customPathURL() -> URL? {
        guard let raw = DocumentEditorSettings.loadDockerCLIPath()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else { return nil }
        return resolveExecutable(at: raw)
    }

    private static func locateViaShell() async -> URL? {
        do {
            let result = try await ProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/bin/zsh"),
                arguments: ["-lc", "command -v docker"],
                environment: dockerEnvironment(),
                timeout: 10
            )
            guard result.exitCode == 0 else { return nil }
            let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty else { return nil }
            return resolveExecutable(at: path)
        } catch {
            return nil
        }
    }
}
