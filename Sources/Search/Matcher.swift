import Foundation

enum Matcher {
    private static let wordBoundaries: Set<Character> = [" ", "-", "_", ".", "/"]

    private static let exactMatchBonus = 1000
    private static let startBonus = 100
    private static let wordBoundaryBonus = 50
    private static let consecutiveBonus = 15
    private static let gapPenalty = 1

    static func score(query: String, target: String) -> Int? {
        if query.isEmpty { return 0 }
        let q = Array(query.lowercased())
        let t = Array(target.lowercased())

        if q == t { return exactMatchBonus }

        var score = 0
        var qi = 0
        var lastMatchIndex: Int? = nil

        for ti in 0..<t.count {
            if qi >= q.count { break }
            if t[ti] == q[qi] {
                if ti == 0 {
                    score += startBonus
                } else if wordBoundaries.contains(t[ti - 1]) {
                    score += wordBoundaryBonus
                }
                if let last = lastMatchIndex {
                    if ti == last + 1 {
                        score += consecutiveBonus
                    } else {
                        score -= gapPenalty * (ti - last - 1)
                    }
                }
                lastMatchIndex = ti
                qi += 1
            }
        }

        return qi == q.count ? score : nil
    }
}
