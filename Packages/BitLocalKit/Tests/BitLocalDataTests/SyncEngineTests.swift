import Foundation
import Testing
@testable import BitLocalData
import BitLocalDomain

actor FakeClient: BTCMapPlacesClient {
    var snapshotPlaces: [BTCMapSnapshotPlace] = []
    var snapshotDate: Date? = Date(timeIntervalSince1970: 1_700_000_000)
    var pages: [[BTCMapPlace]] = []
    var requestedAnchors: [String] = []
    var snapshotCalls = 0
    var single: [Int: BTCMapPlace] = [:]

    init(snapshot: [BTCMapSnapshotPlace] = [], pages: [[BTCMapPlace]] = [], single: [Int: BTCMapPlace] = [:]) {
        self.snapshotPlaces = snapshot
        self.pages = pages
        self.single = single
    }

    func snapshot() async throws -> (places: [BTCMapSnapshotPlace], lastModified: Date?) {
        snapshotCalls += 1
        return (snapshotPlaces, snapshotDate)
    }

    func places(updatedSince: String, limit: Int) async throws -> [BTCMapPlace] {
        requestedAnchors.append(updatedSince)
        return pages.isEmpty ? [] : pages.removeFirst()
    }

    func place(id: MerchantID) async throws -> BTCMapPlace {
        guard let place = single[id.rawValue] else { throw BTCMapClientError.httpStatus(404) }
        return place
    }
}

func place(_ id: Int, name: String = "Shop", updated: String = "2026-11-01T00:00:00Z", deleted: String? = nil) -> BTCMapPlace {
    var place = BTCMapPlace(id: id)
    place.lat = 36.16
    place.lon = -86.78
    place.icon = "local_cafe"
    place.name = name
    place.updatedAt = updated
    place.deletedAt = deleted
    return place
}

@Suite("SyncEngine")
struct SyncEngineTests {
    @Test func bootstrapsFromSnapshotThenAppliesIncrementalChanges() async throws {
        let store = try MerchantStore(url: nil)
        let client = FakeClient(
            snapshot: [BTCMapSnapshotPlace(id: 1, lat: 36.1, lon: -86.7, icon: "local_cafe"),
                       BTCMapSnapshotPlace(id: 2, lat: 36.2, lon: -86.8, icon: "local_cafe")],
            pages: [[place(1, name: "Real Name"), place(2, deleted: "2026-11-02T00:00:00Z")]]
        )
        let engine = SyncEngine(store: store, client: client, mapper: MerchantMapper())
        let result = try await engine.sync()

        #expect(result.bootstrapped)
        #expect(try await store.count() == 1)
        #expect(try await store.merchant(MerchantID(1))?.summary.name == "Real Name")
        #expect(try await store.merchant(MerchantID(1))?.isHydrated == true)
        #expect(await client.requestedAnchors == ["2023-11-14T22:13:20Z"])
        #expect(try await store.syncValue(forKey: SyncEngine.Key.anchor) == "2026-11-01T00:00:00Z")
        #expect(try await engine.lastSuccess() != nil)
    }

    @Test func secondSyncSkipsSnapshotAndResumesFromAnchor() async throws {
        let store = try MerchantStore(url: nil)
        let client = FakeClient(snapshot: [BTCMapSnapshotPlace(id: 1, lat: 1, lon: 1)],
                                pages: [[place(1, updated: "2026-11-03T00:00:00Z")], []])
        let engine = SyncEngine(store: store, client: client, mapper: MerchantMapper())
        try await engine.sync()
        let second = try await engine.sync()
        #expect(!second.bootstrapped)
        #expect(await client.snapshotCalls == 1)
        #expect(await client.requestedAnchors.last == "2026-11-03T00:00:00Z")
    }

    @Test func hydrateFetchesOnePlace() async throws {
        let store = try MerchantStore(url: nil)
        let client = FakeClient(single: [7: place(7, name: "Hydrated")])
        let engine = SyncEngine(store: store, client: client, mapper: MerchantMapper())
        let merchant = try await engine.hydrate(MerchantID(7))
        #expect(merchant?.summary.name == "Hydrated")
        #expect(merchant?.isHydrated == true)
    }

    @Test func httpDateParsing() {
        #expect(BTCMapClient.parseHTTPDate("Tue, 14 Nov 2023 22:13:20 GMT") == Date(timeIntervalSince1970: 1_700_000_000))
    }
}
