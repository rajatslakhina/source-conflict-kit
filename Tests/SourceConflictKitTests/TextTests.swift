import Foundation
import XCTest
@testable import SourceConflictKit

final class TopicKeyTests: XCTestCase {
    func testNormalizesCaseWordOrderAndStopWords() throws {
        let a = try TopicKey("Request Timeout")
        let b = try TopicKey("the timeout of a request")
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.normalized, "request-timeout")
        XCTAssertEqual(a.description, "request-timeout")
    }

    func testKeepsDigitsAndSplitsOnPunctuation() throws {
        XCTAssertEqual(try TopicKey("HTTP/2 push!").normalized, "2-http-push")
    }

    func testRefusesATopicThatNormalizesToNothing() {
        XCTAssertThrowsError(try TopicKey("the of and")) { error in
            XCTAssertEqual(error as? SourceConflictError, .emptyTopic(raw: "the of and"))
        }
    }

    func testDistinctSubjectsDoNotCollide() throws {
        XCTAssertNotEqual(try TopicKey("request timeout"), try TopicKey("retry budget"))
    }
}

final class TextFactsTests: XCTestCase {
    private let vocabulary = ConflictVocabulary.english

    func testReadsAUnitSuffixInsideTheToken() {
        let facts = TextFacts(text: "timeout is 30s", vocabulary: vocabulary)
        XCTAssertEqual(facts.measurements, [MeasuredValue(value: 30, unit: "s")])
    }

    func testReadsAUnitFromTheFollowingToken() {
        let facts = TextFacts(text: "timeout is 30 seconds", vocabulary: vocabulary)
        XCTAssertEqual(facts.measurements, [MeasuredValue(value: 30, unit: "s")])
    }

    func testTreatsALongFollowingWordAsProseRatherThanAUnit() {
        let facts = TextFacts(text: "supports 5 concurrentconnections", vocabulary: vocabulary)
        XCTAssertEqual(facts.measurements, [MeasuredValue(value: 5, unit: nil)])
    }

    func testANumberAtTheEndHasNoUnit() {
        let facts = TextFacts(text: "the budget is 5", vocabulary: vocabulary)
        XCTAssertEqual(facts.measurements, [MeasuredValue(value: 5, unit: nil)])
    }

    func testPercentIsAUnit() {
        let facts = TextFacts(text: "coverage is 99%", vocabulary: vocabulary)
        XCTAssertEqual(facts.measurements, [MeasuredValue(value: 99, unit: "%")])
    }

    /// `99%` arrives as one token; `99 %` arrives as two. Both have to reach the same measurement,
    /// or the same fact written two ways stops comparing against itself.
    func testADetachedPercentSignIsStillAUnit() {
        let facts = TextFacts(text: "coverage is 99 %", vocabulary: vocabulary)
        XCTAssertEqual(facts.measurements, [MeasuredValue(value: 99, unit: "%")])
        XCTAssertTrue(TextFacts.isUnitLike("%"))
    }

    func testAFollowingTokenWithDigitsIsNotAUnit() {
        let facts = TextFacts(text: "version 2 h2c", vocabulary: vocabulary)
        XCTAssertEqual(facts.measurements, [MeasuredValue(value: 2, unit: nil)])
    }

    func testUnparseableNumericTokenIsNotAMeasurement() {
        let facts = TextFacts(text: "build 1.2.3 shipped", vocabulary: vocabulary)
        XCTAssertEqual(facts.measurements, [])
        XCTAssertTrue(facts.contentTokens.contains("1.2.3"))
    }

    func testDoubleNegationIsAffirmative() {
        XCTAssertTrue(TextFacts(text: "is not cached", vocabulary: vocabulary).isNegated)
        XCTAssertFalse(TextFacts(text: "is not never cached", vocabulary: vocabulary).isNegated)
    }

    func testNegationCuesAreNotContentTokens() {
        let facts = TextFacts(text: "caching is not enabled", vocabulary: vocabulary)
        XCTAssertFalse(facts.contentTokens.contains("not"))
        XCTAssertTrue(facts.contentTokens.contains("caching"))
    }

    func testASetNamingBothMembersContributesNoHit() {
        let facts = TextFacts(text: "was enabled, now disabled", vocabulary: vocabulary)
        XCTAssertTrue(facts.exclusiveHits.isEmpty)
    }

    func testASetNamingOneMemberContributesAHit() {
        let facts = TextFacts(text: "caching is enabled", vocabulary: vocabulary)
        XCTAssertEqual(Array(facts.exclusiveHits.values), ["enabled"])
    }

    func testRenderingDropsTrailingZeroAndSpacesWordUnits() {
        XCTAssertEqual(MeasuredValue(value: 30, unit: "s").rendered, "30s")
        XCTAssertEqual(MeasuredValue(value: 5, unit: "attempts").rendered, "5 attempts")
        XCTAssertEqual(MeasuredValue(value: 7, unit: nil).rendered, "7")
        XCTAssertEqual(MeasuredValue(value: 1.5, unit: "s").rendered, "1.5s")
    }

