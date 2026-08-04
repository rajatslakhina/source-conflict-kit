import Foundation
import XCTest
@testable import SourceConflictKit

final class AuditorTests: XCTestCase {
    private func timeout() throws -> TopicKey { try TopicKey("request timeout") }

    func testAgreementAloneIsNotAConflict() async throws {
        let key = try timeout()
        let report = try await ConflictAuditor().audit([
            Fix.passage("p1", "the timeout is 30 seconds", topic: key),
            Fix.passage("p2", "requests stop after 30 seconds", topic: key)
        ], at: 0)
        XCTAssertEqual(report.decision, .clear)
        XCTAssertEqual(report.admitted, ["p1", "p2"])
        XCTAssertTrue(report.findings.isEmpty)
    }

    func testTopicsAreAuditedSeparately() async throws {
        let report = try await ConflictAuditor().audit([
            Fix.passage("p1", "the timeout is 30 seconds", topic: try TopicKey("request timeout")),
            Fix.passage("p2", "the budget is 5 seconds", topic: try TopicKey("retry budget"))
        ], at: 0)
        XCTAssertEqual(report.decision, .clear)
    }

    func testAuthorityResolvesAndTheLoserIsWithheld() async throws {
        let key = try timeout()
        let report = try await ConflictAuditor().audit([
            Fix.passage("p-spec", "the timeout is 30 seconds", topic: key, authority: .official),
            Fix.passage("p-blog", "the timeout is 60 seconds", topic: key, authority: .community)
        ], at: 0)
        XCTAssertEqual(report.decision, .flagged(withheld: ["p-blog"]))
        XCTAssertEqual(report.admitted, ["p-spec"])
        XCTAssertEqual(report.findings.count, 1)
        XCTAssertEqual(report.findings[0].resolution, .resolved(winner: ["p-spec"], by: .authority))
        XCTAssertEqual(report.findings[0].topic.normalized, "request-timeout")
        XCTAssertEqual(report.findings[0].reasons, ["p-blog vs p-spec — numeric: 30s vs 60s"])
    }

    /// The property the package exists for: three chunks of one document are one voice.
    func testChunksOfOneDocumentDoNotInflateCorroboration() async throws {
        let key = try timeout()
        let auditor = ConflictAuditor(ladder: try ResolutionLadder([.corroboration]))
        let report = try await auditor.audit([
            Fix.passage("p-a", "the timeout is 30 seconds", topic: key, source: "doc-a"),
            Fix.passage("p-b1", "the timeout is 60 seconds", topic: key, source: "doc-b"),
            Fix.passage("p-b2", "requests stop after 60 seconds", topic: key, source: "doc-b"),
            Fix.passage("p-b3", "a timeout of 60 seconds applies", topic: key, source: "doc-b")
        ], at: 0)
        let positions = report.findings[0].positions
        XCTAssertEqual(positions.count, 2)
        XCTAssertEqual(positions.map(\.corroboration), [1, 1])
        XCTAssertEqual(positions.map(\.passageIDs), [["p-a"], ["p-b1", "p-b2", "p-b3"]])
        // One source each, so the only rule in the ladder declines and nothing is picked.
        XCTAssertEqual(report.findings[0].resolution, .unresolved(tried: [.corroboration]))
        XCTAssertEqual(report.decision, .blocked(topics: ["request-timeout"]))
    }

    func testTwoIndependentDocumentsOutweighOne() async throws {
        let key = try timeout()
        let report = try await ConflictAuditor().audit([
            Fix.passage("p-a", "the timeout is 30 seconds", topic: key, source: "doc-a"),
            Fix.passage("p-b", "requests stop after 30 seconds", topic: key, source: "doc-b"),
            Fix.passage("p-c", "the timeout is 60 seconds", topic: key, source: "doc-c")
        ], at: 0)
        XCTAssertEqual(
            report.findings[0].resolution,
            .resolved(winner: ["p-a", "p-b"], by: .corroboration)
        )
        XCTAssertEqual(report.withheld, ["p-c"])
    }

