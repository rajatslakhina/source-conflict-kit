import Foundation
import XCTest
@testable import SourceConflictKit

enum Fix {
    static func passage(
        _ id: String,
        _ text: String,
        topic: TopicKey,
        source: String? = nil,
        authority: AuthorityTier = .unverified,
        revision: Int? = nil
    ) -> Passage {
        Passage(
            id: id,
            text: text,
            topic: topic,
            provenance: Provenance(
                sourceID: source ?? id,
                authority: authority,
                revision: revision
            )
        )
    }

    static func position(
        _ ids: [String],
        topic: TopicKey,
        sources: [String]? = nil,
        authority: AuthorityTier = .unverified,
        revision: Int? = nil
    ) -> Position {
        Position(
            passages: zip(ids, sources ?? ids).map { id, source in
                passage(
                    id,
                    "text for \(id)",
                    topic: topic,
                    source: source,
                    authority: authority,
                    revision: revision
                )
            }
        )
    }
}

/// An oracle that answers from a table, so grouping can be tested independently of any text
/// analysis — including with answers no real oracle would give.
struct ScriptedOracle: ContradictionOracle {
    let name = "scripted"
    let verdicts: [String: OracleVerdict]

    init(_ verdicts: [String: OracleVerdict]) {
        self.verdicts = verdicts
    }

    func judge(_ lhs: Passage, _ rhs: Passage) -> OracleVerdict {
        verdicts[[lhs.id, rhs.id].sorted().joined(separator: "|")] ?? .unrelated
    }
}
