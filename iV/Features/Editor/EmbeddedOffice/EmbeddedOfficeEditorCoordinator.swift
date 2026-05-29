import Foundation
import Observation

/// Coordinates embedded office editor lifecycle: document preparation, server health, honest UI state.
@MainActor
@Observable
final class EmbeddedOfficeEditorCoordinator {
    var lifecycle: EmbeddedEditorLifecycle = .idle
    var documentTitle: String = ""
    var docxFileURL: URL?
    var serverURL: String = DocumentEditorSettings.defaultServerURL
    var showTechnicalDetail = false
    var activeSession: EmbeddedDocumentSessionReady?
    var bridgePendingMessage: String?
    var bridgePendingTechnicalDetail: String?
    var hostConnectionState: DocumentEditorConnectionState = .unavailable("Editor not loaded.")
    var runtimeStatus: DocumentServerRuntimeStatus = .unknown

    private let healthChecker: DocumentServerHealthChecking
    private let preparationService: EmbeddedDocumentPreparationService
    private let sessionManager: EmbeddedDocumentSessionManaging
    private let runtimeService: DocumentServerRuntimeManaging
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration = 0

    init(
        healthChecker: DocumentServerHealthChecking = LiveDocumentServerHealthChecker(),
        preparationService: EmbeddedDocumentPreparationService,
        sessionManager: EmbeddedDocumentSessionManaging = ONLYOFFICEDocumentSessionManager(),
        runtimeService: DocumentServerRuntimeManaging = LiveDocumentServerRuntimeService()
    ) {
        self.healthChecker = healthChecker
        self.preparationService = preparationService
        self.sessionManager = sessionManager
        self.runtimeService = runtimeService
    }

    func reset() {
        cancelRefresh()
        lifecycle = .idle
        documentTitle = ""
        docxFileURL = nil
        activeSession = nil
        bridgePendingMessage = nil
        bridgePendingTechnicalDetail = nil
        hostConnectionState = .unavailable("Editor not loaded.")
        runtimeStatus = .unknown
        showTechnicalDetail = false
    }

    func sync(
        activeDocument: Document?,
        projectFolder: URL?,
        serverURL: String,
        editorKind: DocumentEditorKind
    ) {
        self.serverURL = serverURL
        guard editorKind == .embeddedOffice else {
            cancelRefresh()
            lifecycle = .idle
            activeSession = nil
            return
        }
        guard let document = activeDocument else {
            cancelRefresh()
            documentTitle = ""
            docxFileURL = nil
            activeSession = nil
            lifecycle = .noDocument
            return
        }
        guard let folder = projectFolder else {
            cancelRefresh()
            activeSession = nil
            lifecycle = .failed(
                message: "Project folder is unavailable.",
                technicalDetail: "Cannot resolve manuscript path without an open project folder."
            )
            return
        }
        let docChanged = document.id != lastDocumentID
            || documentTitle != document.title
            || docxFileURL?.path != resolvedDocxPath(document: document, folder: folder)
        lastDocumentID = document.id
        documentTitle = document.title
        if docChanged || shouldRefresh(for: lifecycle) {
            scheduleRefresh(document: document, folder: folder)
        }
    }

    func retryConnection() {
        guard let documentID = lastDocumentID,
              let folder = lastProjectFolder,
              let document = lastPreparedDocument else {
            lifecycle = .noDocument
            return
        }
        scheduleRefresh(document: document, folder: folder, force: true)
        _ = documentID
    }

    func updateHostConnectionState(_ state: DocumentEditorConnectionState) {
        hostConnectionState = state
    }

    func cancelRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    var isEditingBridgeConnected: Bool {
        activeSession != nil
    }

    var isEditorHostReady: Bool {
        if case .ready = hostConnectionState { return true }
        return false
    }

    // MARK: - Private

    private var lastDocumentID: UUID?
    private var lastProjectFolder: URL?
    private var lastPreparedDocument: Document?

    private func shouldRefresh(for state: EmbeddedEditorLifecycle) -> Bool {
        switch state {
        case .idle, .failed, .serverUnavailable, .noDocument, .bridgePending:
            true
        default:
            false
        }
    }

    private func resolvedDocxPath(document: Document, folder: URL) -> String? {
        if let name = document.docxFileName {
            return ProjectPaths.manuscriptFolder(in: folder).appendingPathComponent(name).path
        }
        return ProjectPaths.documentDocxURL(folder: folder, documentID: document.id).path
    }

