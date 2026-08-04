import Foundation

/// What the ladder concluded about one conflict.
public enum Resolution: Sendable, Equatable {
    /// A single position won, and the rule that decided it is named. The rule is part of the
    /// verdict rather than a log line: "the official spec won" and "the majority won" are different
    /// claims about the same passages, and a reviewer needs to know which one was made.
    case resolved(winner: [String], by: ResolutionRule)
    /// Every rule declined. `tried` lists them in the order they ran.
    case unresolved(tried: [ResolutionRule])
}

/// One topic on which the retrieved passages disagree.
public struct ConflictFinding: Sendable, Equatable {
    public let topic: TopicKey
    public let positions: [Position]
    public let reasons: [String]
    public let resolution: Resolution

    public init(
        topic: TopicKey,
        positions: [Position],
        reasons: [String],
        resolution: Resolution
    ) {
        self.topic = topic
        self.positions = positions
        self.reasons = reasons
        self.resolution = resolution
    }
}

/// What the caller should do with the retrieved set.
public enum AuditDecision: Sendable, Equatable {
    /// No topic had two positions. Send everything.
    case clear
    /// Conflicts were found and handled under the policy. `withheld` is empty under a policy that
    /// does not withhold, which is why the finding list, not this case, is the record of what
    /// happened.
    case flagged(withheld: [String])
    /// At least one conflict could not be resolved and the policy blocks on that. Do not generate.
    ///
    /// This is the case the package exists for. Handing a model two passages that contradict each
    /// other, with nothing to say which is right, does not produce a hedged answer — it produces a
    /// confident answer built on whichever passage happened to land closer to the prompt.
    case blocked(topics: [String])

    var kind: String {
        switch self {
        case .clear: return "clear"
        case .flagged: return "flagged"
        case .blocked: return "blocked"
        }
    }
}

/// The audit result: what disagreed, what survived, and what to do next.
public struct ConflictReport: Sendable, Equatable {
    public let findings: [ConflictFinding]
    public let admitted: [String]
    public let withheld: [String]
    public let decision: AuditDecision

    public init(
        findings: [ConflictFinding],
        admitted: [String],
        withheld: [String],
        decision: AuditDecision
    ) {
        self.findings = findings
        self.admitted = admitted
        self.withheld = withheld
        self.decision = decision
    }
}
