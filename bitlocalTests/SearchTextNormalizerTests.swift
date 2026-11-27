import Testing
@testable import bitlocal

@Suite(.tags(.search))
struct SearchTextNormalizerTests {
    @Test(arguments: [
        ("Steak 'n Shake", "steak n shake"),
        ("Café Crème", "cafe creme")
    ])
    func normalizesPunctuationCaseAndDiacritics(raw: String, expected: String) {
        #expect(SearchTextNormalizer.normalize(raw) == expected)
    }

    @Test func matchesWithTokenPrefixes() {
        let query = SearchTextNormalizer.normalize("ste n sh")
        let candidate = SearchTextNormalizer.normalize("Steak 'n Shake")
        #expect(SearchTextNormalizer.matches(normalizedQuery: query, normalizedCandidate: candidate))
    }

    @Test func doesNotMatchDifferentTokens() {
        let query = SearchTextNormalizer.normalize("pizza")
        let candidate = SearchTextNormalizer.normalize("Steak 'n Shake")
        #expect(SearchTextNormalizer.matches(normalizedQuery: query, normalizedCandidate: candidate) == false)
    }
}
