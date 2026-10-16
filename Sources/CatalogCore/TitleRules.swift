import Foundation

/// A word or construct that the title rules did not change and that needs a person's review.
public struct TitleReview: Equatable, Sendable, CustomStringConvertible {
    public var word: String
    public var reason: String

    public var description: String { "\"\(word)\": \(reason)" }
}

public struct TitleRuleResult: Equatable, Sendable {
    public var title: String
    public var reviews: [TitleReview]
}

/// Applies the title rules of a catalog: removal of qualifiers, square brackets for nested parentheticals,
/// and a capitalization style. Explicit titles in a catalog take precedence; these rules normalize source
/// names and support matching.
public struct TitleRules: Sendable {
    public var caseStyle: TitleCase
    public var removeQualifiers: [String]
    public var bracketNested: Bool
    public var preserve: Set<String>

    public init(_ settings: TitleRuleSettings?) {
        caseStyle = settings?.caseStyle ?? .keep
        removeQualifiers = settings?.removeQualifiers ?? []
        bracketNested = settings?.bracketNested ?? false
        preserve = Set(settings?.preserve ?? [])
    }

    public func apply(_ title: String) -> TitleRuleResult {
        var reviews: [TitleReview] = []
        var text = TitleRules.removingQualifiers(title, terms: removeQualifiers)
        if bracketNested {
            let converted = TitleRules.bracketingNested(text)
            text = converted.text
            if !converted.balanced { reviews.append(TitleReview(word: title, reason: "unbalanced parentheses")) }
        }
        let cased = TitleRules.capitalized(text, style: caseStyle, preserve: preserve)
        return TitleRuleResult(title: cased.title, reviews: reviews + cased.reviews)
    }

    /// A key for comparing titles: qualifiers removed, brackets and apostrophes unified, and case,
    /// diacritics, width, and spacing ignored.
    public func matchingKey(_ title: String) -> String {
        let removed = TitleRules.removingQualifiers(title, terms: removeQualifiers)
        let unified = removed.replacingOccurrences(of: "[", with: "(").replacingOccurrences(of: "]", with: ")")
            .replacingOccurrences(of: "\u{2019}", with: "'").replacingOccurrences(of: "\u{2018}", with: "'")
        return TitleRules.comparisonKey(unified)
    }

