import Foundation
import Network

/// Minimal localhost HTTP server so ONLYOFFICE Document Server can fetch manuscript DOCX files.
///
/// Document Server runs in Docker and cannot read `file://` URLs from the Mac sandbox.
/// It fetches documents via `http://host.docker.internal:{port}/documents/{id}/file.docx`.
final class LocalManuscriptDocumentServer: LocalDocumentServing, @unchecked Sendable {
    static let shared = LocalManuscriptDocumentServer()
    static let defaultPort: UInt16 = 8765
    /// Hostname reachable from ONLYOFFICE Document Server container on macOS Docker Desktop.
    static let documentServerFetchHost = "host.docker.internal"

    typealias SaveCompletionHandler = @Sendable (UUID, Result<URL, Error>) async -> Void

    private let listenPort: UInt16

    private let queue = DispatchQueue(label: "iv.local-manuscript-server", qos: .userInitiated)
    private var listener: NWListener?
    private var filesByPath: [String: URL] = [:]
    private var pathByDocumentID: [UUID: String] = [:]
    private var saveCompletionHandler: SaveCompletionHandler?
    private let saveProcessor = ONLYOFFICESaveCallbackProcessor()
    private let lock = NSLock()
    private(set) var isRunning = false

    init(port: UInt16 = defaultPort) {
        listenPort = port
    }

    func setSaveCompletionHandler(_ handler: SaveCompletionHandler?) {
        lock.lock()
        saveCompletionHandler = handler
        lock.unlock()
    }

