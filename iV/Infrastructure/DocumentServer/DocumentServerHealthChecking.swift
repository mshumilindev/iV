import Foundation

enum DocumentServerHealthResult: Sendable, Equatable {
    case invalidConfiguration(DocumentServerConfiguration.ValidationError)
    case unreachable(message: String)
    case reachable(statusCode: Int)
}

protocol DocumentServerHealthChecking: Sendable {
    func checkHealth(serverURL: String) async -> DocumentServerHealthResult
}

/// Live health probe against a local ONLYOFFICE Document Server `/healthcheck`.
struct LiveDocumentServerHealthChecker: DocumentServerHealthChecking {
    var session: URLSession = .shared
    var timeout: TimeInterval = 4

    func checkHealth(serverURL: String) async -> DocumentServerHealthResult {
        switch DocumentServerConfiguration.validate(serverURL) {
        case .failure(let error):
            return .invalidConfiguration(error)
        case .success(let base):
            let healthURL = DocumentServerConfiguration.healthCheckURL(for: base)
            var request = URLRequest(
                url: healthURL,
                cachePolicy: .reloadIgnoringLocalCacheData,
                timeoutInterval: timeout
            )
            request.httpMethod = "GET"
            do {
                let (_, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    return .unreachable(message: "Document Server did not respond.")
                }
                guard (200..<500).contains(http.statusCode) else {
                    return .unreachable(message: "Document Server returned HTTP \(http.statusCode).")
                }
                return .reachable(statusCode: http.statusCode)
            } catch {
                return .unreachable(message: error.localizedDescription)
            }
        }
    }
}
