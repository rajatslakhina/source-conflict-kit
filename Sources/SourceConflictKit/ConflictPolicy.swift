import Foundation

/// What the caller wants done about a conflict, declared before the audit rather than inferred
/// from its outcome.
public struct ConflictPolicy: Sendable, Equatable {
    /// Whether an unresolved conflict stops generation.
    public let blocksOnUnresolved: Bool
    /// Whether the losing positions of a *resolved* conflict are dropped from the admitted set.
    public let withholdsLosers: Bool

    public init(blocksOnUnresolved: Bool, withholdsLosers: Bool) {
        self.blocksOnUnresolved = blocksOnUnresolved
        self.withholdsLosers = withholdsLosers
    }

    /// Resolve what can be resolved, drop the losers, refuse the rest.
    public static let strict = ConflictPolicy(blocksOnUnresolved: true, withholdsLosers: true)

    /// Report everything and admit everything. Useful when a downstream reranker or a human is the
    /// real arbiter — the findings still name every conflict, so `permissive` means *someone else
    /// decides*, not *nobody noticed*.
    public static let permissive = ConflictPolicy(blocksOnUnresolved: false, withholdsLosers: false)
}
