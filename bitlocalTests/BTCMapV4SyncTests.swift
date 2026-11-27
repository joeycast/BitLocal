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

    @Test func concurrentRefreshesCoalesceIntoSingleUpstreamFetch() async {
        let client = MockBTCMapV4Client()
        client.snapshotDelayMilliseconds = 80
        client.snapshotResult = .success((
            records: [
                V4PlaceSnapshotRecord(
                    id: 42,
                    lat: 30.26,
                    lon: -97.74,
                    icon: "local_cafe",
                    comments: 1,
                    boostedUntil: nil,
                    name: "Coalesced Cafe",
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

        let results: [[String]] = await withTaskGroup(of: [String].self) { group in
            for _ in 0..<5 {
                group.addTask {
                    let elements = await repository.refreshElements()
                    return elements?.map(\.id) ?? []
                }
            }
            var collected: [[String]] = []
            for await ids in group {
                collected.append(ids)
            }
            return collected
        }

        #expect(client.snapshotCallCount == 1)
        #expect(results.count == 5)
        for ids in results {
            #expect(ids == ["42"])
        }
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
    private let lock = NSLock()
    var snapshotResult: Result<(records: [V4PlaceSnapshotRecord], lastModified: String?), Error> = .success((records: [], lastModified: nil))
    var fetchPlacesResult: Result<[V4PlaceRecord], Error> = .success([])
    var fetchPlacesUpdatedSinceValues: [String] = []
    var snapshotDelayMilliseconds: Int = 0
    private var _snapshotCallCount = 0

    var snapshotCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _snapshotCallCount
    }

    func fetchSnapshot(completion: @escaping @Sendable (Result<(records: [V4PlaceSnapshotRecord], lastModified: String?), Error>) -> Void) {
        lock.lock()
        _snapshotCallCount += 1
        let delay = snapshotDelayMilliseconds
        let result = snapshotResult
        lock.unlock()

        if delay > 0 {
            Task {
                try? await Task.sleep(for: .milliseconds(delay))
                completion(result)
            }
        } else {
            completion(result)
        }
    }

    func fetchPlaces(updatedSince: String, includeDeleted: Bool, completion: @escaping @Sendable (Result<[V4PlaceRecord], Error>) -> Void) {
        lock.lock()
        fetchPlacesUpdatedSinceValues.append(updatedSince)
        let result = fetchPlacesResult
        lock.unlock()
        completion(result)
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
