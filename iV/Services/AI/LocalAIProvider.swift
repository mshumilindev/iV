import Foundation

enum OllamaHealth: Sendable {
    case unavailable(String)
    case available(models: [String])
    case running
}

protocol LocalAIProvider: Sendable {
    var backend: LocalAIBackend { get }
    func checkAvailability(settings: OllamaSettings) async -> OllamaHealth
    func listModels(settings: OllamaSettings) async throws -> [String]
    func runJSONTask<T: Decodable>(prompt: String, model: String, settings: OllamaSettings, as type: T.Type) async throws -> T
    func runTextTask(prompt: String, model: String, settings: OllamaSettings, keepAlive: String?) async throws -> String
    func embed(text: String, model: String, settings: OllamaSettings) async throws -> [Float]
    func unloadModel(name: String, settings: OllamaSettings) async throws
    func cancelTask()
    func estimateContextLimit(model: String) -> Int
    func estimateRuntimeCost(promptTokens: Int) -> String
}

struct OllamaEmbedRequest: Encodable {
    let model: String
    let prompt: String
}

struct OllamaEmbedResponse: Decodable {
    let embedding: [Double]
}

struct OllamaModelsResponse: Decodable {
    struct Model: Decodable { let name: String }
    let models: [Model]
}

struct OllamaGenerateRequest: Encodable {
    let model: String
    let prompt: String
    let stream: Bool
    let format: String?
    let keep_alive: String?
    let options: Options

    struct Options: Encodable {
        let temperature: Double
        let num_predict: Int
    }
}

struct OllamaGenerateResponse: Decodable {
    let response: String
}

struct LLMAnalysisResponse: Decodable, Sendable {
    let diagnostics: [LLMDiagnostic]
    let changeProposals: [LLMChangeProposal]
    let summaryUpdates: [LLMSummaryUpdate]
    let canonUpdateSuggestions: [LLMCanonUpdateSuggestion]
    let manualReviewReady: Bool
}

struct LLMDiagnostic: Decodable, Sendable {
    let title: String
    let severity: String
    let scope: String
    let message: String
    let evidence: String
    let reason: String
    let fixLevel: String
    let suggestedFix: String?
}

struct LLMChangeProposal: Decodable, Sendable {
    let title: String
    let reason: String
    let beforeText: String
    let afterText: String
    let riskLevel: String
}

struct LLMSummaryUpdate: Decodable, Sendable {
    let scope: String
    let summary: String
}

struct LLMCanonUpdateSuggestion: Decodable, Sendable {
    let entityType: String
    let name: String
    let fact: String
    let reason: String
}

final class OllamaAIProvider: LocalAIProvider, @unchecked Sendable {
    let backend: LocalAIBackend = .ollama
    private var activeTask: Task<Void, Never>?

    func checkAvailability(settings: OllamaSettings = .default) async -> OllamaHealth {
        do {
            let models = try await listModels(settings: settings)
            return models.isEmpty ? .available(models: []) : .available(models: models)
        } catch {
            let message = Self.friendlyErrorMessage(for: error, endpoint: settings.endpoint)
            return .unavailable(message)
        }
    }

