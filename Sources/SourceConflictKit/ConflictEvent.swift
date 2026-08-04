import Foundation

/// One entry in the audit trail.
///
/// `tick` is supplied by the caller rather than read from a clock, so an audit replays to the same
/// trail on any machine at any time. That is the difference between a trail you can assert on in a
/// test and one you can only eyeball.
public struct ConflictEvent: Sendable, Equatable {
    public let sequence: Int
    public let tick: Int
    public let kind: Kind

    public enum Kind: Sendable, Equatable {
        case auditStarted(passages: Int, oracle: String)
        case conflictFound(topic: String, positions: Int)
        case conflictResolved(topic: String, by: ResolutionRule)
        case conflictUnresolved(topic: String, tried: [ResolutionRule])
        case decisionReached(kind: String)
    }
}
