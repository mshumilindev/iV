import Foundation

/// Decides whether a pipeline pass should invoke the LLM (spec: deterministic first).
enum PipelineLLMPolicy {
    static func shouldRunLLM(
        pass: PipelinePass,
        deterministicDiagnostics: [Diagnostic],
        input: PipelineInput,
        routerDecision: LocalModelRouteDecision
    ) -> Bool {
        guard pass.mode == .llm || pass.mode == .hybrid else { return false }
        guard input.aiProvider != nil else { return false }
        guard routerDecision.execution != .skip, routerDecision.execution != .mechanicalOnly else { return false }

        let scope = pass.scope
        let blocking = deterministicDiagnostics.filter {
            !$0.isStale && $0.severity == .blocking && scopeMatches($0.scope, passScope: scope)
        }
        if !blocking.isEmpty { return false }

        if pass.mode == .hybrid {
            let errors = deterministicDiagnostics.filter {
                !$0.isStale && $0.severity == .error && scopeMatches($0.scope, passScope: scope)
            }
            if errors.count >= 3 { return false }
        }
        return true
    }

    private static func scopeMatches(_ diagnosticScope: RuleScope, passScope: RuleScope) -> Bool {
        diagnosticScope == passScope || diagnosticScope == .paragraph && passScope == .paragraphWindow
    }
}
