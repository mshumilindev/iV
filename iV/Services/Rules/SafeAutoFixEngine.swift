import Foundation

struct SafeAutoFixEngine: Sendable {
    struct FixApplication: Sendable {
        var original: String
        var fixed: String
        var description: String
    }

    func apply(to text: String, canon: [CanonEntity] = [], terminology: [String: String] = [:]) -> FixApplication? {
        var result = text
        var changes: [String] = []

        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
            changes.append("Removed double spaces")
        }

        result = result.replacingOccurrences(of: "—", with: "—")
        result = result.replacingOccurrences(of: "--", with: "—")
        result = result.replacingOccurrences(of: "''", with: "\"")
        result = result.replacingOccurrences(of: "‘", with: "'").replacingOccurrences(of: "’", with: "'")

        for (from, to) in terminology where from != to {
            if result.contains(from) {
                result = result.replacingOccurrences(of: from, with: to)
                changes.append("Terminology: \(from) → \(to)")
            }
        }

        for entity in canon where entity.type == .term || entity.type == .character {
            for alias in entity.aliases where !alias.isEmpty && result.contains(alias) && alias != entity.name {
                result = result.replacingOccurrences(of: alias, with: entity.name)
                changes.append("Canon spelling: \(alias) → \(entity.name)")
            }
        }

        guard result != text else { return nil }
        return FixApplication(original: text, fixed: result, description: changes.joined(separator: "; "))
    }

    func canAutoFix(diagnostic: Diagnostic) -> Bool {
        diagnostic.fixLevel == .safeAutoFix
    }
}
