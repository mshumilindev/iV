import Foundation

enum ProposalAcceptPolicy {
    /// Spec: optional confirm for chapter-level / high-risk / large creative proposals.
    static func requiresConfirmation(_ proposal: ChangeProposal) -> Bool {
        if proposal.riskLevel == .high { return true }
        if proposal.scope == .chapter || proposal.scope == .document { return true }
        if proposal.source == .chapterSplit || proposal.source == .sceneExpansion { return true }
        let changeSize = max(proposal.beforeText.count, proposal.afterText.count)
        return changeSize > 800
    }
}
