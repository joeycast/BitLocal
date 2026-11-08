import Foundation
import Testing
@testable import BitLocalData
import BitLocalDomain

func makeMerchant(
    _ id: Int,
    lat: Double = 36.16,
    lon: Double = -86.78,
    name: String = "Shop",
    category: String = "local_cafe",
    payments: PaymentMethods = [.lightning],
    hydrated: Bool = true,
    updated: TimeInterval = 1_000
) -> Merchant {
    Merchant(
        summary: MerchantSummary(
            id: MerchantID(id), coordinate: Coordinate(latitude: lat, longitude: lon), name: name,
            hasRealName: true, category: MerchantCategory(rawValue: category), paymentMethods: payments,
            boostedUntil: nil, openingHours: "Mo-Fr 09:00-17:00", updatedAt: Date(timeIntervalSince1970: updated)
        ),
        address: PostalAddress(houseNumber: "1", street: "Main St", city: "Nashville"),
        contact: Contact(phone: "+1 555", website: URL(string: "https://example.com")),
        socials: [SocialLink(network: .twitter, url: URL(string: "https://x.com/shop")!)],
        about: "About",
        commentsCount: 2,
        isHydrated: hydrated
    )
}

@Suite("MerchantStore")
struct MerchantStoreTests {
    @Test func sqliteHasRTreeAndFTS5() async throws {
        let store = try MerchantStore(url: nil)
        #expect(try await store.supportsRequiredModules())
    }

    @Test func upsertAndReadBack() async throws {
        let store = try MerchantStore(url: nil)
        try await store.apply(SyncBatch(upserts: [makeMerchant(1)]))
        let merchant = try #require(try await store.merchant(MerchantID(1)))
        #expect(merchant.summary.name == "Shop")
        #expect(merchant.address?.streetLine == "1 Main St")
        #expect(merchant.contact.website?.host == "example.com")
        #expect(merchant.socials.count == 1)
        #expect(merchant.summary.paymentMethods == [.lightning])
        #expect(merchant.summary.openingHours == "Mo-Fr 09:00-17:00")
        #expect(merchant.isHydrated)
        #expect(try await store.count() == 1)
    }

    @Test func viewportQueryUsesRTree() async throws {
        let store = try MerchantStore(url: nil)
        try await store.apply(SyncBatch(upserts: [
            makeMerchant(1, lat: 36.16, lon: -86.78),
            makeMerchant(2, lat: 40.71, lon: -74.00),
        ]))
        let rect = GeoRect(center: Coordinate(latitude: 36.16, longitude: -86.78), latitudeDelta: 1, longitudeDelta: 1)
        let ids = try await store.summaries(in: rect).map(\.id)
        #expect(ids == [MerchantID(1)])
    }

    @Test func antimeridianViewport() async throws {
        let store = try MerchantStore(url: nil)
        try await store.apply(SyncBatch(upserts: [
            makeMerchant(1, lat: -17, lon: 179.5),
            makeMerchant(2, lat: -17, lon: -179.5),
            makeMerchant(3, lat: -17, lon: 170),
        ]))
        let rect = GeoRect(center: Coordinate(latitude: -17, longitude: 180), latitudeDelta: 2, longitudeDelta: 4)
        let ids = Set(try await store.summaries(in: rect).map(\.id))
        #expect(ids == [MerchantID(1), MerchantID(2)])
    }

    @Test func filtersApplyInSQL() async throws {
        let store = try MerchantStore(url: nil)
        try await store.apply(SyncBatch(upserts: [
            makeMerchant(1, category: "local_cafe", payments: [.lightning]),
            makeMerchant(2, category: "local_atm", payments: [.onchain]),
            makeMerchant(3, category: "restaurant", payments: [.onchain]),
        ]))
        #expect(try await store.count(filter: MerchantFilter(hideATMs: true)) == 2)
        #expect(try await store.count(filter: MerchantFilter(paymentMethods: [.lightning])) == 1)
        #expect(try await store.count(filter: MerchantFilter(categories: [MerchantCategory(rawValue: "restaurant")])) == 1)
    }

