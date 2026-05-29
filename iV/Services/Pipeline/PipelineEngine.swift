import Foundation

struct PipelineInput: Sendable {
    var project: Project
    var document: Document
    var index: DocumentIndex
    var structure: DocumentStructure
    var canon: [CanonEntity]
    var memory: [NarrativeMemory]
    var ruleFiles: [EditRuleFile]
    var diagnostics: [Diagnostic]
    var scope: RuleScope
    var paragraphID: UUID?
    var aiProvider: (any LocalAIProvider)?
    var llmTask: LocalModelTask?
    var routeLLM: ((LocalModelTask) -> LocalModelRouteDecision)?
}

struct PipelinePass: Sendable {
    let id: String
    let name: String
    let scope: RuleScope
    let mode: PipelinePassMode
    let requiredRuleCategories: [EditRuleCategory]
    let run: @Sendable (PipelineInput) async throws -> PipelinePassResult
}

@MainActor
final class PipelineEngine {
    private let deterministic = DeterministicRuleEngine.default
    private let contextBuilder = ContextBuilder()
    private let analysisCoordinator = AnalysisCoordinator()

    func defaultPasses() -> [PipelinePass] {
        [
            pass(id: "minimum-gate", name: "Minimum Gate", mode: .deterministic, categories: [.minimumGate]),
            pass(id: "text-integrity", name: "Text Integrity", mode: .deterministic, categories: [.coreProse]),
            pass(id: "structure", name: "Structure", mode: .deterministic, categories: [.coreProse]),
            pass(id: "causality", name: "Causality / POV", mode: .hybrid, categories: [.causalityPOVLogic, .coreProse]),
            pass(id: "language", name: "Canon / Language", mode: .deterministic, categories: [.canonLanguage]),
            pass(id: "rhythm", name: "Rhythm / Line Control", mode: .deterministic, categories: [.styleLineControl, .coreProse]),
            pass(id: "dialogue", name: "Dialogue", mode: .hybrid, categories: [.dialogue, .characterVoice]),
            pass(id: "character-voice", name: "Character Voice", mode: .llm, categories: [.characterVoice]),
            pass(id: "atmosphere", name: "Atmosphere / Sensory", mode: .hybrid, categories: [.atmosphereSensory]),
            pass(id: "world", name: "World / Information", mode: .llm, categories: [.worldInformation]),
            pass(id: "action", name: "Action / Aftermath", mode: .hybrid, categories: [.actionAftermath]),
            pass(id: "repetition", name: "Repetition / Tautology", mode: .deterministic, categories: [.coreProse]),
            pass(id: "escalation", name: "Escalation / Pacing", mode: .deterministic, categories: [.coreProse]),
            pass(id: "scene-function", name: "Scene Function", mode: .deterministic, categories: [.coreProse]),
            pass(id: "continuity", name: "Multi-Scope Continuity", mode: .hybrid, categories: [.causalityPOVLogic]),
            pass(id: "ai-marker", name: "AI Marker", mode: .llm, categories: [.styleLineControl]),
            pass(id: "manual-review", name: "Manual Review Readiness", mode: .deterministic, categories: [.minimumGate])
        ]
    }

