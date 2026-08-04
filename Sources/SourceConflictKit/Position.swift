import Foundation

/// One camp inside a conflict: the passages that say the same thing, and what they are worth.
///
/// Positions rather than passages are what a tie-breaker compares. Three chunks asserting `30s` are
/// one claim made three times, and a rule that counted passages would let whichever document
/// happened to be chunked most finely win an argument on volume.
///
/// `sourceIDs` is deduplicated for exactly that reason: **corroboration is counted in distinct
/// documents, not in retrieved rows.** Two chunks of one PDF agreeing with each other is one voice.
public struct Position: Sendable, Equatable {
    public let passageIDs: [String]
    public let sourceIDs: [String]
    public let maxAuthority: AuthorityTier
    public let maxRevision: Int?

    /// How many independent documents back this position.
    public var corroboration: Int { sourceIDs.count }

    init(passages: [Passage]) {
        passageIDs = passages.map(\.id).sorted()
        sourceIDs = Set(passages.map(\.provenance.sourceID)).sorted()
        maxAuthority = passages.map(\.provenance.authority).reduce(.unverified) { Swift.max($0, $1) }
        // A position whose documents carry no revision at all cannot be ranked by recency, and
        // `nil` says so. Substituting zero here would silently rank an undated document as the
        // oldest thing in the room rather than as an unknown.
        maxRevision = passages.compactMap(\.provenance.revision).max()
    }
}