    @Test func thinRowNeverReplacesHydratedRow() async throws {
        let store = try MerchantStore(url: nil)
        try await store.apply(SyncBatch(upserts: [makeMerchant(1, name: "Real")]))
        try await store.apply(SyncBatch(upserts: [makeMerchant(1, name: "Coffee", hydrated: false)]))
        #expect(try await store.merchant(MerchantID(1))?.summary.name == "Real")
    }

    @Test func olderHydratedRowIsIgnoredNewerWins() async throws {
        let store = try MerchantStore(url: nil)
        try await store.apply(SyncBatch(upserts: [makeMerchant(1, name: "B", updated: 2_000)]))
        try await store.apply(SyncBatch(upserts: [makeMerchant(1, name: "A", updated: 1_000)]))
        #expect(try await store.merchant(MerchantID(1))?.summary.name == "B")
        try await store.apply(SyncBatch(upserts: [makeMerchant(1, name: "C", updated: 3_000)]))
        #expect(try await store.merchant(MerchantID(1))?.summary.name == "C")
    }

    @Test func deletionRemovesFromAllTables() async throws {
        let store = try MerchantStore(url: nil)
        try await store.apply(SyncBatch(upserts: [makeMerchant(1)]))
        let change = try await store.apply(SyncBatch(deletions: [MerchantID(1)]))
        #expect(change.changedIDs == [MerchantID(1)])
        #expect(try await store.merchant(MerchantID(1)) == nil)
        let rect = GeoRect(center: Coordinate(latitude: 36.16, longitude: -86.78), latitudeDelta: 1, longitudeDelta: 1)
        #expect(try await store.summaries(in: rect).isEmpty)
    }

    @Test func syncStateIsSavedWithTheBatch() async throws {
        let store = try MerchantStore(url: nil)
        try await store.apply(SyncBatch(upserts: [makeMerchant(1)], syncState: ["anchor": "2026-11-08T00:00:00Z"]))
        #expect(try await store.syncValue(forKey: "anchor") == "2026-11-08T00:00:00Z")
    }

    @Test func nearestIsSortedByDistance() async throws {
        let store = try MerchantStore(url: nil)
        let origin = Coordinate(latitude: 36.0, longitude: -86.0)
        try await store.apply(SyncBatch(upserts: [
            makeMerchant(1, lat: 36.30, lon: -86.0),
            makeMerchant(2, lat: 36.01, lon: -86.0),
            makeMerchant(3, lat: 36.05, lon: -86.0),
            makeMerchant(4, lat: 40.00, lon: -86.0),
        ]))
        #expect(try await store.nearest(to: origin, limit: 3).map(\.id.rawValue) == [2, 3, 1])
        #expect(try await store.nearest(to: origin, limit: 2, offset: 2).map(\.id.rawValue) == [1, 4])
    }

    @Test func summariesByIDKeepOrder() async throws {
        let store = try MerchantStore(url: nil)
        try await store.apply(SyncBatch(upserts: [makeMerchant(1), makeMerchant(2), makeMerchant(3)]))
        #expect(try await store.summaries(ids: [MerchantID(3), MerchantID(9), MerchantID(1)]).map(\.id.rawValue) == [3, 1])
    }

    @Test func changeStreamReportsBatches() async throws {
        let store = try MerchantStore(url: nil)
        let stream = await store.changes()
        try await store.apply(SyncBatch(upserts: [makeMerchant(5)]))
        var iterator = stream.makeAsyncIterator()
        let change = await iterator.next()
        #expect(change?.changedIDs == [MerchantID(5)])
    }

    @Test func persistsAcrossReopen() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("merchants.sqlite")
        do {
            let store = try MerchantStore(url: url)
            try await store.apply(SyncBatch(upserts: [makeMerchant(1)]))
        }
        let reopened = try MerchantStore(url: url)
        #expect(try await reopened.count() == 1)
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}
