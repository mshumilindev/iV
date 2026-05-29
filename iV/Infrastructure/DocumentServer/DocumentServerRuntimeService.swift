import Foundation

enum DocumentServerRuntimeStatus: Sendable, Equatable {
    case unknown
    case dockerUnavailable(detail: String)
    case notRunning
    case starting(message: String)
    case running
    case failed(message: String, detail: String?)
}

enum DocumentServerRuntimeError: LocalizedError, Sendable {
    case dockerUnavailable(String)
    case invalidServerURL(String)
    case startFailed(String, detail: String?)
    case healthCheckTimeout

    var errorDescription: String? {
        switch self {
        case .dockerUnavailable(let detail):
            "Docker is not available: \(detail)"
        case .invalidServerURL(let url):
            "Document Server URL is invalid: \(url)"
        case .startFailed(let message, let detail):
            if let detail, !detail.isEmpty { "\(message)\n\(detail)" } else { message }
        case .healthCheckTimeout:
            "ONLYOFFICE Document Server did not become ready in time."
        }
    }
}

protocol DocumentServerRuntimeManaging: Sendable {
    func resolveStatus(serverURL: String, healthChecker: DocumentServerHealthChecking) async -> DocumentServerRuntimeStatus
    func startLocalDocumentServer(
        serverURL: String,
        healthChecker: DocumentServerHealthChecking,
        onProgress: (@Sendable (String) -> Void)?
    ) async -> DocumentServerLaunchResult
    func stopManagedDocumentServer() async
}

enum DocumentServerLaunchResult: Sendable {
    case alreadyRunning
    case startedManagedContainer
    case failure(DocumentServerRuntimeError)
}

/// Manages a local ONLYOFFICE Document Server Docker container.
struct LiveDocumentServerRuntimeService: DocumentServerRuntimeManaging {
    static let containerName = "iv-onlyoffice-document-server"
    static let imageName = "onlyoffice/documentserver"
    static let healthPollIntervalNanoseconds: UInt64 = 2_000_000_000
    static let healthPollAttempts = 60

    func resolveStatus(
        serverURL: String,
        healthChecker: DocumentServerHealthChecking = LiveDocumentServerHealthChecker()
    ) async -> DocumentServerRuntimeStatus {
        switch await dockerAvailability() {
        case .failure(let error):
            return .dockerUnavailable(detail: error.localizedDescription)
        case .success:
            break
        }

        switch await healthChecker.checkHealth(serverURL: serverURL) {
        case .reachable:
            return .running
        case .invalidConfiguration(let error):
            return .failed(message: error.userMessage, detail: serverURL)
        case .unreachable:
            return .notRunning
        }
    }