    func testAnUnbreakableTieBlocks() async throws {
        let key = try TopicKey("prompt caching")
        let report = try await ConflictAuditor().audit([
            Fix.passage("p-x", "caching is enabled", topic: key, authority: .community),
            Fix.passage("p-y", "caching is disabled", topic: key, authority: .community)
        ], at: 0)
        XCTAssertEqual(report.decision, .blocked(topics: ["caching-prompt"]))
        XCTAssertEqual(report.admitted, ["p-x", "p-y"])
        XCTAssertEqual(report.withheld, [])
    }

    func testAPermissivePolicyAdmitsEverythingAndStillReports() async throws {
        let key = try TopicKey("prompt caching")
        let report = try await ConflictAuditor().audit([
            Fix.passage("p-x", "caching is enabled", topic: key, authority: .community),
            Fix.passage("p-y", "caching is disabled", topic: key, authority: .community)
        ], policy: .permissive, at: 0)
        XCTAssertEqual(report.decision, .flagged(withheld: []))
        XCTAssertEqual(report.admitted, ["p-x", "p-y"])
        XCTAssertEqual(report.findings.count, 1)
    }

    func testAPermissivePolicyKeepsTheLoserOfAResolvedConflict() async throws {
        let key = try timeout()
        let report = try await ConflictAuditor().audit([
            Fix.passage("p-spec", "the timeout is 30 seconds", topic: key, authority: .official),
            Fix.passage("p-blog", "the timeout is 60 seconds", topic: key, authority: .community)
        ], policy: .permissive, at: 0)
        XCTAssertEqual(report.admitted, ["p-blog", "p-spec"])
        XCTAssertEqual(report.decision, .flagged(withheld: []))
    }

    /// A chain of agreements is broken where a conflict crosses it, rather than producing a camp
    /// that contradicts itself and then votes as one voice.
    func testAgreementIsNotHonouredThroughAConflict() async throws {
        let key = try timeout()
        let auditor = ConflictAuditor(
            oracle: ScriptedOracle([
                "p-a|p-b": .agrees(reason: "scripted"),
                "p-b|p-c": .agrees(reason: "scripted"),
                "p-a|p-c": .conflicts(reason: "scripted")
            ])
        )
        let report = try await auditor.audit([
            Fix.passage("p-a", "one", topic: key, source: "d1"),
            Fix.passage("p-b", "two", topic: key, source: "d2"),
            Fix.passage("p-c", "three", topic: key, source: "d3")
        ], at: 0)
        let camps = report.findings[0].positions.map(\.passageIDs)
        XCTAssertEqual(camps.count, 2)
        XCTAssertFalse(
            camps.contains { $0.contains("p-a") && $0.contains("p-c") },
            "p-a and p-c conflict and must never share a position"
        )
    }

    func testAnAgreementEdgeInsideOneCampIsSkipped() async throws {
        let key = try timeout()
        let report = try await ConflictAuditor().audit([
            Fix.passage("p-1", "the timeout is 30 seconds", topic: key, source: "d1"),
            Fix.passage("p-2", "requests stop after 30 seconds", topic: key, source: "d1"),
            Fix.passage("p-3", "a timeout of 30 seconds applies", topic: key, source: "d1"),
            Fix.passage("p-4", "the timeout is 60 seconds", topic: key, source: "d2")
        ], at: 0)
        XCTAssertEqual(
            report.findings[0].positions.map(\.passageIDs),
            [["p-1", "p-2", "p-3"], ["p-4"]]
        )
    }

