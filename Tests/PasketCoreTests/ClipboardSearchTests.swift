import Foundation
import Testing
@testable import PasketCore

struct ClipboardSearchTests {
    @Test(arguments: [
        ("hello world", "prefix HELLO WORLD suffix", true),
        ("hello world", "world before hello", true),
        (" hello\t\nworld ", "world before hello", true),
        ("hello missing", "hello world", false),
        ("hlo world", "hello world", true),
        ("hlo", "hello", true),
        ("abc", "axxxbxxxc", true),
        ("abc", "axxxxbxc", true),
        ("abc", "axbxxxxc", true),
        ("abc", "abxxbxxc", true),
        ("abc", "axxxxabxc", true),
        ("aab", "ab", false),
        ("abc", "cba", false),
        ("cafe", "CAFÉ", true),
        ("cfe", "CAFE\u{301}", true),
        ("中搜", "中文搜索", true),
        ("中索", "中甲乙丙丁索", true),
        ("a👩‍💻b", "A👨‍👩‍👧‍👦👩‍💻xB", true),
        ("ab", "a👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦b", true),
        ("ab", "a👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦👨‍👩‍👧‍👦b", true),
        ("%_", "literal %_ suffix", true),
        ("%_", "ordinary text", false),
        ("a*b", "ab", false),
        ("a\0b", "prefix a\0b", true),
        ("ab", "a\0b", true),
        ("hello hello", "hello", true),
        ("\t\n ", "anything", true)
    ])
    func matchesKeywordsAndUnboundedSubsequences(query: String, text: String, expected: Bool) {
        #expect((ClipboardSearch(query).rank(fields: [text]) > 0) == expected)
    }

    @Test(arguments: ["**LOKI_PHRASE**", "LOKI-PHRASE", "Loki Phrase", "lokiPhrase", "LokiPhrase", "loki_extra_phrase"])
    func recognizesWordInitialsAcrossSeparatorsAndCaseBoundaries(text: String) {
        #expect(ClipboardSearch("lp").rank(fields: [text]) == 1)
    }

    @Test func ranksLiteralThenInitialsThenSubsequencesByTheirSmallestTotalGap() {
        let search = ClipboardSearch("lp")
        let literal = search.rank(fields: ["help"])
        let initials = search.rank(fields: ["**LOKI_PHRASE**"])
        let tight = search.rank(fields: ["lxp"])
        let wide = search.rank(fields: ["lxxxxp"])
        #expect(literal > initials)
        #expect(initials > tight)
        #expect(tight > wide)
        #expect(wide > search.rank(fields: ["l" + String(repeating: "x", count: 2_000) + "p"]))
        #expect(search.rank(fields: ["l" + String(repeating: "x", count: 2_000) + "p"]) > 0)
        #expect(search.rank(fields: ["lxxxxpxlxp"]) == tight)
        #expect(search.rank(fields: ["lxxxxp", "lxp"]) == tight)
        #expect(search.rank(fields: ["lxp", "LOKI_PHRASE"]) == initials)
        #expect(search.rank(fields: ["loki"]) == 0)
        #expect(ClipboardSearch("xp").rank(fields: ["XMLParser"]) == 1)
    }

    @Test func comparesTotalGapsAcrossKeywordsAndCountsUnicodeCharacters() {
        let search = ClipboardSearch("lp rz")
        #expect(search.rank(fields: ["lxp rxxz"]) > search.rank(fields: ["lxxxp rxxz"]))
        #expect(search.rank(fields: ["LOKI_PHRASE rxxz"]) < search.rank(fields: ["LOKI_PHRASE RIVER_ZONE"]))
        let emojiSearch = ClipboardSearch("a👩‍💻b")
        #expect(emojiSearch.rank(fields: ["a👨‍👩‍👧‍👦👩‍💻xb"]) == emojiSearch.rank(fields: ["ax👩‍💻xb"]))
        #expect(ClipboardSearch("abc").rank(fields: ["axbxxxxcxxaxbc"]) == ClipboardSearch("abc").rank(fields: ["axbc"]))
        #expect(ClipboardSearch("aab").rank(fields: ["axaxxb"]) > 0)
    }

    @Test func keywordsCanMatchDifferentFieldsButSubsequencesCannotCrossFields() {
        #expect(ClipboardSearch("report safari").rank(fields: ["Quarterly report", "Safari"]) == 2)
        #expect(ClipboardSearch("rpt safari").rank(fields: ["report", "Safari"]) > 0)
        #expect(ClipboardSearch("abc").rank(fields: ["ab", "c"]) == 0)
        #expect(ClipboardSearch("report missing").rank(fields: ["report", "Safari"]) == 0)
    }

    @Test func literalMatchesInLaterFieldsOutrankEarlierFuzzyMatches() {
        #expect(ClipboardSearch("hlo").rank(fields: ["hello", "hlo"]) == 3)
        #expect(ClipboardSearch("hlo world").rank(fields: ["hello world", "world hlo"]) == 2)
    }
}