    func ensureRunning() throws {
        lock.lock()
        if isRunning, listener != nil {
            lock.unlock()
            return
        }
        lock.unlock()

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let port = NWEndpoint.Port(rawValue: listenPort) else {
            throw LocalDocumentServingError.serverStartFailed("Invalid port \(listenPort)")
        }

        let listener: NWListener
        do {
            listener = try NWListener(using: params, on: port)
        } catch {
            throw LocalDocumentServingError.serverStartFailed(error.localizedDescription)
        }

        let readySemaphore = DispatchSemaphore(value: 0)
        var startupError: String?

        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                readySemaphore.signal()
            case .failed(let error):
                self?.lock.lock()
                self?.isRunning = false
                self?.listener = nil
                self?.lock.unlock()
                startupError = error.localizedDescription
                readySemaphore.signal()
            default:
                break
            }
        }
        listener.start(queue: queue)

        let waitResult = readySemaphore.wait(timeout: .now() + 3)
        if waitResult == .timedOut {
            listener.cancel()
            throw LocalDocumentServingError.serverStartFailed("Local manuscript server did not become ready in time.")
        }
        if let startupError {
            listener.cancel()
            throw LocalDocumentServingError.serverStartFailed(startupError)
        }

        lock.lock()
        self.listener = listener
        isRunning = true
        lock.unlock()
    }

    func register(documentID: UUID, fileURL: URL) throws -> LocalDocumentServingRegistration {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw LocalDocumentServingError.fileNotFound
        }
        try ensureRunning()

        let path = Self.documentPath(for: documentID)
        lock.lock()
        filesByPath[path] = fileURL
        pathByDocumentID[documentID] = path
        lock.unlock()

        let fetchURL = "http://\(Self.documentServerFetchHost):\(listenPort)\(path)"
        let localURL = "http://127.0.0.1:\(listenPort)\(path)"
        return LocalDocumentServingRegistration(
            path: path,
            documentServerFetchURL: fetchURL,
            localDiagnosticsURL: localURL
        )
    }

    func unregister(documentID: UUID) {
        lock.lock()
        if let path = pathByDocumentID.removeValue(forKey: documentID) {
            filesByPath.removeValue(forKey: path)
        }
        lock.unlock()
    }

    static func documentPath(for documentID: UUID) -> String {
        "/documents/\(documentID.uuidString.lowercased())/file.docx"
    }

    static func documentID(fromPath path: String) -> UUID? {
        let prefix = "/documents/"
        let suffix = "/file.docx"
        guard path.hasPrefix(prefix), path.hasSuffix(suffix) else { return nil }
        let raw = path.dropFirst(prefix.count).dropLast(suffix.count)
        return UUID(uuidString: String(raw))
    }

    static func callbackDocumentID(fromPath path: String) -> UUID? {
        let prefix = "/callback/"
        guard path.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(path.dropFirst(prefix.count)))
    }

    // MARK: - HTTP

    private struct ParsedHTTPRequest {
        let method: String
        let path: String
        let body: Data
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, accumulated: Data())
    }

    private func receiveRequest(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [weak self] data, _, isComplete, _ in
            guard let self else {
                connection.cancel()
                return
            }
            var buffer = accumulated
            if let data { buffer.append(data) }

            if let request = self.parseRequest(buffer) {
                self.respond(to: request, on: connection)
                return
            }

            if isComplete || buffer.count >= 1_048_576 {
                connection.cancel()
                return
            }
            self.receiveRequest(on: connection, accumulated: buffer)
        }
    }

    private func parseRequest(_ data: Data) -> ParsedHTTPRequest? {
        guard let separator = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        guard let headerText = String(data: data[..<separator.lowerBound], encoding: .utf8) else { return nil }
        let body = Data(data[separator.upperBound...])
        let lines = headerText.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0])
        let rawPath = String(parts[1])
        let path = String(rawPath.split(separator: "?").first ?? Substring(rawPath))

        var contentLength = 0
        for line in lines.dropFirst() {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                let value = lower.replacingOccurrences(of: "content-length:", with: "").trimmingCharacters(in: .whitespaces)
                contentLength = Int(value) ?? 0
            }
        }

        if method == "POST", body.count < contentLength { return nil }
        let requestBody = contentLength > 0 ? body.prefix(contentLength) : body.prefix(0)
        return ParsedHTTPRequest(method: method, path: path, body: Data(requestBody))
    }

    private func respond(to request: ParsedHTTPRequest, on connection: NWConnection) {
        if request.method == "GET" {
            respondToGET(path: request.path, on: connection)
            return
        }

        if request.method == "POST", request.path.hasPrefix("/callback/") {
            handleCallback(path: request.path, body: request.body, on: connection)
            return
        }

        sendResponse(connection: connection, status: 405, contentType: "text/plain", body: Data("Method not allowed".utf8))
    }

    private func respondToGET(path: String, on connection: NWConnection) {
        guard let documentID = Self.documentID(fromPath: path) else {
            sendResponse(connection: connection, status: 404, contentType: "text/plain", body: Data("Not found".utf8))
            return
        }

        lock.lock()
        let fileURL = filesByPath[path]
        lock.unlock()

        guard let fileURL, let body = try? Data(contentsOf: fileURL) else {
            sendResponse(connection: connection, status: 404, contentType: "text/plain", body: Data("Not found".utf8))
            return
        }

        _ = documentID
        sendResponse(
            connection: connection,
            status: 200,
            contentType: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            body: body
        )
    }

    private func handleCallback(path: String, body: Data, on connection: NWConnection) {
        guard let documentID = Self.callbackDocumentID(fromPath: path) else {
            sendJSON(connection: connection, status: 400, payload: ["error": 1, "message": "Invalid callback document ID."])
            return
        }

        lock.lock()
        let registeredPath = pathByDocumentID[documentID]
        let fileURL = registeredPath.flatMap { filesByPath[$0] }
        let handler = saveCompletionHandler
        lock.unlock()

        guard let fileURL else {
            sendJSON(connection: connection, status: 404, payload: ["error": 1, "message": "Document not registered."])
            return
        }

        let payload: ONLYOFFICESaveCallbackPayload
        do {
            payload = try ONLYOFFICESaveCallbackProcessor.decodePayload(from: body)
        } catch {
            sendJSON(connection: connection, status: 400, payload: ["error": 1, "message": "Invalid callback payload."])
            return
        }

        switch payload.status {
        case 3, 7:
            sendJSON(connection: connection, status: 200, payload: ["error": 1, "message": "Document save reported an error."])
            Task {
                await handler?(documentID, .failure(ONLYOFFICESaveCallbackError.saveStatusError(payload.status)))
            }
            return
        case 1, 4:
            sendJSON(connection: connection, status: 200, payload: ["error": 0])
            return
        case 2, 6:
            // ONLYOFFICE times out if we wait for download+write — ACK first, persist in background.
            sendJSON(connection: connection, status: 200, payload: ["error": 0])
            Task { [saveProcessor] in
                do {
                    try await saveProcessor.process(documentID: documentID, payload: payload, targetFileURL: fileURL)
                    await handler?(documentID, .success(fileURL))
                } catch {
                    await handler?(documentID, .failure(error))
                }
            }
            return
        default:
            sendJSON(connection: connection, status: 200, payload: ["error": 0])
        }
    }

    private func sendJSON(connection: NWConnection, status: Int, payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
            sendResponse(connection: connection, status: 500, contentType: "application/json", body: Data("{\"error\":1}".utf8))
            return
        }
        sendResponse(connection: connection, status: status, contentType: "application/json", body: data)
    }

    private func sendResponse(connection: NWConnection, status: Int, contentType: String, body: Data) {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        case 405: statusText = "Method Not Allowed"
        case 500: statusText = "Internal Server Error"
        default: statusText = "Error"
        }

        var response = "HTTP/1.1 \(status) \(statusText)\r\n"
        response += "Content-Type: \(contentType)\r\n"
        response += "Content-Length: \(body.count)\r\n"
        response += "Connection: close\r\n\r\n"

        var data = Data(response.utf8)
        data.append(body)
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
