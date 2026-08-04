import Foundation

/// A normalized subject, so that two passages about one thing are compared and two passages about
/// different things are not.
///
/// Normalization matters more than it looks. `"Request Timeout"` and `"the request timeout"` name
/// the same facet, and if they hash differently the two passages never meet — the checker reports
/// no conflict and the caller reads that as agreement. A missed comparison is indistinguishable
/// from a clean bill of health, which makes it the most expensive bug this type can have.
///
/// Tokens are sorted, so word order does not create a second bucket for one subject.
public struct TopicKey: Sendable, Hashable, CustomStringConvertible {
    public let normalized: String

    public var description: String { normalized }

    /// Throws rather than producing an empty key: a topic that normalizes to nothing would collide
    /// with every other empty topic and silently merge unrelated passages into one conflict group.
    public init(_ raw: String) throws {
        let tokens = TopicKey.tokens(in: raw)
        guard !tokens.isEmpty else { throw SourceConflictError.emptyTopic(raw: raw) }
        normalized = tokens.sorted().joined(separator: "-")
    }

    static func tokens(in raw: String) -> [String] {
        raw.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !TopicKey.stopWords.contains($0) }
    }

    static let stopWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "by", "for", "from",
        "in", "is", "of", "on", "or", "the", "to", "with"
    ]
}
