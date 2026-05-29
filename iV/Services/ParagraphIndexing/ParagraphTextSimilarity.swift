import Foundation

/// Deterministic text similarity for paragraph identity (no ML).
enum ParagraphTextSimilarity {
    /// Ratio in `0...1` — 1 is identical after normalization.
    static func ratio(_ lhs: String, _ rhs: String) -> Double {
        let a = normalize(lhs)
        let b = normalize(rhs)
        if a == b { return 1 }
        if a.isEmpty || b.isEmpty { return 0 }
        let distance = levenshtein(a, b)
        let maxLen = max(a.count, b.count)
        return 1 - (Double(distance) / Double(maxLen))
    }

    /// Weighted blend of previous / current / next paragraph similarity.
    static func contextRatio(
        previousNew: String?,
        currentNew: String,
        nextNew: String?,
        previousOld: String?,
        currentOld: String,
        nextOld: String?
    ) -> Double {
        var weighted = 0.0
        var totalWeight = 0.0

        func add(_ weight: Double, _ new: String?, _ old: String?) {
            guard let new, let old else { return }
            weighted += weight * ratio(new, old)
            totalWeight += weight
        }

        add(0.25, previousNew, previousOld)
        add(0.5, currentNew, currentOld)
        add(0.25, nextNew, nextOld)

        guard totalWeight > 0 else { return ratio(currentNew, currentOld) }
        return weighted / totalWeight
    }

    private static func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs)
        let b = Array(rhs)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)

        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(
                    previous[j] + 1,
                    current[j - 1] + 1,
                    previous[j - 1] + cost
                )
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
