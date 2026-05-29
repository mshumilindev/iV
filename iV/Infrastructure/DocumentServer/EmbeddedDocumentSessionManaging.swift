import Foundation

/// Prepares embedded ONLYOFFICE DocsAPI sessions for local manuscripts.
protocol EmbeddedDocumentSessionManaging: Sendable {
    func prepareSession(
        documentServerURL: String,
        documentID: UUID,
        documentTitle: String,
        docxFileURL: URL
    ) async -> EmbeddedDocumentSessionOutcome
}

struct StubEmbeddedDocumentSessionManager: EmbeddedDocumentSessionManaging {
    func prepareSession(
        documentServerURL: String,
        documentID: UUID,
        documentTitle: String,
        docxFileURL: URL
    ) async -> EmbeddedDocumentSessionOutcome {
        _ = documentServerURL
        _ = documentID
        _ = documentTitle
        _ = docxFileURL
        return .pending(
            reason: "Document Server reachable — IV-12 editing bridge not connected.",
            technicalDetail: "Stub session manager — DocsAPI session loader not wired."
        )
    }
}

struct ONLYOFFICEDocumentSessionManager: EmbeddedDocumentSessionManaging {
    let localServer: any LocalDocumentServing

    init(localServer: any LocalDocumentServing = LocalManuscriptDocumentServer.shared) {
        self.localServer = localServer
    }

    func prepareSession(
        documentServerURL: String,
        documentID: UUID,
        documentTitle: String,
        docxFileURL: URL
    ) async -> EmbeddedDocumentSessionOutcome {
        switch DocumentServerConfiguration.validate(documentServerURL) {
        case .failure(let error):
            return .unavailable(reason: error.userMessage, technicalDetail: "URL: \(documentServerURL)")
        case .success:
            break
        }

        let registration: LocalDocumentServingRegistration
        do {
            registration = try localServer.register(documentID: documentID, fileURL: docxFileURL)
        } catch {
            let detail = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return .pending(
                reason: "Local document-serving adapter is not available.",
                technicalDetail: detail
            )
        }

        let documentKey = Self.documentKey(documentID: documentID, fileURL: docxFileURL)
        let callbackURL =
            "http://\(LocalManuscriptDocumentServer.documentServerFetchHost):\(LocalManuscriptDocumentServer.defaultPort)/callback/\(documentID.uuidString.lowercased())"

        guard let html = ONLYOFFICEDocumentEditorLoader.documentEditorHTML(
            serverURL: documentServerURL,
            documentTitle: documentTitle,
            documentKey: documentKey,
            documentFetchURL: registration.documentServerFetchURL,
            callbackURL: callbackURL
        ) else {
            return .pending(
                reason: "DocsAPI session configuration could not be built.",
                technicalDetail: "Manuscript fetch URL: \(registration.documentServerFetchURL)"
            )
        }

        switch await LocalDocumentReachabilityChecker.verify(diagnosticsURL: registration.localDiagnosticsURL) {
        case .failure(let error):
            let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return .pending(
                reason: "Local manuscript file is not reachable over HTTP.",
                technicalDetail: """
                Mac diagnostics URL: \(registration.localDiagnosticsURL)
                Docker fetch URL: \(registration.documentServerFetchURL)
                Error: \(reason)
                """
            )
        case .success:
            break
        }

        return .ready(
            EmbeddedDocumentSessionReady(
                onlyOfficeServerURL: documentServerURL,
                documentTitle: documentTitle,
                docxFileURL: docxFileURL,
                editorHTML: html,
                documentKey: documentKey,
                documentFetchURL: registration.documentServerFetchURL,
                localServingDetail: registration.localDiagnosticsURL,
                saveAvailable: true
            )
        )
    }

    static func documentKey(documentID: UUID, fileURL: URL) -> String {
        let mtime = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date)?
            .timeIntervalSince1970 ?? 0
        return "\(documentID.uuidString.lowercased())-\(Int(mtime))"
    }
}