    static func comparisonKey(_ text: String) -> String {
        text.precomposedStringWithCompatibilityMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    // MARK: - Qualifiers

    /// Removes trailing parenthesized or bracketed qualifiers that contain a listed term as whole words,
    /// with or without a year: `(2012 Remaster)`, `[Remastered]`.
    static func removingQualifiers(_ title: String, terms: [String]) -> String {
        guard !terms.isEmpty else { return title }
        var text = title
        while true {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard let last = trimmed.last, last == ")" || last == "]",
                let open = matchingOpening(in: trimmed)
            else { return trimmed }
            let inner = String(trimmed[trimmed.index(after: open)..<trimmed.index(before: trimmed.endIndex)])
            guard terms.contains(where: { containsWords(inner, $0) }) else { return trimmed }
            text = String(trimmed[..<open])
        }
    }

    /// The index of the bracket that opens the group closed by the last character.
    static func matchingOpening(in text: String) -> String.Index? {
        var depth = 0
        var index = text.endIndex
        while index > text.startIndex {
            index = text.index(before: index)
            switch text[index] {
            case ")", "]": depth += 1
            case "(", "[":
                depth -= 1
                if depth == 0 { return index }
            default: break
            }
        }
        return nil
    }

    static func containsWords(_ text: String, _ phrase: String) -> Bool {
        let words = text.lowercased().split { !$0.isLetter && !$0.isNumber }
        let target = phrase.lowercased().split { !$0.isLetter && !$0.isNumber }
        guard !target.isEmpty, words.count >= target.count else { return false }
        return (0...(words.count - target.count)).contains { Array(words[$0..<($0 + target.count)]) == target }
    }

    // MARK: - Nested Parentheticals

    /// Converts each top-level parenthetical that contains another parenthetical to square brackets:
    /// `Behind the Mask (Mike's Mix (Demo))` becomes `Behind the Mask [Mike's Mix (Demo)]`.
    static func bracketingNested(_ title: String) -> (text: String, balanced: Bool) {
        var characters = Array(title)
        var stack: [(index: Int, nested: Bool)] = []
        for index in characters.indices {
            switch characters[index] {
            case "(":
                if !stack.isEmpty { stack[stack.count - 1].nested = true }
                stack.append((index, false))
            case ")":
                guard let open = stack.popLast() else { return (title, false) }
                if stack.isEmpty && open.nested {
                    characters[open.index] = "["
                    characters[index] = "]"
                }
            default: break
            }
        }
        return stack.isEmpty ? (String(characters), true) : (title, false)
    }

    // MARK: - Capitalization

    static let articles: Set<String> = ["a", "an", "the"]
    static let coordinatingConjunctions: Set<String> = [
        "and", "but", "for", "nor", "or", "so", "yet", "'n'", "n'", "'n",
    ]
    static let prepositions: Set<String> = [
        "about", "above", "across", "after", "against", "along", "amid", "among", "around", "as", "at", "before",
        "behind", "below", "beneath", "beside", "besides", "between", "beyond", "but", "by", "despite", "down",
        "during", "except", "for", "from", "in", "inside", "into", "like", "near", "of", "off", "on", "onto",
        "out", "outside", "over", "past", "per", "round", "since", "than", "through", "throughout", "till", "'til",
        "to", "toward", "towards", "under", "underneath", "unlike", "until", "up", "upon", "versus", "via", "with",
        "within", "without",
    ]
    /// Words that are prepositions or conjunctions in some uses and adverbs, particles, or subordinating
    /// conjunctions in others. MLA treats the roles differently, so these are left unchanged and reported.
    static let mlaRoleDependent: Set<String> = [
        "about", "above", "across", "after", "along", "around", "as", "before", "behind", "below", "beneath",
        "beyond", "by", "down", "in", "inside", "like", "near", "off", "on", "out", "outside", "over", "past",
        "round", "since", "so", "through", "till", "'til", "under", "underneath", "until", "up", "yet",
    ]
    /// APA lowercases articles, prepositions, and conjunctions of three letters or fewer.
    static let apaMinorWords: Set<String> = [
        "a", "an", "the", "and", "as", "at", "but", "by", "for", "if", "in", "nor", "of", "off", "on", "or", "per",
        "so", "to", "up", "via", "yet", "'n'", "n'", "'n",
    ]
    static let apaRoleDependent: Set<String> = ["as", "by", "in", "off", "on", "so", "up", "yet"]

    struct Token {
        var leading: Substring
        var core: Substring
        var trailing: Substring
        var separator: Substring
    }

    static func tokens(_ text: String) -> [Token] {
        var result: [Token] = []
        var index = text.startIndex
        while index < text.endIndex {
            let wordEnd = text[index...].firstIndex(where: \.isWhitespace) ?? text.endIndex
            let separatorEnd = text[wordEnd...].firstIndex(where: { !$0.isWhitespace }) ?? text.endIndex
            let word = text[index..<wordEnd]
            let opening: Set<Character> = ["(", "[", "\"", "\u{201C}", "{"]
            let closing: Set<Character> = [")", "]", "\"", "\u{201D}", "}", ",", ":", ";", ".", "!", "?"]
            var start = word.startIndex
            while start < word.endIndex, opening.contains(word[start]) { start = word.index(after: start) }
            var end = word.endIndex
            while end > start, closing.contains(word[word.index(before: end)]) {
                // Keep periods of abbreviations such as "P.Y.T." in the core.
                if word[word.index(before: end)] == ".", word[start..<word.index(before: end)].contains(".") { break }
                end = word.index(before: end)
            }
            result.append(
                Token(
                    leading: word[..<start], core: word[start..<end], trailing: word[end...],
                    separator: text[wordEnd..<separatorEnd]))
            index = separatorEnd
        }
        return result
    }

    static func isLatinLetter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x41...0x5A, 0x61...0x7A, 0xC0...0x24F, 0x1E00...0x1EFF, 0x2C60...0x2C7F, 0xA720...0xA7FF, 0xAB30...0xAB6F:
            return true
        default:
            return false
        }
    }

    /// Words that are never changed: listed words, words entirely in capitals, words with internal capitals,
    /// abbreviations, words without letters, and words containing letters outside the Latin script.
    static func isProtected(_ core: Substring, preserve: Set<String>) -> Bool {
        if preserve.contains(String(core)) { return true }
        let letters = core.unicodeScalars.filter { $0.properties.isAlphabetic }
        if letters.isEmpty || letters.contains(where: { !isLatinLetter($0) }) { return true }
        if letters.count >= 2 && letters.allSatisfy({ $0.properties.isUppercase }) { return true }
        if letters.dropFirst().contains(where: { $0.properties.isUppercase }) { return true }
        if core.dropLast().contains(".") { return true }
        return false
    }

    static func setFirstLetter(_ core: Substring, uppercase: Bool) -> String {
        guard let index = core.firstIndex(where: \.isLetter) else { return String(core) }
        let letter = String(core[index])
        return String(core[..<index]) + (uppercase ? letter.uppercased() : letter.lowercased())
            + String(core[core.index(after: index)...])
    }

    static func capitalized(_ text: String, style: TitleCase, preserve: Set<String>) -> TitleRuleResult {
        guard style != .keep else { return TitleRuleResult(title: text, reviews: []) }
        let tokens = tokens(text)
        var reviews: [TitleReview] = []
        var output = ""
        for (position, token) in tokens.enumerated() {
            // A segment begins at the start, after a colon or a dash, and at an opening bracket; it ends before them.
            let previous = position > 0 ? tokens[position - 1] : nil
            let next = position + 1 < tokens.count ? tokens[position + 1] : nil
            let dashes: Set<Substring> = ["-", "\u{2013}", "\u{2014}"]
            let isFirst =
                previous == nil || previous!.trailing.contains(":") || dashes.contains(previous!.core)
                || token.leading.contains("(") || token.leading.contains("[")
            let isLast =
                next == nil || token.trailing.contains(":") || token.trailing.contains(")")
                || token.trailing.contains("]")
                || dashes.contains(next!.core) || next!.leading.contains("(") || next!.leading.contains("[")
            let parts = token.core.split(separator: "-", omittingEmptySubsequences: false)
            var cased: [String] = []
            for (partIndex, part) in parts.enumerated() {
                let first = isFirst && partIndex == 0
                let last = isLast && partIndex == parts.count - 1
                cased.append(
                    casePart(part, style: style, first: first, last: last, preserve: preserve, reviews: &reviews))
            }
            output += token.leading + cased.joined(separator: "-") + token.trailing + token.separator
        }
        return TitleRuleResult(title: output, reviews: reviews)
    }

    static func casePart(
        _ part: Substring, style: TitleCase, first: Bool, last: Bool, preserve: Set<String>,
        reviews: inout [TitleReview]
    ) -> String {
        guard !isProtected(part, preserve: preserve) else { return String(part) }
        let word = part.lowercased()
        switch style {
        case .keep:
            return String(part)
        case .start:
            return setFirstLetter(part, uppercase: true)
        case .mla:
            if first || last { return setFirstLetter(part, uppercase: true) }
            if mlaRoleDependent.contains(word) {
                reviews.append(
                    TitleReview(word: String(part), reason: "MLA capitalization depends on its grammatical role"))
                return String(part)
            }
            let minor =
                articles.contains(word) || coordinatingConjunctions.contains(word) || prepositions.contains(word)
            return setFirstLetter(part, uppercase: !minor)
        case .apa:
            if first { return setFirstLetter(part, uppercase: true) }
            if apaRoleDependent.contains(word) {
                reviews.append(
                    TitleReview(word: String(part), reason: "APA capitalization depends on its grammatical role"))
                return String(part)
            }
            let letterCount = part.filter(\.isLetter).count
            return setFirstLetter(part, uppercase: letterCount >= 4 || !apaMinorWords.contains(word))
        }
    }
}

