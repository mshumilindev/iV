import Foundation

enum PipelineRunSummary {
    struct Outcome: Sendable {
        var runStatus: AnalysisRunStatus
        var statusLabel: String
        var unavailableLLMPasses: Int
        var skippedLLMPasses: Int
        var failedPasses: Int
    }

    static func summarize(passResults: [PipelinePassResult]) -> Outcome {
        var unavailable = 0
        var skipped = 0
        var failed = 0
        for pass in passResults {
            if pass.status == .failed { failed += 1 }
            if let llm = pass.llmStatus {
                switch llm {
                case .unavailable: unavailable += 1
                case .skipped: skipped += 1
                case .failed: failed += 1
                default: break
                }
            } else if pass.mode == .llm, pass.status == .unavailable {
                unavailable += 1
            }
        }
        if failed > 0 {
            return Outcome(
                runStatus: .failed,
                statusLabel: "Pipeline failed (\(failed) pass\(failed == 1 ? "" : "es"))",
                unavailableLLMPasses: unavailable,
                skippedLLMPasses: skipped,
                failedPasses: failed
            )
        }
        if unavailable > 0 || skipped > 0 {
            var parts: [String] = ["Completed with gaps"]
            if unavailable > 0 { parts.append("\(unavailable) LLM unavailable") }
            if skipped > 0 { parts.append("\(skipped) LLM skipped") }
            return Outcome(
                runStatus: .completed,
                statusLabel: parts.joined(separator: " · "),
                unavailableLLMPasses: unavailable,
                skippedLLMPasses: skipped,
                failedPasses: 0
            )
        }
        return Outcome(
            runStatus: .completed,
            statusLabel: "Completed",
            unavailableLLMPasses: 0,
            skippedLLMPasses: 0,
            failedPasses: 0
        )
    }
}
