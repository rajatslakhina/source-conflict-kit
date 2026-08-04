import Foundation

/// How much weight a source is entitled to before anyone reads what it says.
///
/// Authority is declared by the caller at ingestion, not inferred from the text. A passage cannot
/// argue its way up a tier by sounding confident, which is the whole point: the tier is the part of
/// the decision that an injected document is not allowed to influence.
public enum AuthorityTier: Int, Sendable, Hashable, Comparable, CaseIterable {
    /// Anonymous or unattributed text. Admissible as evidence, never as a tie-breaker's winner.
    case unverified = 0
    /// Forums, blogs, third-party write-ups.
    case community = 1
    /// The vendor's own documentation or release notes.
    case vendor = 2
    /// A normative specification, contract, or system of record.
    case official = 3

    public static func < (lhs: AuthorityTier, rhs: AuthorityTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Where a passage came from, in the two dimensions that can break a tie.
///
/// `sourceID` identifies the **document**, not the chunk. Two passages retrieved from the same
/// document share one `sourceID`, and that is what stops a long document from out-voting a short
/// one purely by being chunked more times.
///
/// `revision` is a caller-supplied monotonic ordinal rather than a date. A package that reads the
/// clock cannot be replayed, and a package that parses dates inherits a timezone bug it did not
/// write. The caller already knows which of its documents is newer; it passes that in.
public struct Provenance: Sendable, Hashable {
    public let sourceID: String
    public let authority: AuthorityTier
    public let revision: Int?

    public init(sourceID: String, authority: AuthorityTier = .unverified, revision: Int? = nil) {
        self.sourceID = sourceID
        self.authority = authority
        self.revision = revision
    }
}

/// One retrieved chunk, scoped to the topic it makes an assertion about.
///
/// The topic is supplied rather than inferred. A retrieval pipeline already knows what facet it
/// asked for, and guessing it here would require the model this package exists to run without.
public struct Passage: Sendable, Hashable, Identifiable {
    public let id: String
    public let text: String
    public let topic: TopicKey
    public let provenance: Provenance

    public init(id: String, text: String, topic: TopicKey, provenance: Provenance) {
        self.id = id
        self.text = text
        self.topic = topic
        self.provenance = provenance
    }
}