    func run(
        passes: [PipelinePass],
        input: PipelineInput,
        onPassUpdate: @escaping (PipelinePassResult) -> Void
    ) async -> (AnalysisRun, [Diagnostic], [ChangeProposal], [CanonUpdateSuggestion]) {
        var results: [PipelinePassResult] = []
        var allDiagnostics = input.diagnostics
        var proposals: [ChangeProposal] = []
        var canonSuggestions: [CanonUpdateSuggestion] = []
        let runID = UUID()
        let runStarted = Date()

        for pass in passes {
            var result = PipelinePassResult(
                id: pass.id,
                name: pass.name,
                mode: pass.mode,
                status: .running,
                startedAt: Date(),
                finishedAt: nil,
                diagnosticsCreated: 0,
                proposalsCreated: 0,
                ruleFilesUsed: pass.requiredRuleCategories.map(\.rawValue),
                contextScope: pass.scope,
                failureReason: nil,
                deterministicStatus: nil,
                llmStatus: nil
            )
            onPassUpdate(result)

            var detStatus: PipelinePassStatus?
            var llmStatus: PipelinePassStatus?
            var failureNotes: [String] = []

            do {
                if pass.mode == .deterministic || pass.mode == .hybrid {
                    let newDiags = runDeterministicPass(pass: pass, input: input)
                    allDiagnostics.append(contentsOf: newDiags)
                    result.diagnosticsCreated = newDiags.count
                    detStatus = .completed
                    result.deterministicStatus = .completed
                }

                let passDetDiagnostics = allDiagnostics.filter { $0.source == .deterministic }
                let task = input.llmTask ?? LocalLLMCoordinator.task(forPipelinePassID: pass.id)
                let route = input.routeLLM?(task) ?? LocalModelRouteDecision(
                    backend: .ollama,
                    modelName: input.project.ollamaSettings.effectivePrimaryModel,
                    execution: .asyncQueued,
                    skipReason: nil
                )

                if pass.mode == .llm || pass.mode == .hybrid {
                    llmStatus = await resolveLLMPhase(
                        pass: pass,
                        input: input,
                        route: route,
                        passDetDiagnostics: passDetDiagnostics,
                        allDiagnostics: &allDiagnostics,
                        proposals: &proposals,
                        canonSuggestions: &canonSuggestions,
                        result: &result,
                        failureNotes: &failureNotes
                    )
                    result.llmStatus = llmStatus
                }

                if pass.id == "manual-review" {
                    let review = ManualReviewCalculator.status(
                        diagnostics: allDiagnostics,
                        proposals: proposals,
                        passResults: results + [result]
                    )
                    if !review.isReady {
                        result.status = .failed
                        result.failureReason = review.readinessNote ?? "Manual review not ready"
                    } else {
                        result.status = .completed
                        result.failureReason = nil
                    }
                } else {
                    result.status = overallPassStatus(mode: pass.mode, det: detStatus, llm: llmStatus)
                    if failureNotes.isEmpty {
                        result.failureReason = hybridSummaryNote(det: detStatus, llm: llmStatus)
                    } else {
                        let note = failureNotes.joined(separator: "; ")
                        result.failureReason = hybridSummaryNote(det: detStatus, llm: llmStatus).map { "\($0); \(note)" } ?? note
                    }
                }

                result.finishedAt = Date()
            } catch {
                result.status = .failed
                result.failureReason = error.localizedDescription
                result.finishedAt = Date()
                if pass.mode == .hybrid || pass.mode == .llm {
                    llmStatus = .failed
                    result.llmStatus = .failed
                }
                let failDiag = DiagnosticEvidence.llmPassFailure(
                    projectID: input.project.id,
                    documentID: input.document.id,
                    passName: pass.name,
                    error: error.localizedDescription,
                    paragraphID: input.paragraphID
                )
                allDiagnostics.append(failDiag)
                result.diagnosticsCreated += 1
            }

            results.append(result)
            onPassUpdate(result)
        }

        allDiagnostics = dedupeDiagnostics(allDiagnostics)
        let summary = PipelineRunSummary.summarize(passResults: results)
        let analysisRun = AnalysisRun(
            id: runID,
            projectID: input.project.id,
            documentID: input.document.id,
            scope: input.scope,
            scopeID: input.paragraphID,
            pipelineID: "default",
            status: summary.runStatus,
            startedAt: runStarted,
            finishedAt: Date(),
            passResults: results,
            createdDiagnosticIDs: allDiagnostics.map(\.id),
            modelUsed: input.project.ollamaSettings.modelName.nilIfEmpty
        )
        return (analysisRun, allDiagnostics, proposals, canonSuggestions)
    }

    private func resolveLLMPhase(
        pass: PipelinePass,
        input: PipelineInput,
        route: LocalModelRouteDecision,
        passDetDiagnostics: [Diagnostic],
        allDiagnostics: inout [Diagnostic],
        proposals: inout [ChangeProposal],
        canonSuggestions: inout [CanonUpdateSuggestion],
        result: inout PipelinePassResult,
        failureNotes: inout [String]
    ) async -> PipelinePassStatus {
        guard input.project.ollamaSettings.llmPassesEnabled else {
            failureNotes.append("LLM passes disabled in project settings")
            return .skipped
        }
        guard input.aiProvider != nil else {
            failureNotes.append(pass.mode == .hybrid ? "LLM unavailable (Ollama)" : "Ollama unavailable")
            return .unavailable
        }
        guard PipelineLLMPolicy.shouldRunLLM(
            pass: pass,
            deterministicDiagnostics: passDetDiagnostics,
            input: input,
            routerDecision: route
        ) else {
            failureNotes.append(route.skipReason ?? "LLM skipped (deterministic sufficient or policy)")
            return .skipped
        }
        guard let provider = input.aiProvider else { return .unavailable }
        do {
            let llmOutput = try await runLLMPass(pass: pass, input: input, provider: provider, modelName: route.modelName)
            allDiagnostics.append(contentsOf: llmOutput.diagnostics)
            proposals.append(contentsOf: llmOutput.proposals)
            canonSuggestions.append(contentsOf: llmOutput.canonSuggestions)
            result.diagnosticsCreated += llmOutput.diagnostics.count
            result.proposalsCreated = llmOutput.proposals.count
            return .completed
        } catch {
            failureNotes.append("LLM failed: \(error.localizedDescription)")
            let failDiag = DiagnosticEvidence.llmPassFailure(
                projectID: input.project.id,
                documentID: input.document.id,
                passName: pass.name,
                error: error.localizedDescription,
                paragraphID: input.paragraphID
            )
            allDiagnostics.append(failDiag)
            result.diagnosticsCreated += 1
            return .failed
        }
    }

