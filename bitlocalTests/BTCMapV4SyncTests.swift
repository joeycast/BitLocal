import XCTest
@testable import bitlocal

final class BTCMapV4SyncTests: XCTestCase {
    private let elementsFileURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        .appendingPathComponent("btcmap_elements_v4.json")
    private let syncStateFileURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        .appendingPathComponent("btcmap_v4_sync_state.json")

    override func setUpWithError() throws {
        try super.setUpWithError()
        try removeV4CacheFiles()
    }

    override func tearDownWithError() throws {
        try removeV4CacheFiles()
        try super.tearDownWithError()
    }

    func testBootstrapUsesSnapshotLastModifiedAsInitialIncrementalAnchor() {
        let client = MockBTCMapV4Client()
        client.snapshotResult = .success((
            records: [
                V4PlaceSnapshotRecord(
                    id: 1,
                    lat: 1,
                    lon: 2,
                    icon: "local_cafe",
                    comments: 3,
                    boostedUntil: nil
                )
            ],
            lastModified: "Wed, 11 Jun 2025 00:00:00 GMT"
        ))
        client.fetchPlacesResult = .success([])

        let repository = BTCMapRepository(v4Client: client, userDefaults: testUserDefaults())
        let expectation = expectation(description: "refresh completes")

        repository.refreshElements { _ in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2)

        XCTAssertEqual(client.fetchPlacesUpdatedSinceValues, ["2025-06-11T00:00:00Z"])
    }

    func testIncrementalSyncFallsBackToSnapshotLastModifiedWhenAnchorMissing() throws {
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

        let repository = BTCMapRepository(v4Client: client, userDefaults: testUserDefaults())
        let expectation = expectation(description: "refresh completes")

        repository.refreshElements { _ in
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2)

        XCTAssertEqual(client.fetchPlacesUpdatedSinceValues, ["2025-06-11T00:00:00Z"])
    }

    private func removeV4CacheFiles() throws {
        for url in [elementsFileURL, syncStateFileURL] {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    private func testUserDefaults() -> UserDefaults {
        let suiteName = "BTCMapV4SyncTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private final class MockBTCMapV4Client: BTCMapV4ClientProtocol {
    var snapshotResult: Result<(records: [V4PlaceSnapshotRecord], lastModified: String?), Error> = .success((records: [], lastModified: nil))
    var fetchPlacesResult: Result<[V4PlaceRecord], Error> = .success([])
    var fetchPlacesUpdatedSinceValues: [String] = []

    func fetchSnapshot(completion: @escaping (Result<(records: [V4PlaceSnapshotRecord], lastModified: String?), Error>) -> Void) {
        completion(snapshotResult)
    }

    func fetchPlaces(updatedSince: String, includeDeleted: Bool, completion: @escaping (Result<[V4PlaceRecord], Error>) -> Void) {
        fetchPlacesUpdatedSinceValues.append(updatedSince)
        completion(fetchPlacesResult)
    }

    func searchPlaces(query: V4SearchQuery, completion: @escaping (Result<[V4PlaceRecord], Error>) -> Void) {
        completion(.success([]))
    }

    func fetchPlace(id: String, completion: @escaping (Result<V4PlaceRecord, Error>) -> Void) {
        completion(.failure(MockError.unimplemented))
    }

    func fetchEvents(query: V4EventsQuery, completion: @escaping (Result<[V4EventRecord], Error>) -> Void) {
        completion(.success([]))
    }

    func fetchPlaceComments(placeID: String, completion: @escaping (Result<[V4PlaceCommentRecord], Error>) -> Void) {
        completion(.success([]))
    }

    private enum MockError: Error {
        case unimplemented
    }
}
