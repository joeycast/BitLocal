import Foundation
import Testing
@testable import bitlocal

@Suite(.serialized, .tags(.sync))
final class BTCMapV4SyncTests {
    private let cacheDirectory: URL
    private let elementsFileURL: URL
    private let syncStateFileURL: URL

    init() throws {
        cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BTCMapV4SyncTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        elementsFileURL = cacheDirectory.appendingPathComponent("btcmap_elements_v4.json")
        syncStateFileURL = cacheDirectory.appendingPathComponent("btcmap_v4_sync_state.json")
    }

    deinit {
        try? FileManager.default.removeItem(at: cacheDirectory)
    }

    @Test func bootstrapUsesSnapshotLastModifiedAsInitialIncrementalAnchor() async {
        let client = MockBTCMapV4Client()
        client.snapshotResult = .success((
            records: [
                V4PlaceSnapshotRecord(
                    id: 1,
                    lat: 1,
                    lon: 2,
                    icon: "local_cafe",
                    comments: 3,
                    boostedUntil: nil,
                    name: nil,
                    displayName: nil
                )
            ],
            lastModified: "Wed, 11 Jun 2025 00:00:00 GMT"
        ))
        client.fetchPlacesResult = .success([])

        let repository = BTCMapRepository(
            v4Client: client,
            userDefaults: testUserDefaults(),
            cacheDirectory: cacheDirectory
        )
        await withCheckedContinuation { continuation in
            repository.refreshElements { _ in
                continuation.resume()
            }
        }

        #expect(client.fetchPlacesUpdatedSinceValues == ["2025-06-11T00:00:00Z"])
    }

    @Test func incrementalSyncFallsBackToSnapshotLastModifiedWhenAnchorMissing() async throws {
        let element = V4PlaceToElementMapper.placeRecordToElement(
            V4PlaceRecord(
                id: 7,
                lat: 1,
                lon: 2,
                icon: "local_cafe",
                name: "Cafe 7",
                address: nil,
                openingHours: nil,
                comments: nil,
                createdAt: "2025-06-10T00:00:00Z",
                updatedAt: "2025-06-10T00:00:00Z",
                deletedAt: nil,
                verifiedAt: nil,
                osmID: nil,
                osmURL: nil,
                phone: nil,
                website: nil,
                twitter: nil,
                facebook: nil,
                instagram: nil,
                line: nil,
                telegram: nil,
                email: nil,
                boostedUntil: nil,
                requiredAppURL: nil,
                description: nil,
                image: nil,
                paymentProvider: nil,
                osmPaymentBitcoin: nil,
                osmCurrencyXBT: nil,
                osmPaymentOnchain: nil,
                osmPaymentLightning: nil,
                osmPaymentLightningContactless: nil,
                osmAddrHouseNumber: nil,
                osmAddrStreet: nil,
                osmAddrCity: nil,
                osmAddrState: nil,
                osmAddrPostcode: nil,
                osmOperator: nil,
                osmBrand: nil,
                osmBrandWikidata: nil
            )
        )
        let elementData = try JSONEncoder().encode([element])
        try elementData.write(to: elementsFileURL, options: .atomic)

        let syncState = V4SyncState(
            snapshotLastModifiedRFC1123: "Wed, 11 Jun 2025 00:00:00 GMT",
            incrementalAnchorUpdatedSince: nil,
            lastSuccessfulSyncAt: nil,
            schemaVersion: V4SyncState.currentSchemaVersion
        )
        let syncStateData = try JSONEncoder().encode(syncState)
        try syncStateData.write(to: syncStateFileURL, options: .atomic)

        let client = MockBTCMapV4Client()
        client.fetchPlacesResult = .success([])

        let repository = BTCMapRepository(
            v4Client: client,
            userDefaults: testUserDefaults(),
            cacheDirectory: cacheDirectory
        )
        await withCheckedContinuation { continuation in
            repository.refreshElements { _ in
                continuation.resume()
            }
        }

        #expect(client.fetchPlacesUpdatedSinceValues == ["2025-06-11T00:00:00Z"])
    }

    @Test func snapshotFailureWithoutCacheReturnsNilWithoutLegacyFallback() async {
        let client = MockBTCMapV4Client()
        client.snapshotResult = .failure(URLError(.notConnectedToInternet))

        let repository = BTCMapRepository(
            v4Client: client,
            userDefaults: testUserDefaults(),
            cacheDirectory: cacheDirectory
        )
        let refreshed: [Element]? = await withCheckedContinuation { continuation in
            repository.refreshElements { elements in
                continuation.resume(returning: elements)
            }
        }

        #expect(refreshed == nil)
        #expect(repository.hasCachedData() == false)
    }

    @Test func incrementalFailureReturnsCachedV4Elements() async throws {
        let cached = V4PlaceToElementMapper.snapshotRecordToElement(
            V4PlaceSnapshotRecord(
                id: 99,
                lat: 37.77,
                lon: -122.42,
                icon: "local_cafe",
                comments: nil,
                boostedUntil: nil,
                name: "Cached Cafe",
                displayName: nil
            ),
            fallbackTimestamp: "2025-06-10T00:00:00Z"
        )
        try JSONEncoder().encode([cached]).write(to: elementsFileURL, options: .atomic)

        let client = MockBTCMapV4Client()
        client.fetchPlacesResult = .failure(URLError(.timedOut))

        let repository = BTCMapRepository(
            v4Client: client,
            userDefaults: testUserDefaults(),
            cacheDirectory: cacheDirectory
        )
        let refreshed: [Element]? = await withCheckedContinuation { continuation in
            repository.refreshElements { elements in
                continuation.resume(returning: elements)
            }
        }

        #expect(refreshed?.map(\.id) == ["99"])
    }

    private func testUserDefaults() -> UserDefaults {
        let suiteName = "BTCMapV4SyncTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        defaults.set(currentVersion, forKey: "btcmap_last_app_version")
        return defaults
    }
}

private final class MockBTCMapV4Client: BTCMapV4ClientProtocol, @unchecked Sendable {
    var snapshotResult: Result<(records: [V4PlaceSnapshotRecord], lastModified: String?), Error> = .success((records: [], lastModified: nil))
    var fetchPlacesResult: Result<[V4PlaceRecord], Error> = .success([])
    var fetchPlacesUpdatedSinceValues: [String] = []

    func fetchSnapshot(completion: @escaping @Sendable (Result<(records: [V4PlaceSnapshotRecord], lastModified: String?), Error>) -> Void) {
        completion(snapshotResult)
    }

    func fetchPlaces(updatedSince: String, includeDeleted: Bool, completion: @escaping @Sendable (Result<[V4PlaceRecord], Error>) -> Void) {
        fetchPlacesUpdatedSinceValues.append(updatedSince)
        completion(fetchPlacesResult)
    }

    func searchPlaces(query: V4SearchQuery, completion: @escaping @Sendable (Result<[V4PlaceRecord], Error>) -> Void) {
        completion(.success([]))
    }

    func fetchPlace(id: String, completion: @escaping @Sendable (Result<V4PlaceRecord, Error>) -> Void) {
        completion(.failure(MockError.unimplemented))
    }

    func fetchEvents(query: V4EventsQuery, completion: @escaping @Sendable (Result<[V4EventRecord], Error>) -> Void) {
        completion(.success([]))
    }

    func fetchPlaceComments(placeID: String, completion: @escaping @Sendable (Result<[V4PlaceCommentRecord], Error>) -> Void) {
        completion(.success([]))
    }

    private enum MockError: Error {
        case unimplemented
    }
}
