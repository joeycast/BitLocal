import Foundation
import Testing
@testable import BitLocalData
import BitLocalDomain

@Suite("Merchant search")
struct MerchantSearchTests {
    @Test func buildsSafePrefixExpressions() {
        #expect(FTSQuery.expression(for: "Café  Nash") == "\"cafe\"* \"nash\"*")
        #expect(FTSQuery.expression(for: "\"OR\" NEAR(") == "\"or\"* \"near\"*")
        #expect(FTSQuery.expression(for: "  ,;  ") == nil)
        #expect(FTSQuery.tokens("Ünïcödé-Shop 5") == ["unicode", "shop", "5"])
    }

    @Test func prefixMatchesNamesAndIgnoresAccents() async throws {
        let store = try MerchantStore(url: nil)
        try await store.apply(SyncBatch(upserts: [
            makeMerchant(1, name: "Crème Café"),
            makeMerchant(2, name: "Hardware Store", category: "hardware"),
        ]))
        let hits = try await store.search("creme ca")
        #expect(hits.map(\.summary.id) == [MerchantID(1)])
        #expect(hits.first?.matchesName == true)
    }

    @Test func nameMatchesComeBeforeCategoryMatchesThenDistance() async throws {
        let store = try MerchantStore(url: nil, categoryTerms: { $0.rawValue == "local_cafe" ? "coffee cafe" : $0.rawValue })
        try await store.apply(SyncBatch(upserts: [
            makeMerchant(1, lat: 36.20, name: "Bean There", category: "local_cafe"),       // category match, near
            makeMerchant(2, lat: 40.00, name: "Coffee Republic", category: "local_cafe"),  // name match, far
            makeMerchant(3, lat: 36.17, name: "Coffee Corner", category: "local_cafe"),    // name match, near
        ]))
        let hits = try await store.search("coffee", near: Coordinate(latitude: 36.16, longitude: -86.78))
        #expect(hits.map(\.summary.id.rawValue) == [3, 2, 1])
        #expect(hits[0].distance! < hits[1].distance!)
    }

    @Test func respectsFilterAndLimit() async throws {
        let store = try MerchantStore(url: nil)
        try await store.apply(SyncBatch(upserts: [
            makeMerchant(1, name: "Shop One", category: "local_atm"),
            makeMerchant(2, name: "Shop Two"),
            makeMerchant(3, name: "Shop Three"),
        ]))
        let hits = try await store.search("shop", filter: MerchantFilter(hideATMs: true), limit: 1)
        #expect(hits.count == 1)
        #expect(hits[0].summary.id != MerchantID(1))
    }

    @Test func deletedMerchantsLeaveTheIndex() async throws {
        let store = try MerchantStore(url: nil)
        try await store.apply(SyncBatch(upserts: [makeMerchant(1, name: "Gone Bakery")]))
        try await store.apply(SyncBatch(deletions: [MerchantID(1)]))
        #expect(try await store.search("bakery").isEmpty)
    }

    @Test func recentSearchesAreNewestFirstAndDeduplicated() async throws {
        let store = try MerchantStore(url: nil)
        try await store.recordRecentSearch("coffee", at: Date(timeIntervalSince1970: 1))
        try await store.recordRecentSearch("atm", at: Date(timeIntervalSince1970: 2))
        try await store.recordRecentSearch("coffee", at: Date(timeIntervalSince1970: 3))
        try await store.recordRecentSearch("  ", at: Date(timeIntervalSince1970: 4))
        #expect(try await store.recentSearches() == ["coffee", "atm"])
        try await store.deleteRecentSearch("coffee")
        #expect(try await store.recentSearches() == ["atm"])
    }

    @Test func recentSearchesKeepOnlyTheNewest() async throws {
        let store = try MerchantStore(url: nil)
        for i in 0..<5 {
            try await store.recordRecentSearch("q\(i)", at: Date(timeIntervalSince1970: Double(i)), keep: 3)
        }
        #expect(try await store.recentSearches(limit: 10) == ["q4", "q3", "q2"])
    }
}
