import Foundation
import SourceConflictKit

/// One retrieved set, the policy it is audited under, and what it is meant to show.
struct Scenario {
    let title: String
    let note: String
    let passages: [Passage]
    let policy: ConflictPolicy
}

enum Scenarios {
    // swiftlint:disable:next function_body_length
    static func all() throws -> [Scenario] {
        let timeout = try TopicKey("Request timeout")
        let retries = try TopicKey("the retry budget")
        let caching = try TopicKey("Prompt caching")
        let region = try TopicKey("Data residency region")

        return [
            Scenario(
                title: "Two chunks that agree",
                note: "Agreement is recorded, but agreement alone is not a conflict.",
                passages: [
                    passage("p-spec", "The request timeout is 30 seconds.", timeout, "spec", .official),
                    passage("p-guide", "Requests time out after 30 seconds.", timeout, "guide", .vendor)
                ],
                policy: .strict
            ),
            Scenario(
                title: "Official spec against a forum post",
                note: "Authority decides before anyone counts votes.",
                passages: [
                    passage("p-spec", "The request timeout is 30 seconds.", timeout, "spec", .official),
                    passage("p-forum", "The request timeout is 60 seconds.", timeout, "forum", .community)
                ],
                policy: .strict
            ),
            Scenario(
                title: "One document chunked three times",
                note: "Corroboration counts documents, not rows: 1 source against 1, not 3 against 1.",
                passages: [
                    passage("p-spec", "The request timeout is 30 seconds.", timeout, "spec", .official),
                    passage("p-blog-1", "The request timeout is 60 seconds.", timeout, "blog", .community),
                    passage("p-blog-2", "A request timeout of 60 seconds applies.", timeout, "blog", .community),
                    passage("p-blog-3", "Requests time out at 60 seconds.", timeout, "blog", .community)
                ],
                policy: .strict
            ),
            Scenario(
                title: "Two independent documents outweigh one",
                note: "Equal authority, no revisions anywhere — corroboration is the only rule left.",
                passages: [
                    passage("p-a", "The retry budget is 5 attempts.", retries, "doc-a", .community),
                    passage("p-b", "The retry budget is 5 attempts.", retries, "doc-b", .community),
                    passage("p-c", "The retry budget is 3 attempts.", retries, "doc-c", .community)
                ],
                policy: .strict
            ),
            Scenario(
                title: "Same tier, different revision",
                note: "Recency runs only because every position carries a revision.",
                passages: [
                    passage("p-old", "The retry budget is 3 attempts.", retries, "rel-1", .vendor, 3),
                    passage("p-new", "The retry budget is 8 attempts.", retries, "rel-2", .vendor, 7)
                ],
                policy: .strict
            ),
            Scenario(
                title: "Nothing can break the tie",
                note: "Every rule declines. The audit blocks rather than picking.",
                passages: [
                    passage("p-x", "Prompt caching is enabled.", caching, "wiki-x", .community),
                    passage("p-y", "Prompt caching is disabled.", caching, "wiki-y", .community)
                ],
                policy: .strict
            ),
            Scenario(
                title: "The same tie, under a permissive policy",
                note: "Someone downstream decides — but the conflict is still named.",
                passages: [
                    passage("p-x", "Prompt caching is enabled.", caching, "wiki-x", .community),
                    passage("p-y", "Prompt caching is disabled.", caching, "wiki-y", .community)
                ],
                policy: .permissive
            ),
            Scenario(
                title: "A negation a similarity score would miss",
                note: "Every content word matches. The one token that reverses the sentence does not.",
                passages: [
                    passage("p-on", "Prompt caching is applied to system instructions.",
                            caching, "note-1", .vendor, 2),
                    passage("p-off", "Prompt caching is not applied to system instructions.",
                            caching, "note-2", .vendor, 5)
                ],
                policy: .strict
            ),
            Scenario(
                title: "Newer beats more",
                note: "Two documents agree and still lose: the ladder puts recency above corroboration.",
                passages: [
                    passage("p-eu", "Data residency region is 50 percent complete.", region, "eu", .vendor, 4),
                    passage("p-mid", "Residency rollout covers 50 percent of regions.", region, "mid", .vendor, 4),
                    passage("p-us", "Data residency region is 90 percent complete.", region, "us", .vendor, 9)
                ],
                policy: .strict
            ),
            Scenario(
                title: "Different topics, both carrying numbers",
                note: "Topic scoping is what stops 30 against 5 from being reported as a dispute.",
                passages: [
                    passage("p-t", "The request timeout is 30 seconds.", timeout, "spec", .official),
                    passage("p-r", "The retry budget is 5 attempts.", retries, "spec", .official)
                ],
                policy: .strict
            )
        ]
    }

    static func passage(
        _ id: String,
        _ text: String,
        _ topic: TopicKey,
        _ source: String,
        _ authority: AuthorityTier,
        _ revision: Int? = nil
    ) -> Passage {
        Passage(
            id: id,
            text: text,
            topic: topic,
            provenance: Provenance(sourceID: source, authority: authority, revision: revision)
        )
    }
}
