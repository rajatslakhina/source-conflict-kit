import Foundation

/// Audits a retrieved set for internal disagreement before any of it reaches a model.
///
/// The stage this occupies is the point of the package. Everything downstream — grounding, claim
/// consistency, citation checking — judges an answer that has already been generated and paid for.
/// This runs before the request, on evidence alone, and the cheapest contradiction to handle is the
/// one caught while it is still two documents rather than one confident paragraph.
///
/// Deliberately incapable of retrieval, ranking, or calling a model. Every verdict is derivable
/// from the passages in front of it and the oracle it was handed, which is what makes an audit
/// reproducible at no cost.
public actor ConflictAuditor {
    private let oracle: any ContradictionOracle
    private let ladder: ResolutionLadder
    private var stats = ConflictStatistics()
    private var trail: [ConflictEvent] = []
    private var sequence = 0

    public init(
        oracle: any ContradictionOracle = LexicalContradictionOracle(),
        ladder: ResolutionLadder = .standard
    ) {
        self.oracle = oracle
        self.ladder = ladder
    }

    public func audit(
        _ passages: [Passage],
        policy: ConflictPolicy = .strict,
        at tick: Int
    ) throws -> ConflictReport {
        try ConflictAuditor.validate(passages)
        record(.auditStarted(passages: passages.count, oracle: oracle.name), at: tick)

        var findings: [ConflictFinding] = []
        var withheld: Set<String> = []
        var blocked: [String] = []

        for group in ConflictGrouper.groups(in: passages, oracle: oracle) {
            let topic = group.topic.normalized
            record(.conflictFound(topic: topic, positions: group.positions.count), at: tick)
            let resolution = ladder.resolve(group.positions)

            switch resolution {
            case .resolved(let winner, let rule):
                record(.conflictResolved(topic: topic, by: rule), at: tick)
                if policy.withholdsLosers {
                    let members = group.positions.flatMap(\.passageIDs)
                    withheld.formUnion(members.filter { !winner.contains($0) })
                }
            case .unresolved(let tried):
                record(.conflictUnresolved(topic: topic, tried: tried), at: tick)
                if policy.blocksOnUnresolved {
                    blocked.append(topic)
                }
            }

            findings.append(
                ConflictFinding(
                    topic: group.topic,
                    positions: group.positions,
                    reasons: group.reasons,
                    resolution: resolution
                )
            )
        }

        let decision = ConflictAuditor.decision(
            blocked: blocked,
            withheld: withheld,
            hasFindings: !findings.isEmpty
        )
        record(.decisionReached(kind: decision.kind), at: tick)

        let report = ConflictReport(
            findings: findings,
            admitted: passages.map(\.id).filter { !withheld.contains($0) }.sorted(),
            withheld: withheld.sorted(),
            decision: decision
        )
        stats.record(report)
        return report
    }

    public func statistics() -> ConflictStatistics {
        stats
    }

    public func events() -> [ConflictEvent] {
        trail
    }

    /// Duplicate IDs are refused rather than deduplicated. Two passages sharing an ID would be
    /// merged by every map in the grouper, so one of them would vanish silently — and a passage
    /// that disappears between retrieval and the audit is the one nobody thinks to look for.
    private static func validate(_ passages: [Passage]) throws {
        guard !passages.isEmpty else { throw SourceConflictError.noPassages }
        var seen: Set<String> = []
        for passage in passages {
            guard seen.insert(passage.id).inserted else {
                throw SourceConflictError.duplicateID(passage.id)
            }
            let trimmed = passage.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw SourceConflictError.emptyText(id: passage.id)
            }
        }
    }

    private static func decision(
        blocked: [String],
        withheld: Set<String>,
        hasFindings: Bool
    ) -> AuditDecision {
        guard blocked.isEmpty else { return .blocked(topics: blocked.sorted()) }
        guard hasFindings else { return .clear }
        return .flagged(withheld: withheld.sorted())
    }

    private func record(_ kind: ConflictEvent.Kind, at tick: Int) {
        sequence += 1
        trail.append(ConflictEvent(sequence: sequence, tick: tick, kind: kind))
    }
}