    private func overallPassStatus(
        mode: PipelinePassMode,
        det: PipelinePassStatus?,
        llm: PipelinePassStatus?
    ) -> PipelinePassStatus {
        switch mode {
        case .deterministic:
            return det ?? .completed
        case .llm:
            return llm ?? .unavailable
        case .hybrid:
            if llm == .failed { return .failed }
            if det == .failed { return .failed }
            return .completed
        }
    }

    private func hybridSummaryNote(det: PipelinePassStatus?, llm: PipelinePassStatus?) -> String? {
        guard let llm else { return nil }
        switch llm {
        case .unavailable:
            return det == .completed ? "Deterministic complete; LLM unavailable" : "LLM unavailable"
        case .skipped:
            return det == .completed ? "Deterministic complete; LLM skipped" : "LLM skipped"
        case .failed:
            return det == .completed ? "Deterministic complete; LLM failed" : nil
        default:
            return nil
        }
    }

    private func dedupeDiagnostics(_ diagnostics: [Diagnostic]) -> [Diagnostic] {
        var seen = Set<String>()
        return diagnostics.filter { d in
            let key = "\(d.paragraphID?.uuidString ?? "-")|\(d.source.rawValue)|\(d.title)|\(d.message)"
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }

    private func pass(id: String, name: String, mode: PipelinePassMode, categories: [EditRuleCategory]) -> PipelinePass {
        PipelinePass(id: id, name: name, scope: scopeForPass(id: id), mode: mode, requiredRuleCategories: categories) { _ in
            PipelinePassResult(
                id: id, name: name, mode: mode, status: .pending,
                startedAt: nil, finishedAt: nil, diagnosticsCreated: 0, proposalsCreated: 0,
                ruleFilesUsed: categories.map(\.rawValue), contextScope: nil, failureReason: nil,
                deterministicStatus: nil, llmStatus: nil
            )
        }
    }

    private func scopeForPass(id: String) -> RuleScope {
        switch id {
        case "structure", "scene-function", "dialogue", "atmosphere", "action": .scene
        case "continuity", "escalation": .chapter
        case "repetition": .document
        default: .paragraph
        }
    }

    private func runDeterministicPass(pass: PipelinePass, input: PipelineInput) -> [Diagnostic] {
        if pass.scope == .scene || pass.scope == .chapter || pass.scope == .document {
            let result = analysisCoordinator.runExpandedAnalysis(
                project: input.project,
                document: input.document,
                index: input.index,
                structure: input.structure,
                canon: input.canon,
                ruleFiles: input.ruleFiles,
                paragraphID: input.paragraphID,
                maxScope: pass.scope
            )
            return result.diagnostics
        }
        let paragraph = input.paragraphID.flatMap { id in input.index.paragraphs.map(\.paragraph).first { $0.id == id } }
        let order = paragraph?.order ?? 0
        let paragraphs = input.index.paragraphs.map(\.paragraph)
        let ruleInput = RuleInput(
            project: input.project,
            document: input.document,
            chapter: ManuscriptStructureBuilder.chapter(for: paragraph?.id ?? UUID(), in: input.structure),
            scene: ManuscriptStructureBuilder.scene(for: paragraph?.id ?? UUID(), in: input.structure),
            paragraph: paragraph,
            currentText: paragraph?.text ?? input.document.plainText,
            previousText: order > 0 && paragraphs.indices.contains(order - 1) ? paragraphs[order - 1].text : nil,
            nextText: paragraphs.indices.contains(order + 1) ? paragraphs[order + 1].text : nil,
            canon: input.canon,
            editRules: input.ruleFiles,
            scope: pass.scope
        )
        let violations = deterministic.run(input: ruleInput)
        return deterministic.diagnostics(
            from: violations,
            projectID: input.project.id,
            documentID: input.document.id,
            paragraph: paragraph,
            chapterID: ruleInput.chapter?.id,
            sceneID: ruleInput.scene?.id
        )
    }

    private func runLLMPass(pass: PipelinePass, input: PipelineInput, provider: any LocalAIProvider, modelName: String?) async throws -> (diagnostics: [Diagnostic], proposals: [ChangeProposal], canonSuggestions: [CanonUpdateSuggestion]) {
        let packet = contextBuilder.build(
            task: pass.name,
            scope: pass.scope,
            document: input.document,
            index: input.index,
            paragraphID: input.paragraphID,
            structure: input.structure,
            memory: input.memory,
            canon: input.canon,
            ruleFiles: input.ruleFiles,
            categories: pass.requiredRuleCategories,
            diagnostics: input.diagnostics
        )
        let prompt = PromptBuilder.analysisPrompt(packet: packet)
        let settings = input.project.ollamaSettings
        var model = modelName ?? settings.effectivePrimaryModel
        if model.isEmpty { model = settings.modelName }
        if model.isEmpty { model = (try? await provider.listModels(settings: settings).first) ?? "llama3.2" }
        let response = try await provider.runJSONTask(prompt: prompt, model: model, settings: settings, as: LLMAnalysisResponse.self)
        return mapLLMResponse(response, input: input, paragraphID: input.paragraphID)
    }

    private func mapLLMResponse(_ response: LLMAnalysisResponse, input: PipelineInput, paragraphID: UUID?) -> (diagnostics: [Diagnostic], proposals: [ChangeProposal], canonSuggestions: [CanonUpdateSuggestion]) {
        let paragraphText = paragraphID.flatMap { pid in
            input.index.paragraphs.first { $0.paragraph.id == pid }?.paragraph.text
        }
        let paragraphHash = paragraphID.flatMap { pid in
            input.index.paragraphs.first { $0.paragraph.id == pid }?.paragraph.hash
        }
        let diags = response.diagnostics.map { d -> Diagnostic in
            Diagnostic(
                id: UUID(),
                projectID: input.project.id,
                documentID: input.document.id,
                chapterID: nil,
                sceneID: nil,
                paragraphID: paragraphID,
                ruleID: nil,
                source: .llm,
                severity: RuleSeverity(rawValue: d.severity) ?? .warning,
                scope: RuleScope(rawValue: d.scope) ?? input.scope,
                title: d.title,
                message: d.message,
                evidence: DiagnosticEvidence.clamp(d.evidence, paragraphText: paragraphText),
                startOffset: nil,
                endOffset: nil,
                suggestedFix: d.suggestedFix,
                fixLevel: FixLevel(rawValue: d.fixLevel) ?? .humanOnly,
                status: .open,
                textHashAtCreation: paragraphHash,
                scopeHashAtCreation: nil,
                isStale: false,
                staleReason: nil,
                createdAt: Date()
            )
        }
        let proposals = response.changeProposals.map { p in
            ChangeProposalService.makeProposal(
                projectID: input.project.id,
                documentID: input.document.id,
                scope: input.scope,
                scopeID: paragraphID,
                source: .llm,
                title: p.title,
                reason: p.reason,
                beforeText: p.beforeText,
                afterText: p.afterText,
                riskLevel: RiskLevel(rawValue: p.riskLevel) ?? .medium
            )
        }
        let canon = response.canonUpdateSuggestions.map {
            CanonUpdateSuggestion(from: $0, projectID: input.project.id, source: .pipeline)
        }
        return (diags, proposals, canon)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

enum PromptBuilder {
    static func analysisPrompt(packet: ContextPacket) -> String {
        """
        Analyze prose for editorial issues. Return JSON matching schema with diagnostics and changeProposals arrays.
        Task: \(packet.task)
        Scope: \(packet.scope.rawValue)
        Current text:
        \(packet.currentText)
        Previous:
        \(packet.previousText ?? "")
        Next:
        \(packet.nextText ?? "")
        Rules:
        \(packet.relevantEditRules.map { "[\($0.fileName)] \($0.heading): \($0.content.prefix(500))" }.joined(separator: "\n"))
        """
    }
}
