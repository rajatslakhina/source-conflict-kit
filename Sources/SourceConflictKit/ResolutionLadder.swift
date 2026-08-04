import Foundation

/// One way to prefer a position over the others.
///
/// Each rule either names a single strict winner or stands aside. There is deliberately no scoring
/// blend: a weighted combination would produce a winner every time, including when the evidence is
/// a dead heat, and nobody reading the report could tell which of those two cases they were in.
public enum ResolutionRule: String, Sendable, Equatable, CaseIterable {
    /// The highest-tier source present in the position.
    case authority
    /// The newest revision present in the position. Stands aside entirely if any position under
    /// comparison has no revision, because ranking a known date against an unknown one is guessing.
    case recency
    /// The most distinct documents backing the position.
    case corroboration

    func winner(among positions: [Position]) -> Position? {
        switch self {
        case .authority:
            return ResolutionRule.strictMax(positions, positions.map { Double($0.maxAuthority.rawValue) })
        case .recency:
            // Unwrapped rather than defaulted. A `?? Int.min` here would be unreachable behind the
            // count check, and an unreachable fallback reports as covered risk.
            let revisions = positions.compactMap(\.maxRevision)
            guard revisions.count == positions.count else { return nil }
            return ResolutionRule.strictMax(positions, revisions.map(Double.init))
        case .corroboration:
            return ResolutionRule.strictMax(positions, positions.map { Double($0.corroboration) })
        }
    }

    /// Returns a position only when it holds the top score *alone*. A shared maximum is a tie, and
    /// a tie is information — it is what sends the decision down to the next rule.
    private static func strictMax(_ positions: [Position], _ scores: [Double]) -> Position? {
        let top = scores.reduce(-Double.greatestFiniteMagnitude) { Swift.max($0, $1) }
        let leaders = zip(positions, scores).filter { $0.1 == top }.map(\.0)
        guard leaders.count == 1 else { return nil }
        return leaders.first
    }
}

/// An ordered list of tie-breakers, applied until one of them decides or all of them decline.
///
/// The order is the policy. `.standard` puts authority first because a vendor's own release note
/// outranks a forum post regardless of which was published later; recency second, so a newer
/// official document beats an older one; corroboration last, because agreement between equally
/// authoritative and equally dated sources is the weakest of the three signals and the easiest to
/// manufacture by retrieving more chunks.
public struct ResolutionLadder: Sendable, Equatable {
    public let rules: [ResolutionRule]

    /// Rejects an empty ladder and repeated rules. A repeated rule cannot change its mind on the
    /// second pass, so its presence means the author believed something about the ladder that is
    /// not true — better to say so than to run a step that provably does nothing.
    public init(_ rules: [ResolutionRule]) throws {
        guard !rules.isEmpty else { throw SourceConflictError.emptyLadder }
        var seen: Set<ResolutionRule> = []
        for rule in rules {
            guard seen.insert(rule).inserted else {
                throw SourceConflictError.duplicateRule(rule)
            }
        }
        self.rules = rules
    }

    private init(unchecked rules: [ResolutionRule]) {
        self.rules = rules
    }

    public static let standard = ResolutionLadder(unchecked: [.authority, .recency, .corroboration])

    /// Records which rules were consulted on the way to an unresolved verdict, so the caller can
    /// see that the ladder ran and came up empty rather than that it was never configured.
    func resolve(_ positions: [Position]) -> Resolution {
        var tried: [ResolutionRule] = []
        for rule in rules {
            tried.append(rule)
            if let winner = rule.winner(among: positions) {
                return .resolved(winner: winner.passageIDs, by: rule)
            }
        }
        return .unresolved(tried: tried)
    }
}
