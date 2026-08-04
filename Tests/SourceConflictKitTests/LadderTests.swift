import Foundation
import XCTest
@testable import SourceConflictKit

final class PositionTests: XCTestCase {
    func testCorroborationCountsDocumentsNotPassages() throws {
        let topic = try TopicKey("request timeout")
        let position = Fix.position(
            ["p1", "p2", "p3"],
            topic: topic,
            sources: ["doc-a", "doc-a", "doc-a"]
        )
        XCTAssertEqual(position.passageIDs, ["p1", "p2", "p3"])
        XCTAssertEqual(position.corroboration, 1)
        XCTAssertEqual(position.sourceIDs, ["doc-a"])
    }

    func testTakesTheHighestAuthorityAndRevisionPresent() throws {
        let topic = try TopicKey("request timeout")
        let position = Position(
            passages: [
                Fix.passage("p1", "a", topic: topic, authority: .community, revision: 2),
                Fix.passage("p2", "b", topic: topic, authority: .official, revision: nil),
                Fix.passage("p3", "c", topic: topic, authority: .vendor, revision: 9)
            ]
        )
        XCTAssertEqual(position.maxAuthority, .official)
        XCTAssertEqual(position.maxRevision, 9)
    }

    func testAPositionWithNoRevisionsAtAllReportsNil() throws {
        let topic = try TopicKey("request timeout")
        XCTAssertNil(Fix.position(["p1"], topic: topic).maxRevision)
    }

    func testAuthorityTiersOrder() {
        XCTAssertTrue(AuthorityTier.unverified < .community)
        XCTAssertTrue(AuthorityTier.community < .vendor)
        XCTAssertTrue(AuthorityTier.vendor < .official)
        XCTAssertEqual(AuthorityTier.allCases.count, 4)
    }
}

final class ResolutionLadderTests: XCTestCase {
    private func topic() throws -> TopicKey { try TopicKey("request timeout") }

    func testAuthorityDecidesFirst() throws {
        let key = try topic()
        let resolution = ResolutionLadder.standard.resolve([
            Fix.position(["p1"], topic: key, authority: .official, revision: 1),
            Fix.position(["p2", "p3"], topic: key, sources: ["d1", "d2"], authority: .community, revision: 9)
        ])
        XCTAssertEqual(resolution, .resolved(winner: ["p1"], by: .authority))
    }

    func testRecencyDecidesWhenAuthorityTies() throws {
        let key = try topic()
        let resolution = ResolutionLadder.standard.resolve([
            Fix.position(["p1"], topic: key, authority: .vendor, revision: 3),
            Fix.position(["p2"], topic: key, authority: .vendor, revision: 7)
        ])
        XCTAssertEqual(resolution, .resolved(winner: ["p2"], by: .recency))
    }

    /// Recency stands aside entirely rather than treating "no revision" as "oldest".
    func testRecencyStandsAsideWhenAnyPositionHasNoRevision() throws {
        let key = try topic()
        let resolution = ResolutionLadder.standard.resolve([
            Fix.position(["p1"], topic: key, authority: .vendor, revision: 7),
            Fix.position(["p2", "p3"], topic: key, sources: ["d1", "d2"], authority: .vendor)
        ])
        XCTAssertEqual(resolution, .resolved(winner: ["p2", "p3"], by: .corroboration))
    }

    func testEveryRuleDecliningIsRecordedInOrder() throws {
        let key = try topic()
        let resolution = ResolutionLadder.standard.resolve([
            Fix.position(["p1"], topic: key, authority: .community, revision: 4),
            Fix.position(["p2"], topic: key, authority: .community, revision: 4)
        ])
        XCTAssertEqual(resolution, .unresolved(tried: [.authority, .recency, .corroboration]))
    }

    func testASharedMaximumIsATieRatherThanAWin() throws {
        let key = try topic()
        XCTAssertNil(
            ResolutionRule.corroboration.winner(among: [
                Fix.position(["p1", "p2"], topic: key, sources: ["d1", "d2"]),
                Fix.position(["p3", "p4"], topic: key, sources: ["d3", "d4"])
            ])
        )
    }

    func testTheLadderOrderChangesTheWinner() throws {
        let key = try topic()
        let positions = [
            Fix.position(["p1"], topic: key, authority: .official),
            Fix.position(["p2", "p3"], topic: key, sources: ["d1", "d2"], authority: .community)
        ]
        XCTAssertEqual(
            try ResolutionLadder([.authority]).resolve(positions),
            .resolved(winner: ["p1"], by: .authority)
        )
        XCTAssertEqual(
            try ResolutionLadder([.corroboration]).resolve(positions),
            .resolved(winner: ["p2", "p3"], by: .corroboration)
        )
    }

    func testRefusesAnEmptyLadder() {
        XCTAssertThrowsError(try ResolutionLadder([])) { error in
            XCTAssertEqual(error as? SourceConflictError, .emptyLadder)
        }
    }

    func testRefusesARepeatedRule() {
        XCTAssertThrowsError(try ResolutionLadder([.authority, .recency, .authority])) { error in
            XCTAssertEqual(error as? SourceConflictError, .duplicateRule(.authority))
        }
    }

    func testStandardLadderOrder() {
        XCTAssertEqual(ResolutionLadder.standard.rules, [.authority, .recency, .corroboration])
        XCTAssertEqual(ResolutionRule.allCases.count, 3)
    }
}

final class PolicyAndReportTests: XCTestCase {
    func testPolicyPresets() {
        XCTAssertTrue(ConflictPolicy.strict.blocksOnUnresolved)
        XCTAssertTrue(ConflictPolicy.strict.withholdsLosers)
        XCTAssertFalse(ConflictPolicy.permissive.blocksOnUnresolved)
        XCTAssertFalse(ConflictPolicy.permissive.withholdsLosers)
        XCTAssertFalse(ConflictPolicy(blocksOnUnresolved: true, withholdsLosers: false).withholdsLosers)
    }

    func testDecisionKinds() {
        XCTAssertEqual(AuditDecision.clear.kind, "clear")
        XCTAssertEqual(AuditDecision.flagged(withheld: ["p1"]).kind, "flagged")
        XCTAssertEqual(AuditDecision.blocked(topics: ["t"]).kind, "blocked")
    }

    func testReportAndFindingAreValueTypes() throws {
        let key = try TopicKey("request timeout")
        let finding = ConflictFinding(
            topic: key,
            positions: [Fix.position(["p1"], topic: key)],
            reasons: ["because"],
            resolution: .unresolved(tried: [.authority])
        )
        let report = ConflictReport(
            findings: [finding],
            admitted: ["p1"],
            withheld: [],
            decision: .flagged(withheld: [])
        )
        XCTAssertEqual(report.findings, [finding])
        XCTAssertEqual(report.admitted, ["p1"])
        XCTAssertEqual(report.withheld, [])
        XCTAssertEqual(report.decision, .flagged(withheld: []))
    }

    func testEveryErrorDescribesItself() {
        let errors: [SourceConflictError] = [
            .noPassages,
            .emptyText(id: "p1"),
            .emptyTopic(raw: "the"),
            .duplicateID("p1"),
            .emptyLadder,
            .duplicateRule(.recency)
        ]
        for error in errors {
            XCTAssertFalse(error.description.isEmpty, "\(error)")
        }
        XCTAssertEqual(SourceConflictError.noPassages.description, "no passages to audit")
    }
}