    func testAPassageOutsideTheConflictIsNotWithheld() async throws {
        let key = try timeout()
        let auditor = ConflictAuditor(
            oracle: ScriptedOracle(["p-a|p-b": .conflicts(reason: "scripted")])
        )
        let report = try await auditor.audit([
            Fix.passage("p-a", "one", topic: key, authority: .official),
            Fix.passage("p-b", "two", topic: key, authority: .community),
            Fix.passage("p-c", "three", topic: key)
        ], at: 0)
        XCTAssertEqual(report.findings[0].positions.count, 2)
        XCTAssertEqual(report.admitted, ["p-a", "p-c"])
        XCTAssertEqual(report.withheld, ["p-b"])
    }

    func testStatisticsAndTrailAccumulate() async throws {
        let key = try timeout()
        let caching = try TopicKey("prompt caching")
        let auditor = ConflictAuditor()
        _ = try await auditor.audit([
            Fix.passage("p1", "the timeout is 30 seconds", topic: key, authority: .official),
            Fix.passage("p2", "the timeout is 60 seconds", topic: key, authority: .community)
        ], at: 1)
        _ = try await auditor.audit([
            Fix.passage("q1", "caching is enabled", topic: caching),
            Fix.passage("q2", "caching is disabled", topic: caching)
        ], at: 2)

        let stats = await auditor.statistics()
        XCTAssertEqual(stats.audits, 2)
        XCTAssertEqual(stats.passagesSeen, 4)
        XCTAssertEqual(stats.conflictsFound, 2)
        XCTAssertEqual(stats.conflictsResolved, 1)
        XCTAssertEqual(stats.conflictsUnresolved, 1)
        XCTAssertEqual(stats.passagesWithheld, 1)

        let events = await auditor.events()
        XCTAssertEqual(events.first?.kind, .auditStarted(passages: 2, oracle: "lexical"))
        XCTAssertEqual(events.first?.sequence, 1)
        XCTAssertEqual(events.first?.tick, 1)
        XCTAssertTrue(events.contains { $0.kind == .decisionReached(kind: "blocked") })
        XCTAssertTrue(events.contains { $0.kind == .conflictFound(topic: "request-timeout", positions: 2) })
        XCTAssertTrue(
            events.contains { $0.kind == .conflictResolved(topic: "request-timeout", by: .authority) }
        )
        XCTAssertTrue(
            events.contains {
                $0.kind == .conflictUnresolved(
                    topic: "caching-prompt",
                    tried: [.authority, .recency, .corroboration]
                )
            }
        )
    }

    func testRefusesAnEmptyRetrievedSet() async {
        let auditor = ConflictAuditor()
        do {
            _ = try await auditor.audit([], at: 0)
            XCTFail("an empty retrieved set must be refused")
        } catch {
            XCTAssertEqual(error as? SourceConflictError, .noPassages)
        }
    }

    func testRefusesABlankPassage() async throws {
        let key = try timeout()
        let auditor = ConflictAuditor()
        do {
            _ = try await auditor.audit([Fix.passage("p1", "   \n ", topic: key)], at: 0)
            XCTFail("a blank passage must be refused")
        } catch {
            XCTAssertEqual(error as? SourceConflictError, .emptyText(id: "p1"))
        }
    }

    func testRefusesDuplicateIDsRatherThanSilentlyDroppingOne() async throws {
        let key = try timeout()
        let auditor = ConflictAuditor()
        do {
            _ = try await auditor.audit([
                Fix.passage("p1", "the timeout is 30 seconds", topic: key),
                Fix.passage("p1", "the timeout is 60 seconds", topic: key)
            ], at: 0)
            XCTFail("duplicate ids must be refused")
        } catch {
            XCTAssertEqual(error as? SourceConflictError, .duplicateID("p1"))
        }
    }

    func testEdgeIsUnorderedAndSortable() {
        XCTAssertEqual(ConflictGrouper.Edge("b", "a"), ConflictGrouper.Edge("a", "b"))
        XCTAssertTrue(ConflictGrouper.Edge("a", "b") < ConflictGrouper.Edge("a", "c"))
        XCTAssertTrue(ConflictGrouper.Edge("a", "z") < ConflictGrouper.Edge("b", "c"))
    }
}
