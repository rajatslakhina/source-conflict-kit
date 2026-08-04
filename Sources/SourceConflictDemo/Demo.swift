import Foundation
import SourceConflictKit

@main
struct Demo {
    static func main() async throws {
        print("SourceConflictKit — auditing retrieved passages against each other")
        print(String(repeating: "=", count: 78))
        print("")

        let auditor = ConflictAuditor()
        for (index, scenario) in try Scenarios.all().enumerated() {
            let report = try await auditor.audit(
                scenario.passages,
                policy: scenario.policy,
                at: index + 1
            )
            render(scenario, number: index + 1, report: report)
        }

        try await renderLadderComparison()
        try await renderRefusals()
        await renderStatistics(auditor)
    }

    static func render(_ scenario: Scenario, number: Int, report: ConflictReport) {
        print("[\(number)] \(scenario.title)")
        print("     \(scenario.note)")
        for finding in report.findings {
            print("     topic: \(finding.topic)")
            for reason in finding.reasons {
                print("       conflict: \(reason)")
            }
            for position in finding.positions {
                print("       position \(describe(position))")
            }
            print("       resolution: \(describe(finding.resolution))")
        }
        print("     decision: \(describe(report.decision))")
        print("     admitted: \(list(report.admitted))   withheld: \(list(report.withheld))")
        print("")
    }

    static func describe(_ position: Position) -> String {
        let revision = position.maxRevision.map(String.init) ?? "—"
        let ids = list(position.passageIDs)
        return "\(ids) sources=\(position.corroboration) "
            + "authority=\(position.maxAuthority) revision=\(revision)"
    }

    static func describe(_ resolution: Resolution) -> String {
        switch resolution {
        case .resolved(let winner, let rule):
            return "RESOLVED by \(rule.rawValue) → \(list(winner))"
        case .unresolved(let tried):
            let names = tried.map(\.rawValue).joined(separator: ", ")
            return "UNRESOLVED — every rule declined (\(names))"
        }
    }

    static func describe(_ decision: AuditDecision) -> String {
        switch decision {
        case .clear:
            return "CLEAR"
        case .flagged(let withheld):
            return "FLAGGED (\(withheld.count) withheld)"
        case .blocked(let topics):
            return "BLOCKED — do not generate on \(list(topics))"
        }
    }

    static func list(_ values: [String]) -> String {
        values.isEmpty ? "[]" : "[" + values.joined(separator: ", ") + "]"
    }

    /// The same passages, two ladders. The winner changes, which is the argument for the ladder
    /// being an explicit ordered list rather than a score somebody tuned once.
    static func renderLadderComparison() async throws {
        let topic = try TopicKey("Request timeout")
        let passages = [
            Scenarios.passage("p-spec", "The request timeout is 30 seconds.", topic, "spec", .official),
            Scenarios.passage("p-a", "The request timeout is 60 seconds.", topic, "doc-a", .community),
            Scenarios.passage("p-b", "The request timeout is 60 seconds.", topic, "doc-b", .community)
        ]

        print("[11] One dispute, two ladders")
        print("     The order of the rules is the policy, and it changes the answer.")
        for rules in [[ResolutionRule.authority], [ResolutionRule.corroboration]] {
            let auditor = ConflictAuditor(ladder: try ResolutionLadder(rules))
            let report = try await auditor.audit(passages, at: 11)
            let resolution = report.findings.map { describe($0.resolution) }.joined()
            print("       ladder \(list(rules.map(\.rawValue))): \(resolution)")
        }
        print("")
    }

    /// Every refusal path, exercised rather than described.
    static func renderRefusals() async throws {
        print("[12] What the auditor refuses")
        let topic = try TopicKey("Request timeout")
        let auditor = ConflictAuditor()
        let duplicate = [
            Scenarios.passage("p-1", "The request timeout is 30 seconds.", topic, "spec", .official),
            Scenarios.passage("p-1", "The request timeout is 60 seconds.", topic, "forum", .community)
        ]

        await report("empty retrieved set") { _ = try await auditor.audit([], at: 12) }
        await report("a passage with no text") {
            let blank = Scenarios.passage("p-blank", "   ", topic, "spec", .official)
            _ = try await auditor.audit([blank], at: 12)
        }
        await report("two passages sharing an id") { _ = try await auditor.audit(duplicate, at: 12) }
        await report("a topic that normalizes to nothing") { _ = try TopicKey("the of and") }
        await report("an empty ladder") { _ = try ResolutionLadder([]) }
        await report("a repeated ladder rule") {
            _ = try ResolutionLadder([.authority, .authority])
        }
        print("")
    }

    static func report(_ label: String, _ body: () async throws -> Void) async {
        do {
            try await body()
            print("       \(label): accepted — which it should not have been")
        } catch let error as SourceConflictError {
            print("       \(label): \(error)")
        } catch {
            print("       \(label): \(error)")
        }
    }

    static func renderStatistics(_ auditor: ConflictAuditor) async {
        let stats = await auditor.statistics()
        let events = await auditor.events()
        print("Statistics across the ten scenarios above")
        print("     audits: \(stats.audits)   passages seen: \(stats.passagesSeen)")
        print("     conflicts found: \(stats.conflictsFound)"
            + "   resolved: \(stats.conflictsResolved)"
            + "   unresolved: \(stats.conflictsUnresolved)")
        print("     passages withheld: \(stats.passagesWithheld)   trail entries: \(events.count)")
    }
}
