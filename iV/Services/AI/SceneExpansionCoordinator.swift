import Foundation

struct LLMSceneExpansionResponse: Decodable, Sendable {
    let expandedProse: String
    let title: String
    let reason: String
    let riskLevel: String
    let diagnostics: [LLMDiagnostic]
}

enum SceneExpansionCoordinator {
    @MainActor
    static func expand(
        skeleton: String,
        outcome: String,
        project: Project,
        document: Document,
        context: ContextPacket,
        coordinator: LocalLLMCoordinator,
        performanceMode: PerformanceMode
    ) async -> Result<ChangeProposal, Error> {
        guard project.ollamaSettings.llmPassesEnabled else {
            return .failure(NSError(domain: "iV.SceneExpansion", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "LLM passes are disabled. Enable in Settings."
            ]))
        }

        let prompt = """
        Expand the scene skeleton into prose. Return JSON only with keys:
        expandedProse, title, reason, riskLevel (low|medium|high), diagnostics (array, may be empty).

        Required outcome: \(outcome)
        POV / constraints: use edit rules and canon below.
        Do not add meta commentary. Write in the manuscript language.

        Skeleton:
        \(skeleton)

        Scene summary: \(context.sceneSummary ?? "")
        Relevant rules:
        \(context.relevantEditRules.prefix(5).map { "[\($0.fileName)] \($0.content.prefix(300))" }.joined(separator: "\n"))

        Canon:
        \(context.relevantCanon.map { $0.name + ": " + $0.description.prefix(200) }.joined(separator: "\n"))
        """

        do {
            let settings = project.ollamaSettings
            let response = try await coordinator.runJSONTask(
                task: .sceneExpansion,
                prompt: prompt,
                settings: settings,
                performanceMode: performanceMode,
                as: LLMSceneExpansionResponse.self
            )

            let proposal = ChangeProposalService.makeProposal(
                projectID: project.id,
                documentID: document.id,
                scope: .scene,
                scopeID: nil,
                source: .sceneExpansion,
                title: response.title.isEmpty ? "Scene expansion" : response.title,
                reason: response.reason.isEmpty ? outcome : response.reason,
                beforeText: skeleton,
                afterText: response.expandedProse,
                riskLevel: RiskLevel(rawValue: response.riskLevel) ?? .high
            )
            return .success(proposal)
        } catch {
            return .failure(error)
        }
    }
}
