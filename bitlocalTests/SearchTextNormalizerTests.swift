import XCTest
@testable import bitlocal

final class SearchTextNormalizerTests: XCTestCase {
    func testNormalizesPunctuationAndCase() {
        let normalized = SearchTextNormalizer.normalize("Steak 'n Shake")
        XCTAssertEqual(normalized, "steak n shake")
    }

    func testNormalizesDiacritics() {
        let normalized = SearchTextNormalizer.normalize("Café Crème")
        XCTAssertEqual(normalized, "cafe creme")
    }

    func testMatchesWithTokenPrefixes() {
        let query = SearchTextNormalizer.normalize("ste n sh")
        let candidate = SearchTextNormalizer.normalize("Steak 'n Shake")
        XCTAssertTrue(SearchTextNormalizer.matches(normalizedQuery: query, normalizedCandidate: candidate))
    }

    func testDoesNotMatchDifferentTokens() {
        let query = SearchTextNormalizer.normalize("pizza")
        let candidate = SearchTextNormalizer.normalize("Steak 'n Shake")
        XCTAssertFalse(SearchTextNormalizer.matches(normalizedQuery: query, normalizedCandidate: candidate))
    }
}
