import Foundation

/// The word lists the built-in oracle reasons over, kept out of the oracle so a caller can swap
/// the domain without forking the logic.
///
/// `exclusiveSets` is the one a caller almost always needs to extend. Whether `staging` and
/// `production` are mutually exclusive is a fact about somebody's deployment model, not about
/// English, and a package that hard-coded an opinion there would be wrong in most codebases.
public struct ConflictVocabulary: Sendable {
    public let negationCues: Set<String>
    public let exclusiveSets: [Set<String>]
    public let stopWords: Set<String>
    public let unitAliases: [String: String]

    public init(
        negationCues: Set<String>,
        exclusiveSets: [Set<String>],
        stopWords: Set<String>,
        unitAliases: [String: String]
    ) {
        self.negationCues = negationCues
        self.exclusiveSets = exclusiveSets
        self.stopWords = stopWords
        self.unitAliases = unitAliases
    }

    public static let english = ConflictVocabulary(
        negationCues: [
            "not", "no", "never", "cannot", "cant", "wont", "isnt", "arent",
            "doesnt", "dont", "didnt", "without", "neither", "nor", "none"
        ],
        exclusiveSets: [
            ["enabled", "disabled"],
            ["supported", "deprecated", "removed"],
            ["available", "unavailable"],
            ["required", "optional"],
            ["synchronous", "asynchronous"],
            ["allowed", "forbidden"]
        ],
        stopWords: [
            "a", "an", "and", "are", "as", "at", "be", "been", "by", "for", "from",
            "has", "have", "in", "is", "it", "its", "of", "on", "or", "that", "the",
            "this", "to", "was", "were", "will", "with"
        ],
        unitAliases: [
            "sec": "s", "secs": "s", "second": "s", "seconds": "s",
            "millisecond": "ms", "milliseconds": "ms", "msec": "ms",
            "minute": "min", "minutes": "min", "mins": "min",
            "hour": "h", "hours": "h", "hr": "h", "hrs": "h",
            "megabyte": "mb", "megabytes": "mb",
            "gigabyte": "gb", "gigabytes": "gb",
            "kilobyte": "kb", "kilobytes": "kb",
            "percent": "%", "pct": "%"
        ]
    )
}