    func startLocalDocumentServer(
        serverURL: String,
        healthChecker: DocumentServerHealthChecking = LiveDocumentServerHealthChecker(),
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async -> DocumentServerLaunchResult {
        switch DocumentServerConfiguration.validate(serverURL) {
        case .failure:
            return .failure(.invalidServerURL(serverURL))
        case .success(let baseURL):
            let hostPort = baseURL.port ?? 8080

            switch await dockerAvailability() {
            case .failure(let error):
                return .failure(error)
            case .success(let dockerURL):
                let dockerEnvironment = DockerLocator.dockerEnvironment()
                var existingState = await containerState(dockerURL: dockerURL)
                let needsRecreate = await containerNeedsRecreate(dockerURL: dockerURL, existingState: existingState)

                if !needsRecreate, case .reachable = await healthChecker.checkHealth(serverURL: serverURL) {
                    return .alreadyRunning
                }

                onProgress?(EditorStartupMessage.starting)
                var startedManagedContainer = false

                if needsRecreate, case .missing = existingState {} else if needsRecreate {
                    await removeManagedContainer(dockerURL: dockerURL, environment: dockerEnvironment)
                    existingState = .missing
                }

                switch existingState {
                case .running:
                    break
                case .stopped:
                    do {
                        let start = try await ProcessRunner.run(
                            executableURL: dockerURL,
                            arguments: ["start", Self.containerName],
                            environment: dockerEnvironment
                        )
                        guard start.exitCode == 0 else {
                            return .failure(.startFailed(
                                "Could not start existing Document Server container.",
                                detail: start.stderr.isEmpty ? start.stdout : start.stderr
                            ))
                        }
                        startedManagedContainer = true
                    } catch {
                        return .failure(.startFailed("Could not start existing Document Server container.", detail: error.localizedDescription))
                    }
                case .missing:
                    do {
                        let run = try await createManagedContainer(
                            dockerURL: dockerURL,
                            hostPort: hostPort,
                            environment: dockerEnvironment
                        )
                        guard run.exitCode == 0 else {
                            return .failure(.startFailed(
                                "Could not create ONLYOFFICE Document Server container.",
                                detail: run.stderr.isEmpty ? run.stdout : run.stderr
                            ))
                        }
                        startedManagedContainer = true
                    } catch {
                        return .failure(.startFailed("Could not create ONLYOFFICE Document Server container.", detail: error.localizedDescription))
                    }
                case .unknown(let detail):
                    return .failure(.startFailed("Could not inspect Docker container state.", detail: detail))
                }

                onProgress?(EditorStartupMessage.connecting)
                for attempt in 0..<Self.healthPollAttempts {
                    if case .reachable = await healthChecker.checkHealth(serverURL: serverURL) {
                        return startedManagedContainer ? .startedManagedContainer : .alreadyRunning
                    }
                    if attempt == Self.healthPollAttempts / 2 {
                        onProgress?(EditorStartupMessage.almostReady)
                    }
                    if attempt + 1 < Self.healthPollAttempts {
                        try? await Task.sleep(nanoseconds: Self.healthPollIntervalNanoseconds)
                    }
                }
                return .failure(.healthCheckTimeout)
            }
        }
    }

    func stopManagedDocumentServer() async {
        guard let dockerURL = await DockerLocator.locate() else { return }
        let state = await containerState(dockerURL: dockerURL)
        guard case .running = state else { return }
        _ = try? await ProcessRunner.run(
            executableURL: dockerURL,
            arguments: ["stop", Self.containerName],
            environment: DockerLocator.dockerEnvironment(),
            timeout: 30
        )
    }

    // MARK: - Docker helpers

    private enum ContainerState: Sendable {
        case missing
        case stopped
        case running
        case unknown(String)
    }

    private func dockerAvailability() async -> Result<URL, DocumentServerRuntimeError> {
        guard let dockerURL = await DockerLocator.locate() else {
            return .failure(.dockerUnavailable(DockerLocator.cliNotFoundHelp()))
        }
        do {
            let version = try await ProcessRunner.run(
                executableURL: dockerURL,
                arguments: ["version", "--format", "{{.Server.Version}}"],
                environment: DockerLocator.dockerEnvironment()
            )
            guard version.exitCode == 0 else {
                let detail = version.stderr.isEmpty ? version.stdout : version.stderr
                return .failure(.dockerUnavailable(
                    DockerLocator.daemonNotRunningHelp(cliPath: dockerURL.path, detail: detail)
                ))
            }
            return .success(dockerURL)
        } catch {
            return .failure(.dockerUnavailable(error.localizedDescription))
        }
    }

    private func containerState(dockerURL: URL) async -> ContainerState {
        do {
            let inspect = try await ProcessRunner.run(
                executableURL: dockerURL,
                arguments: ["ps", "-a", "--filter", "name=^\(Self.containerName)$", "--format", "{{.Status}}"],
                environment: DockerLocator.dockerEnvironment()
            )
            guard inspect.exitCode == 0 else {
                return .unknown(inspect.stderr.isEmpty ? inspect.stdout : inspect.stderr)
            }
            let status = inspect.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if status.isEmpty { return .missing }
            if status.lowercased().hasPrefix("up") { return .running }
            return .stopped
        } catch {
            return .unknown(error.localizedDescription)
        }
    }

    private func containerNeedsRecreate(dockerURL: URL, existingState: ContainerState) async -> Bool {
        if case .missing = existingState { return false }

        do {
            let envResult = try await ProcessRunner.run(
                executableURL: dockerURL,
                arguments: ["inspect", Self.containerName, "--format", "{{range .Config.Env}}{{println .}}{{end}}"],
                environment: DockerLocator.dockerEnvironment()
            )
            guard envResult.exitCode == 0 else { return true }
            let jwtDisabled = envResult.stdout.lowercased().contains("jwt_enabled=false")

            let hostResult = try await ProcessRunner.run(
                executableURL: dockerURL,
                arguments: ["inspect", Self.containerName, "--format", "{{json .HostConfig.ExtraHosts}}"],
                environment: DockerLocator.dockerEnvironment()
            )
            guard hostResult.exitCode == 0 else { return true }
            let hosts = hostResult.stdout.lowercased()
            let hasHostGateway = hosts.contains("host.docker.internal") && hosts.contains("host-gateway")

            return !(jwtDisabled && hasHostGateway)
        } catch {
            return true
        }
    }

    private func removeManagedContainer(dockerURL: URL, environment: [String: String]) async {
        _ = try? await ProcessRunner.run(
            executableURL: dockerURL,
            arguments: ["rm", "-f", Self.containerName],
            environment: environment,
            timeout: 60
        )
    }

    private func createManagedContainer(
        dockerURL: URL,
        hostPort: Int,
        environment: [String: String]
    ) async throws -> ProcessRunner.Result {
        try await ProcessRunner.run(
            executableURL: dockerURL,
            arguments: [
                "run", "-d",
                "--name", Self.containerName,
                "-p", "\(hostPort):80",
                "--add-host", "\(LocalManuscriptDocumentServer.documentServerFetchHost):host-gateway",
                "-e", "JWT_ENABLED=false",
                Self.imageName,
            ],
            environment: environment,
            timeout: 300
        )
    }
}
