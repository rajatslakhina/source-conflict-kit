import Foundation

/// A deterministic, model-free oracle over three signals: measurement disagreement, polarity flip,
/// and mutually exclusive categorical values.
///
/// Its ceiling is deliberate. It will not catch `some providers` widened to `all providers`, and it
/// says so rather than guessing — that is quantifier scope, and it belongs in a propositional
/// checker plugged in through ``ContradictionOracle``. What it does catch is the set of
/// disagreements that survive a similarity score, because the token that reverses a sentence is the
/// one a similarity score weighs least.
public struct LexicalContradictionOracle: ContradictionOracle {
    public let name = "lexical"

    private let vocabulary: ConflictVocabulary
    private let minimumSharedTokens: Int

    /// - Parameter minimumSharedTokens: how much lexical common ground a polarity flip needs before
    ///   it counts. Two passages on one topic can still be about different properties of it, and a
    ///   bare negation somewhere in an unrelated clause is not a contradiction.
    public init(vocabulary: ConflictVocabulary = .english, minimumSharedTokens: Int = 2) {
        self.vocabulary = vocabulary
        self.minimumSharedTokens = minimumSharedTokens
    }

    public func judge(_ lhs: Passage, _ rhs: Passage) -> OracleVerdict {
        let left = TextFacts(text: lhs.text, vocabulary: vocabulary)
        let right = TextFacts(text: rhs.text, vocabulary: vocabulary)

        var conflicts: [String] = []
        var agreements: [String] = []

        if let signal = polarity(left, right) {
            conflicts.append(signal)
        }
        for signal in [numeric(left, right)].compactMap({ $0 }) + exclusive(left, right) {
            if signal.isConflict {
                conflicts.append(signal.reason)
            } else {
                agreements.append(signal.reason)
            }
        }

        // Conflict outranks agreement rather than being averaged with it. Two passages that quote
        // the same number and disagree about whether it applies are in conflict, and a scheme that
        // let the matching number cancel the negation would report the pair as corroborating.
        if !conflicts.isEmpty {
            return .conflicts(reason: conflicts.sorted().joined(separator: "; "))
        }
        if !agreements.isEmpty {
            return .agrees(reason: agreements.sorted().joined(separator: "; "))
        }
        return .unrelated
    }

    /// Never returns agreement. Matching polarity over shared words is exactly lexical overlap, and
    /// treating it as evidence would convert the signal this package distrusts back into a vote.
    ///
    /// Names no side. `judge(a, b)` and `judge(b, a)` must produce the same reason, and "left is
    /// negated" would silently make the verdict depend on which passage the grouper happened to
    /// enumerate first.
    private func polarity(_ lhs: TextFacts, _ rhs: TextFacts) -> String? {
        guard lhs.isNegated != rhs.isNegated else { return nil }
        let shared = lhs.contentTokens.intersection(rhs.contentTokens)
        guard shared.count >= minimumSharedTokens else { return nil }
        return "polarity: one side is negated over \(shared.count) shared terms"
    }

    /// Requires exactly one measurement on each side. A passage carrying two numbers gives no way
    /// to tell which one the topic is about, and picking the first would be a coin flip wearing a
    /// rule's clothes.
    ///
    /// Values are reported low-first so the reason is a property of the pair, not of the order.
    private func numeric(_ lhs: TextFacts, _ rhs: TextFacts) -> Signal? {
        guard let left = lhs.measurements.first, let right = rhs.measurements.first,
              lhs.measurements.count == 1, rhs.measurements.count == 1,
              left.unit == right.unit else { return nil }
        if left.value == right.value {
            return Signal(isConflict: false, reason: "numeric: both state \(left.rendered)")
        }
        let ordered = [left, right].sorted { $0.value < $1.value }.map(\.rendered)
        return Signal(isConflict: true, reason: "numeric: \(ordered[0]) vs \(ordered[1])")
    }

    /// Members are reported alphabetically, for the same symmetry reason as `numeric`.
    private func exclusive(_ lhs: TextFacts, _ rhs: TextFacts) -> [Signal] {
        lhs.exclusiveHits.compactMap { index, leftMember in
            guard let rightMember = rhs.exclusiveHits[index] else { return nil }
            if leftMember == rightMember {
                return Signal(isConflict: false, reason: "exclusive: both state \(leftMember)")
            }
            let ordered = [leftMember, rightMember].sorted()
            return Signal(isConflict: true, reason: "exclusive: \(ordered[0]) vs \(ordered[1])")
        }
    }

    private struct Signal {
        let isConflict: Bool
        let reason: String
    }
}
