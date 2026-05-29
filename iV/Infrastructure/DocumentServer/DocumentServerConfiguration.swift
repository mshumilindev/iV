import Foundation

/// Local Document Server URL configuration and validation.
enum DocumentServerConfiguration {
    static let defaultURL = DocumentEditorSettings.defaultServerURL

    enum ValidationError: LocalizedError, Sendable, Equatable {
        case empty
        case invalidURL
        case remoteHostBlocked(host: String)

        var userMessage: String {
            errorDescription ?? "Invalid Document Server configuration."
        }

        var errorDescription: String? {
            switch self {
            case .empty:
                "Document Server URL is not configured."
            case .invalidURL:
                "Document Server URL is invalid. Use a full URL such as http://127.0.0.1:8080."
            case .remoteHostBlocked:
                "Only localhost Document Server URLs are allowed for local-first editing."
            }
        }
    }

    static func normalizedURL(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func validate(_ raw: String) -> Result<URL, ValidationError> {
        let trimmed = normalizedURL(raw)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        guard let url = URL(string: trimmed), let host = url.host else {
            return .failure(.invalidURL)
        }
        guard host == "127.0.0.1" || host == "localhost" else {
            return .failure(.remoteHostBlocked(host: host))
        }
        return .success(url)
    }

    static func healthCheckURL(for base: URL) -> URL {
        base.appendingPathComponent("healthcheck")
    }

    /// URLs ONLYOFFICE may use when downloading saved DOCX files back to the Mac.
    static func isAllowedLocalFetchURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        guard let host = url.host?.lowercased() else { return false }
        return host == "127.0.0.1" || host == "localhost" || host == "host.docker.internal"
    }
}
