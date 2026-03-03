import XCTest
@testable import bitlocal

final class V4SearchQueryEncodingTests: XCTestCase {
    func testEncodesNameRadiusAndTagFilters() {
        let query = V4SearchQuery(
            name: "coffee",
            lat: 36.12,
            lon: -86.67,
            radiusKM: 20,
            tagName: "payment:coinos",
            tagValue: "yes"
        )

        let items = Dictionary(uniqueKeysWithValues: query.queryItems().compactMap { item in
            item.value.map { (item.name, $0) }
        })

        XCTAssertEqual(items["name"], "coffee")
        XCTAssertEqual(items["lat"], "36.12")
        XCTAssertEqual(items["lon"], "-86.67")
        XCTAssertEqual(items["radius_km"], "20.0")
        XCTAssertEqual(items["tag_name"], "payment:coinos")
        XCTAssertEqual(items["tag_value"], "yes")
    }

    func testShortNameIsStillAValidNameFilter() {
        let query = V4SearchQuery(name: "ab", lat: nil, lon: nil, radiusKM: nil, tagName: nil, tagValue: nil)
        XCTAssertFalse(query.isEmpty)
        let items = Dictionary(uniqueKeysWithValues: query.queryItems().compactMap { item in
            item.value.map { (item.name, $0) }
        })
        XCTAssertEqual(items["name"], "ab")
    }
}
