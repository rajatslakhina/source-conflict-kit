import Foundation

/// A conflict as the grouper found it, before any tie-breaking.
struct ConflictGroup {
    let topic: TopicKey
    let positions: [Position]
    let reasons: [String]
}

/// Turns pairwise verdicts into topic-scoped conflict groups made of positions.
///
/// The work here is the part an oracle cannot do alone. An oracle sees two passages; the question a
/// caller actually has is "which camps exist on this topic, and how many independent documents back
/// each one" — and that only exists once every pair has been judged and the results reconciled.
enum ConflictGrouper {
    /// Passages are bucketed by topic and compared only within a bucket. Comparing across topics
    /// would report `timeout is 30s` against `retries are 5` as a numeric disagreement, which is
    /// the false positive that teaches a reader to stop reading the report.
    static func groups(in passages: [Passage], oracle: any ContradictionOracle) -> [ConflictGroup] {
        Dictionary(grouping: passages, by: \.topic)
            .sorted { $0.key.normalized < $1.key.normalized }
            .compactMap { group(in: $0.value, topic: $0.key, oracle: oracle) }
    }

    private static func group(
        in bucket: [Passage],
        topic: TopicKey,
        oracle: any ContradictionOracle
    ) -> ConflictGroup? {
        let ordered = bucket.sorted { $0.id < $1.id }
        var conflicts: [Edge] = []
        var agreements: [Edge] = []
        var reasons: [String] = []

        for left in 0..<ordered.count {
            for right in (left + 1)..<ordered.count {
                let edge = Edge(ordered[left].id, ordered[right].id)
                switch oracle.judge(ordered[left], ordered[right]) {
                case .conflicts(let reason):
                    conflicts.append(edge)
                    reasons.append("\(edge.low) vs \(edge.high) — \(reason)")
                case .agrees:
                    agreements.append(edge)
                case .unrelated:
                    break
                }
            }
        }

        guard !conflicts.isEmpty else { return nil }

        let involved = Set(conflicts.flatMap { [$0.low, $0.high] })
        let positions = camps(over: ordered, agreements: agreements, conflicts: Set(conflicts))
            .filter { camp in camp.contains { involved.contains($0.id) } }
            .map(Position.init(passages:))
            .sorted { $0.passageIDs.joined() < $1.passageIDs.joined() }

        return ConflictGroup(topic: topic, positions: positions, reasons: reasons.sorted())
    }

    /// Merges passages that agree, refusing any merge that would place two passages known to
    /// conflict into one camp.
    ///
    /// Agreement is not transitive when an oracle is imperfect: A may agree with B and B with C
    /// while A and C conflict outright. Honouring the chain would produce a camp that contradicts
    /// itself and then votes as one voice. The conflict edge wins, and the chain breaks where the
    /// evidence says it should.
    ///
    /// A camp that already spans both ends of an agreement edge is skipped rather than merged with
    /// itself — three mutually agreeing passages produce three edges, and only two of them do work.
    private static func camps(
        over passages: [Passage],
        agreements: [Edge],
        conflicts: Set<Edge>
    ) -> [[Passage]] {
        var camps: [[Passage]] = passages.map { [$0] }
        for edge in agreements.sorted() {
            let left = camps.firstIndex { $0.contains { $0.id == edge.low } }
            let right = camps.firstIndex { $0.contains { $0.id == edge.high } }
            guard let left, let right, left != right else { continue }
            let merged = camps[left] + camps[right]
            guard !contradicts(merged, conflicts) else { continue }
            camps.remove(at: Swift.max(left, right))
            camps.remove(at: Swift.min(left, right))
            camps.append(merged)
        }
        return camps
    }

    private static func contradicts(_ camp: [Passage], _ conflicts: Set<Edge>) -> Bool {
        let ids = camp.map(\.id).sorted()
        for left in 0..<ids.count {
            for right in (left + 1)..<ids.count
            where conflicts.contains(Edge(ids[left], ids[right])) {
                return true
            }
        }
        return false
    }

    /// An unordered pair, normalized so `(a, b)` and `(b, a)` are the same edge and hash alike.
    struct Edge: Hashable, Comparable {
        let low: String
        let high: String

        init(_ lhs: String, _ rhs: String) {
            low = Swift.min(lhs, rhs)
            high = Swift.max(lhs, rhs)
        }

        static func < (lhs: Edge, rhs: Edge) -> Bool {
            (lhs.low, lhs.high) < (rhs.low, rhs.high)
        }
    }
}
