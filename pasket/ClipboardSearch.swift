import Foundation

nonisolated struct ClipboardSearch {
    let query: String
    private let tokens: [Token]
    var isEmpty: Bool { query.isEmpty }

    init(_ query: String) {
        self.query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var seen: Set<String> = []
        tokens = self.query.split(whereSeparator: \.isWhitespace).compactMap { part in
            let text = String(part)
            return seen.insert(text).inserted ? Token(text) : nil
        }
    }

    // Zero excludes a record; higher ranks precede lower ranks before pagination.
    func rank(fields: [String]) -> Double {
        guard !isEmpty else { return 3 }
        if fields.contains(where: { $0.localizedStandardContains(query) }) { return 3 }
        var usesInitials = false
        var usesSubsequence = false
        var totalGap = 0
        var preparedFields: [SearchField]?
        for token in tokens {
            if fields.contains(where: { $0.localizedStandardContains(token.text) }) { continue }
            let prepared = preparedFields ?? fields.map(SearchField.init)
            preparedFields = prepared
            if prepared.contains(where: { token.minimumGap(in: $0.initials) != nil }) {
                usesInitials = true
                continue
            }
            guard let gap = prepared.compactMap({ token.minimumGap(in: $0.text) }).min() else { return 0 }
            usesSubsequence = true
            totalGap += gap
        }
        // Keep every ordinary subsequence below initials, without capping its distance.
        // Smaller total gaps yield higher scores; equal scores retain recency order.
        if usesSubsequence { return 1 / (Double(totalGap) + 2) }
        return usesInitials ? 1 : 2
    }

    func rank(_ item: ClipboardItem) -> Double {
        rank(fields: [item.title, item.content, item.source.name, item.source.bundleIdentifier ?? ""])
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .precomposedStringWithCanonicalMapping
    }

    private struct SearchField {
        let text: String
        let initials: String

        init(_ text: String) {
            self.text = ClipboardSearch.fold(text)
            let characters = Array(text)
            var initials = ""
            for index in characters.indices {
                let character = characters[index]
                guard character.isLetter || character.isNumber else { continue }
                let previous = index > 0 ? characters[index - 1] : nil
                let next = index + 1 < characters.count ? characters[index + 1] : nil
                let afterSeparator = previous.map { !$0.isLetter && !$0.isNumber } ?? true
                // Recognize separators, camelCase, and acronym boundaries such as XMLParser.
                let caseBoundary = character.isUppercase && (previous?.isLowercase == true
                    || previous?.isNumber == true
                    || (previous?.isUppercase == true && next?.isLowercase == true))
                if afterSeparator || caseBoundary { initials.append(character) }
            }
            self.initials = ClipboardSearch.fold(initials)
        }
    }

    private struct Token {
        let text: String
        let length: Int
        let positions: [Character: [Int]]

        init(_ text: String) {
            self.text = text
            let characters = Array(ClipboardSearch.fold(text))
            length = characters.count
            var positions: [Character: [Int]] = [:]
            for index in characters.indices.reversed() {
                positions[characters[index], default: []].append(index)
            }
            self.positions = positions
        }

        func minimumGap(in text: String) -> Int? {
            guard length > 0 else { return nil }
            var latestStarts = [Int?](repeating: nil, count: length)
            var bestGap: Int?
            for (offset, character) in text.enumerated() {
                // Descending positions prevent one character from matching twice.
                // The latest start of each reachable prefix gives the tightest window at this end.
                for index in positions[character] ?? [] {
                    guard let start = index == 0 ? offset : latestStarts[index - 1] else { continue }
                    latestStarts[index] = start
                    guard index == length - 1 else { continue }
                    // Count skipped grapheme clusters after folding, not bytes or code units.
                    let gap = offset - start + 1 - length
                    if gap == 0 { return 0 }
                    bestGap = min(bestGap ?? gap, gap)
                }
            }
            return bestGap
        }
    }
}
