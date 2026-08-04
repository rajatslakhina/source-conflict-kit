import Foundation

/// A number and the unit attached to it, if one was.
///
/// The unit is what makes a comparison legitimate. `30` against `512` is not a disagreement when
/// one is seconds and the other megabytes, and a checker that compared bare magnitudes would
/// manufacture a conflict out of two compatible sentences.
struct MeasuredValue: Equatable {
    let value: Double
    let unit: String?

    /// Rendered without a trailing `.0`, because `timeout is 30.0s vs 60.0s` reads like a
    /// floating-point artifact in a report a human is meant to trust. Symbols close up (`30s`,
    /// `50%`); words keep their space (`5 attempts`), which is the difference between a report
    /// that reads like prose and one that reads like a stack trace.
    var rendered: String {
        let magnitude = value == value.rounded() && abs(value) < 1e15
            ? String(Int(value))
            : String(value)
        guard let unit else { return magnitude }
        return unit.count <= 2 ? magnitude + unit : magnitude + " " + unit
    }
}

/// Everything the built-in oracle can learn from one passage, computed once per passage rather
/// than once per pair — the grouper judges every pair within a topic, so per-pair parsing would
/// re-tokenize the same text a quadratic number of times.
struct TextFacts {
    let contentTokens: Set<String>
    let isNegated: Bool
    let measurements: [MeasuredValue]
    let exclusiveHits: [Int: String]

    init(text: String, vocabulary: ConflictVocabulary) {
        let raw = TextFacts.tokenize(text)
        var content: Set<String> = []
        var negationCount = 0
        var found: [MeasuredValue] = []

        for (index, token) in raw.enumerated() {
            if vocabulary.negationCues.contains(token) {
                negationCount += 1
                continue
            }
            if let parsed = TextFacts.measurement(at: index, in: raw, vocabulary: vocabulary) {
                found.append(parsed)
                continue
            }
            if !vocabulary.stopWords.contains(token) {
                content.insert(token)
            }
        }

        contentTokens = content
        isNegated = negationCount % 2 == 1
        measurements = found
        exclusiveHits = TextFacts.exclusiveMembers(in: content, vocabulary: vocabulary)
    }

    /// Splits on anything that is not a letter, a digit, a decimal point or a percent sign, so
    /// `30s`, `1.5`, `99%` and `time-out` survive as the tokens a reader would expect.
    static func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "." && $0 != "%" })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
            .filter { !$0.isEmpty }
    }

    /// Reads a measurement starting at `index`, taking the unit from a suffix inside the token
    /// (`30s`) or from the token that follows it (`30 seconds`).
    static func measurement(
        at index: Int,
        in tokens: [String],
        vocabulary: ConflictVocabulary
    ) -> MeasuredValue? {
        let token = tokens[index]
        guard let split = TextFacts.splitNumeric(token) else { return nil }
        if let suffix = split.suffix {
            return MeasuredValue(value: split.value, unit: TextFacts.canonical(suffix, vocabulary))
        }
        let next = index + 1 < tokens.count ? tokens[index + 1] : nil
        guard let following = next, TextFacts.isUnitLike(following) else {
            return MeasuredValue(value: split.value, unit: nil)
        }
        return MeasuredValue(value: split.value, unit: TextFacts.canonical(following, vocabulary))
    }

    /// Separates `512mb` into `512` and `mb`. A token that is entirely digits yields no suffix.
    static func splitNumeric(_ token: String) -> (value: Double, suffix: String?)? {
        let digits = token.prefix { $0.isNumber || $0 == "." }
        guard !digits.isEmpty, let value = Double(digits) else { return nil }
        let suffix = String(token.dropFirst(digits.count))
        return (value, suffix.isEmpty ? nil : suffix)
    }

    /// A unit token is short and alphabetic, or the percent sign. The length cap is what stops
    /// `5 providers` from reading `providers` as a unit and inventing a dimension.
    static func isUnitLike(_ token: String) -> Bool {
        if token == "%" { return true }
        return token.count <= 12 && token.allSatisfy { $0.isLetter }
    }

    static func canonical(_ unit: String, _ vocabulary: ConflictVocabulary) -> String {
        vocabulary.unitAliases[unit] ?? unit
    }

    /// A set contributes a hit only when exactly one of its members appears. A passage saying
    /// "was enabled, now disabled" names both, and which one it asserts is beyond a word list.
    static func exclusiveMembers(
        in content: Set<String>,
        vocabulary: ConflictVocabulary
    ) -> [Int: String] {
        var hits: [Int: String] = [:]
        for (index, set) in vocabulary.exclusiveSets.enumerated() {
            let present = content.intersection(set)
            guard present.count == 1, let member = present.first else { continue }
            hits[index] = member
        }
        return hits
    }
}