    func testUnitAliasesCollapseToOneForm() {
        XCTAssertEqual(TextFacts.canonical("seconds", vocabulary), "s")
        XCTAssertEqual(TextFacts.canonical("furlongs", vocabulary), "furlongs")
    }
}

final class LexicalOracleTests: XCTestCase {
    private let oracle = LexicalContradictionOracle()

    private func pair(_ left: String, _ right: String) throws -> OracleVerdict {
        let topic = try TopicKey("request timeout")
        return oracle.judge(
            Fix.passage("a", left, topic: topic),
            Fix.passage("b", right, topic: topic)
        )
    }

    func testDifferentValuesInTheSameUnitConflict() throws {
        XCTAssertEqual(
            try pair("the timeout is 30 seconds", "the timeout is 60 seconds"),
            .conflicts(reason: "numeric: 30s vs 60s")
        )
    }

    func testTheSameValueAgrees() throws {
        XCTAssertEqual(
            try pair("the timeout is 30 seconds", "requests stop after 30 seconds"),
            .agrees(reason: "numeric: both state 30s")
        )
    }

    func testDifferentUnitsAreNotComparable() throws {
        XCTAssertEqual(try pair("the timeout is 30 seconds", "the buffer is 30 megabytes"), .unrelated)
    }

    func testAPassageWithTwoNumbersDeclinesRatherThanGuessing() throws {
        XCTAssertEqual(try pair("30 seconds after 5 seconds", "the timeout is 60 seconds"), .unrelated)
    }

    func testPolarityFlipOverSharedTermsConflicts() throws {
        let verdict = try pair(
            "prompt caching is applied to system instructions",
            "prompt caching is not applied to system instructions"
        )
        guard case .conflicts(let reason) = verdict else { return XCTFail("expected a conflict") }
        XCTAssertTrue(reason.hasPrefix("polarity:"), reason)
    }

    func testPolarityFlipWithoutSharedTermsIsNotAConflict() throws {
        XCTAssertEqual(try pair("caching applies", "quotas do not reset"), .unrelated)
    }

    func testMatchingPolarityIsNeverEvidenceOfAgreement() throws {
        XCTAssertEqual(try pair("prompt caching applies here", "prompt caching applies there"), .unrelated)
    }

    func testExclusiveMembersConflictAndMatchesAgree() throws {
        XCTAssertEqual(
            try pair("caching is enabled", "caching is disabled"),
            .conflicts(reason: "exclusive: disabled vs enabled")
        )
        // Reversing the arguments must not reverse the reason.
        XCTAssertEqual(
            try pair("caching is disabled", "caching is enabled"),
            .conflicts(reason: "exclusive: disabled vs enabled")
        )
        XCTAssertEqual(
            try pair("caching is enabled", "caching remains enabled"),
            .agrees(reason: "exclusive: both state enabled")
        )
    }

    /// The pair that decides whether the oracle is trustworthy: the number matches, so any scheme
    /// that averaged its signals would call this corroboration. The matching measurement must not
    /// appear in the reason either — the pair is a conflict, and listing the agreement alongside it
    /// invites a reader to net the two off.
    func testConflictOutranksAgreementWithinOnePair() throws {
        let verdict = try pair(
            "the timeout is 30 seconds under load",
            "the timeout is not 30 seconds under load"
        )
        guard case .conflicts(let reason) = verdict else { return XCTFail("expected a conflict") }
        XCTAssertTrue(reason.contains("polarity:"), reason)
        XCTAssertFalse(reason.contains("both state"), reason)
    }

    /// One side names an exclusive value and the other says nothing about it. Silence is not the
    /// opposite value.
    func testAnExclusiveSetOnlyOneSideNamesIsNotEvidence() throws {
        XCTAssertEqual(try pair("caching is enabled", "caching is fast"), .unrelated)
    }

    func testUnrelatedTextYieldsNoVerdict() throws {
        XCTAssertEqual(try pair("the sky is a colour", "documents exist"), .unrelated)
    }

    func testTheOracleIsSymmetric() throws {
        let topic = try TopicKey("request timeout")
        let left = Fix.passage("a", "the timeout is 30 seconds", topic: topic)
        let right = Fix.passage("b", "the timeout is 60 seconds", topic: topic)
        XCTAssertEqual(oracle.judge(left, right), oracle.judge(right, left))
        XCTAssertEqual(oracle.name, "lexical")
    }

    func testACustomVocabularyChangesWhatCounts() throws {
        let custom = ConflictVocabulary(
            negationCues: ["not"],
            exclusiveSets: [["staging", "production"]],
            stopWords: ["the", "is", "in"],
            unitAliases: [:]
        )
        let topic = try TopicKey("deployment target")
        let verdict = LexicalContradictionOracle(vocabulary: custom).judge(
            Fix.passage("a", "the rollout is in staging", topic: topic),
            Fix.passage("b", "the rollout is in production", topic: topic)
        )
        XCTAssertEqual(verdict, .conflicts(reason: "exclusive: production vs staging"))
        XCTAssertEqual(LexicalContradictionOracle(vocabulary: custom).name, "lexical")
    }
}
