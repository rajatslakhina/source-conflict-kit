import Foundation

/// Every way this package refuses input, named.
///
/// Each case describes something the caller can fix. There is deliberately no `.unknown`: a failure
/// nobody can act on is a failure nobody will act on.
public enum SourceConflictError: Error, Equatable, CustomStringConvertible {
    case noPassages
    case emptyText(id: String)
    case emptyTopic(raw: String)
    case duplicateID(String)
    case emptyLadder
    case duplicateRule(ResolutionRule)

    public var description: String {
        switch self {
        case .noPassages:
            return "no passages to audit"
        case .emptyText(let id):
            return "passage '\(id)' has no text"
        case .emptyTopic(let raw):
            return "topic '\(raw)' normalizes to nothing"
        case .duplicateID(let id):
            return "passage id '\(id)' appears more than once"
        case .emptyLadder:
            return "a resolution ladder needs at least one rule"
        case .duplicateRule(let rule):
            return "resolution rule '\(rule.rawValue)' appears more than once"
        }
    }
}