    private func scheduleRefresh(document: Document, folder: URL, force: Bool = false) {
        if lifecycle.isBusy, !force { return }
        cancelRefresh()
        refreshGeneration &+= 1
        let generation = refreshGeneration
        refreshTask = Task { [weak self] in
            await self?.runRefresh(document: document, folder: folder, generation: generation)
        }
    }

    private func runRefresh(document: Document, folder: URL, generation: Int) async {
        lifecycle = .preparingDocument
        lastProjectFolder = folder
        lastPreparedDocument = document
        activeSession = nil
        hostConnectionState = .unavailable("Editor not loaded.")
        bridgePendingMessage = nil
        bridgePendingTechnicalDetail = nil

        runtimeStatus = await runtimeService.resolveStatus(serverURL: serverURL, healthChecker: healthChecker)

        let prepared: (document: Document, docxURL: URL)
        do {
            prepared = try preparationService.prepareDocxIfNeeded(document: document, folder: folder)
        } catch {
            guard generation == refreshGeneration else { return }
            let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            lifecycle = .failed(message: "Manuscript file could not be prepared.", technicalDetail: detail)
            return
        }

        guard generation == refreshGeneration else { return }
        docxFileURL = prepared.docxURL
        documentTitle = prepared.document.title
        lastPreparedDocument = prepared.document

        lifecycle = .loadingDocument
        try? await Task.sleep(for: .milliseconds(120))
        guard generation == refreshGeneration else { return }

        lifecycle = .checkingServer
        let health = await healthChecker.checkHealth(serverURL: serverURL)
        guard generation == refreshGeneration else { return }

        let docxPath = prepared.docxURL.path
        switch health {
        case .invalidConfiguration(let error):
            activeSession = nil
            runtimeStatus = .failed(message: error.userMessage, detail: serverURL)
            lifecycle = .serverUnavailable(
                reason: error.userMessage,
                technicalDetail: "URL: \(DocumentServerConfiguration.normalizedURL(serverURL))"
            )
        case .unreachable(let message):
            activeSession = nil
            runtimeStatus = .notRunning
            let healthDetail: String?
            if case .success(let base) = DocumentServerConfiguration.validate(serverURL) {
                healthDetail = "Health check: \(DocumentServerConfiguration.healthCheckURL(for: base).absoluteString)"
            } else {
                healthDetail = nil
            }
            lifecycle = .serverUnavailable(
                reason: message,
                technicalDetail: healthDetail
            )
        case .reachable:
            runtimeStatus = .running
            let outcome = await sessionManager.prepareSession(
                documentServerURL: serverURL,
                documentID: prepared.document.id,
                documentTitle: prepared.document.title,
                docxFileURL: prepared.docxURL
            )
            guard generation == refreshGeneration else { return }

            switch outcome {
            case .ready(let session):
                activeSession = session
                hostConnectionState = .connecting
                bridgePendingMessage = nil
                bridgePendingTechnicalDetail = nil
                lifecycle = .ready(documentTitle: prepared.document.title, docxPath: docxPath)
            case .pending(let reason, let detail):
                activeSession = nil
                bridgePendingMessage = reason
                bridgePendingTechnicalDetail = detail
                lifecycle = .bridgePending(documentTitle: prepared.document.title, docxPath: docxPath)
            case .unavailable(let reason, let detail):
                activeSession = nil
                lifecycle = .serverUnavailable(reason: reason, technicalDetail: detail)
            }
        }
    }
}

extension EmbeddedOfficeEditorCoordinator {
    var connectionState: DocumentEditorConnectionState {
        switch lifecycle {
        case .idle, .noDocument:
            return .unavailable("No active manuscript.")
        case .checkingServer, .preparingDocument, .loadingDocument, .startingDocumentServer:
            return .connecting
        case .serverUnavailable(let reason, _):
            return .unavailable(reason)
        case .bridgePending:
            return .unavailable(bridgePendingMessage ?? "Document Server reachable — editing session pending.")
        case .ready:
            if activeSession != nil {
                return hostConnectionState
            }
            return .unavailable(bridgePendingMessage ?? "Document Server reachable — editing session pending.")
        case .failed(let message, _):
            return .error(message)
        }
    }
}
