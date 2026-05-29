import Foundation

enum LocalDocumentReachabilityChecker {
    static func verify(
        diagnosticsURL: String,
        session: URLSession = .shared,
        retryCount: Int = 5
    ) async -> Result<Void, LocalDocumentServingError> {
        var lastFailure: LocalDocumentServingError?
        for attempt in 0..<retryCount {
            switch await verifyOnce(diagnosticsURL: diagnosticsURL, session: session) {
            case .success:
                return .success(())
            case .failure(let error):
                lastFailure = error
                if attempt + 1 < retryCount {
                    try? await Task.sleep(for: .milliseconds(40 * (attempt + 1)))
                }
            }
        }
        return .failure(lastFailure ?? .serverStartFailed("Local manuscript server did not respond."))
    }

    private static func verifyOnce(diagnosticsURL: String, session: URLSession) async -> Result<Void, LocalDocumentServingError> {
        guard let url = URL(string: diagnosticsURL) else {
            return .failure(.serverStartFailed("Invalid local diagnostics URL."))
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 4)
        request.httpMethod = "GET"
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.serverStartFailed("Local manuscript server did not respond."))
            }
            guard http.statusCode == 200 else {
                return .failure(.serverStartFailed("Local manuscript server returned HTTP \(http.statusCode)."))
            }
            guard !data.isEmpty else {
                return .failure(.serverStartFailed("Local manuscript server returned an empty DOCX response."))
            }
            return .success(())
        } catch {
            return .failure(.serverStartFailed(error.localizedDescription))
        }
    }
}
