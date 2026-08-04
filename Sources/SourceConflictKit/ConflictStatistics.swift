import Foundation

/// Running totals across every audit an auditor has run.
///
/// `conflictsUnresolved` is the number worth watching. A pipeline where it stays at zero is not
/// necessarily healthy — it may mean the ladder is deciding every dispute on a rule that should not
/// have been trusted with it, and the count of *resolved* conflicts is what shows that.
public struct ConflictStatistics: Sendable, Equatable {
    public private(set) var audits = 0
    public private(set) var passagesSeen = 0
    public private(set) var conflictsFound = 0
    public private(set) var conflictsResolved = 0
    public private(set) var conflictsUnresolved = 0
    public private(set) var passagesWithheld = 0

    mutating func record(_ report: ConflictReport) {
        audits += 1
        passagesSeen += report.admitted.count + report.withheld.count
        conflictsFound += report.findings.count
        passagesWithheld += report.withheld.count
        for finding in report.findings {
            switch finding.resolution {
            case .resolved:
                conflictsResolved += 1
            case .unresolved:
                conflictsUnresolved += 1
            }
        }
    }
}