    func listModels(settings: OllamaSettings = .default) async throws -> [String] {
        let url = URL(string: normalizedEndpoint(settings.endpoint) + "api/tags")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.cannotConnectToHost)
        }
        let decoded = try JSONDecoder().decode(OllamaModelsResponse.self, from: data)
        return decoded.models.map(\.name)
    }

    private static func friendlyErrorMessage(for error: Error, endpoint: String) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost:
                return "Cannot connect to \(endpoint). Is Ollama running? Install from ollama.com and open the app, or run `ollama serve`."
            case .timedOut:
                return "Connection timed out (\(endpoint))."
            default:
                break
            }
        }
        return error.localizedDescription
    }

    func runJSONTask<T: Decodable>(prompt: String, model: String, settings: OllamaSettings, as type: T.Type) async throws -> T {
        let strict = prompt + "\n\nRespond with valid JSON only. No markdown. No commentary."
        do {
            return try decodeJSON(from: try await runTextTask(prompt: strict, model: model, settings: settings, keepAlive: keepAliveValue(settings: settings), jsonFormat: true), as: type)
        } catch {
            let retry = strict + "\n\nYour previous response was invalid JSON. Return ONLY a single JSON object matching the schema."
            let text = try await runTextTask(prompt: retry, model: model, settings: settings, keepAlive: keepAliveValue(settings: settings), jsonFormat: true)
            return try decodeJSON(from: text, as: type)
        }
    }

    func runTextTask(prompt: String, model: String, settings: OllamaSettings, keepAlive: String? = nil) async throws -> String {
        try await runTextTask(prompt: prompt, model: model, settings: settings, keepAlive: keepAlive, jsonFormat: false)
    }

    private func runTextTask(prompt: String, model: String, settings: OllamaSettings, keepAlive: String?, jsonFormat: Bool) async throws -> String {
        let endpoint = normalizedEndpoint(settings.endpoint)
        let url = URL(string: endpoint + "api/generate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = settings.timeoutSeconds
        let resolvedKeepAlive = keepAlive ?? keepAliveValue(settings: settings)
        let body = OllamaGenerateRequest(
            model: model.isEmpty ? "llama3.2" : model,
            prompt: prompt,
            stream: false,
            format: jsonFormat ? "json" : nil,
            keep_alive: resolvedKeepAlive,
            options: .init(temperature: settings.temperature, num_predict: settings.maxTokens)
        )
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(OllamaGenerateResponse.self, from: data).response
    }

    func unloadModel(name: String, settings: OllamaSettings) async throws {
        _ = try await runTextTask(prompt: " ", model: name, settings: settings, keepAlive: "0")
    }

    private func keepAliveValue(settings: OllamaSettings) -> String {
        switch settings.resolvedModelSettings.keepAlivePolicy {
        case .quiet, .manual: "0"
        case .balanced: "5m"
        case .intensive: "30m"
        }
    }

    private func decodeJSON<T: Decodable>(from text: String, as type: T.Type) throws -> T {
        guard let data = text.data(using: .utf8) else { throw URLError(.cannotDecodeContentData) }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            if let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") {
                let slice = String(text[start...end])
                if let sliceData = slice.data(using: .utf8) {
                    return try JSONDecoder().decode(T.self, from: sliceData)
                }
            }
            throw error
        }
    }

    func embed(text: String, model: String, settings: OllamaSettings) async throws -> [Float] {
        let endpoint = normalizedEndpoint(settings.endpoint)
        let url = URL(string: endpoint + "api/embeddings")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = settings.timeoutSeconds
        let embedModel = model.isEmpty ? (settings.embeddingModelName.isEmpty ? "nomic-embed-text" : settings.embeddingModelName) : model
        let body = OllamaEmbedRequest(model: embedModel, prompt: text)
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(OllamaEmbedResponse.self, from: data).embedding.map(Float.init)
    }

    private func normalizedEndpoint(_ endpoint: String) -> String {
        endpoint.hasSuffix("/") ? endpoint : endpoint + "/"
    }

    func cancelTask() { activeTask?.cancel(); activeTask = nil }
    func estimateContextLimit(model: String) -> Int { 8192 }
    func estimateRuntimeCost(promptTokens: Int) -> String { "~\(promptTokens) tokens" }
}

struct StubAIProvider: LocalAIProvider {
    let backend: LocalAIBackend
    func checkAvailability(settings: OllamaSettings) async -> OllamaHealth { .unavailable("\(backend.rawValue) not implemented") }
    func listModels(settings: OllamaSettings) async throws -> [String] { [] }
    func runJSONTask<T: Decodable>(prompt: String, model: String, settings: OllamaSettings, as type: T.Type) async throws -> T {
        throw URLError(.unsupportedURL)
    }
    func runTextTask(prompt: String, model: String, settings: OllamaSettings, keepAlive: String?) async throws -> String {
        throw URLError(.unsupportedURL)
    }
    func embed(text: String, model: String, settings: OllamaSettings) async throws -> [Float] {
        throw URLError(.unsupportedURL)
    }
    func unloadModel(name: String, settings: OllamaSettings) async throws {
        throw URLError(.unsupportedURL)
    }
    func cancelTask() {}
    func estimateContextLimit(model: String) -> Int { 0 }
    func estimateRuntimeCost(promptTokens: Int) -> String { "N/A" }
}
