import Foundation

/// What one oracle concluded about one pair of passages.
///
/// `unrelated` is not a weaker `agrees`. It means the oracle found no evidence in either direction,
/// and the difference matters downstream: agreement merges two passages into a single position that
/// votes once, while no-evidence leaves them apart. Collapsing the two would turn silence into
/// corroboration, which is how a lexical similarity score ends up deciding a factual dispute.
public enum OracleVerdict: Sendable, Equatable {
    case conflicts(reason: String)
    case agrees(reason: String)
    case unrelated
}

/// The seam this package is built around: someone else decides whether two passages disagree.
///
/// Grouping, corroboration counting and tie-breaking are the parts that are genuinely hard to get
/// right and genuinely reusable. Pairwise contradiction detection is the part that everyone wants
/// to do differently — an NLI model, a propositional rule engine, a domain schema — so it is a
/// protocol rather than an implementation. ``LexicalContradictionOracle`` ships as a working
/// default so the package is useful with no dependencies, not as the recommended one.
public protocol ContradictionOracle: Sendable {
    var name: String { get }

    /// Must be symmetric — `judge(a, b)` and `judge(b, a)` have to agree, because the grouper
    /// evaluates each unordered pair exactly once and the order it picks is an implementation
    /// detail the caller should never be able to observe.
    func judge(_ lhs: Passage, _ rhs: Passage) -> OracleVerdict
}
