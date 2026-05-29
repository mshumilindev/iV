import Foundation

struct ONLYOFFICESaveCallbackPayload: Decodable, Sendable, Equatable {
    let key: String
    let status: Int
    let url: String?
    let changesurl: String?
    let users: [String]?

    enum CodingKeys: String, CodingKey {
        case key, status, url, changesurl, users
    }
}

enum ONLYOFFICESaveCallbackError: LocalizedError, Sendable {
    case invalidPayload
    case invalidDocumentID
    case documentNotRegistered
    case saveStatusError(Int)
    case missingDownloadURL
    case downloadURLNotAllowed(String)
    case downloadFailed(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidPayload:
            "ONLYOFFICE callback payload is invalid."
        case .invalidDocumentID:
            "ONLYOFFICE callback document ID is invalid."
        case .documentNotRegistered:
            "Manuscript is not registered with the local document server."
        case .saveStatusError(let status):
            "ONLYOFFICE reported save error status \(status)."
        case .missingDownloadURL:
            "ONLYOFFICE did not provide a download URL for the saved document."
        case .downloadURLNotAllowed(let url):
            "ONLYOFFICE download URL is not allowed: \(url)"
        case .downloadFailed(let detail):
            "Could not download saved DOCX from Document Server: \(detail)"
        case .writeFailed(let detail):
            "Could not write saved DOCX to disk: \(detail)"
        }
    }
}

/// Processes ONLYOFFICE save callbacks and persists updated DOCX locally.
struct ONLYOFFICESaveCallbackProcessor: Sendable {
    var session: URLSession = .shared
    var downloadTimeout: TimeInterval = 30

    func process(
        documentID: UUID,
        payload: ONLYOFFICESaveCallbackPayload,
        targetFileURL: URL
    ) async throws {
        switch payload.status {
        case 1, 4:
            return
        case 2, 6:
            guard let urlString = payload.url, let originalURL = URL(string: urlString) else {
                throw ONLYOFFICESaveCallbackError.missingDownloadURL
            }
            guard let downloadURL = Self.normalizedDownloadURL(originalURL) else {
                throw ONLYOFFICESaveCallbackError.downloadURLNotAllowed(urlString)
            }
            var request = URLRequest(url: downloadURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: downloadTimeout)
            request.httpMethod = "GET"
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                throw ONLYOFFICESaveCallbackError.downloadFailed("HTTP \(code)")
            }
            guard !data.isEmpty else {
                throw ONLYOFFICESaveCallbackError.downloadFailed("Empty file")
            }
            do {
                try AtomicFileWriter.write(data: data, to: targetFileURL)
            } catch {
                throw ONLYOFFICESaveCallbackError.writeFailed(error.localizedDescription)
            }
        case 3, 7:
            throw ONLYOFFICESaveCallbackError.saveStatusError(payload.status)
        default:
            return
        }
    }

    static func decodePayload(from body: Data) throws -> ONLYOFFICESaveCallbackPayload {
        try JSONDecoder().decode(ONLYOFFICESaveCallbackPayload.self, from: body)
    }

    /// Rewrites Document Server cache URLs that use internal Docker hostnames to localhost.
    static func normalizedDownloadURL(_ url: URL) -> URL? {
        if DocumentServerConfiguration.isAllowedLocalFetchURL(url) {
            return url
        }
        guard url.path.contains("/cache/files/") else { return nil }
        guard let base = URL(string: DocumentServerConfiguration.defaultURL),
              let baseHost = base.host else { return nil }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = base.scheme ?? "http"
        components?.host = baseHost
        components?.port = base.port ?? url.port ?? 8080
        guard let rewritten = components?.url,
              DocumentServerConfiguration.isAllowedLocalFetchURL(rewritten) else { return nil }
        return rewritten
    }
}