/// Reports deviations from the live-recording convention: live recordings carry `(Live)`, or `[Live]` when
/// the title already ends with a parenthetical, and interludes carry no live designation. Version 0.1.0
/// reports deviations and does not apply the convention.
public enum LiveDesignation {
    public static func review(_ title: String) -> [String] {
        var findings: [String] = []
        let lowered = title.lowercased()
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        if lowered.contains("interlude"),
            lowered.contains("live") && (lowered.contains("(live") || lowered.contains("[live"))
        {
            findings.append("an interlude carries a live designation")
        }
        if let range = trimmed.range(of: #"\s[-–—]\s*live\b.*$"#, options: [.regularExpression, .caseInsensitive]) {
            findings.append(
                "\"\(trimmed[range].trimmingCharacters(in: .whitespaces))\" should be a parenthetical (Live)")
        }
        for pattern in [
            #"\((live [^)]+|live version|live recording)\)"#, #"\[(live [^\]]+|live version|live recording)\]"#,
        ] {
            if let range = trimmed.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                findings.append("\"\(trimmed[range])\" is not the plain designation (Live)")
            }
        }
        if trimmed.hasSuffix("(Live)") {
            let before = trimmed.dropLast("(Live)".count).trimmingCharacters(in: .whitespaces)
            if before.hasSuffix(")") || before.hasSuffix("]") {
                findings.append("(Live) follows a parenthetical and should be [Live]")
            }
        } else if trimmed.hasSuffix("[Live]") {
            let before = trimmed.dropLast("[Live]".count).trimmingCharacters(in: .whitespaces)
            if !(before.hasSuffix(")") || before.hasSuffix("]")) {
                findings.append("[Live] does not follow a parenthetical and should be (Live)")
            }
        } else if lowered.hasSuffix("(live)") || lowered.hasSuffix("[live]") {
            findings.append("the live designation should be capitalized")
        }
        return findings
    }
}
