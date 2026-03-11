import XCTest
@testable import bitlocal

@MainActor
final class MerchantAlertDigestLookupTests: XCTestCase {
    func testActivateDigestFetchesMissingMerchantIDsWithoutBroadRefresh() async {
        let repo = DigestLookupRepository()
        let existing = V4PlaceToElementMapper.placeRecordToElement(Self.placeRecord(id: 1, name: "Cached Merchant"))
        repo.elementsByID = ["1": existing]
        repo.fetchPlaceHandler = { id, completion in
            completion(.success(Self.placeRecord(id: Int(id) ?? 0, name: "Fetched \(id)")))
        }

        let viewModel = ContentViewModel(btcMapRepository: repo)
        viewModel.setAllElementsForTesting([existing])

        let digest = CityDigest(
            id: "digest-1",
            locationID: "geonames:123",
            cityKey: "nashville|tennessee|united states",
            cityDisplayName: "Nashville, Tennessee, United States",
            digestWindowStart: nil,
            digestWindowEnd: nil,
            merchantCount: 2,
            merchantIDs: ["1", "2"],
            topMerchantNames: ["Cached Merchant", "Fetched 2"],
            timeZoneID: nil,
            deliveryLocalDate: nil
        )

        viewModel.activateMerchantAlertDigest(digest)
        await waitForDigestMerchantCount(2, on: viewModel)

        XCTAssertEqual(repo.refreshElementsCallCount, 0)
        XCTAssertEqual(repo.fetchedPlaceIDs, ["2"])
        XCTAssertEqual(viewModel.listElementsForCurrentDisplay.map(\.id), ["1", "2"])
    }

    private func waitForDigestMerchantCount(_ count: Int, on viewModel: ContentViewModel) async {
        for _ in 0..<40 {
            if viewModel.listElementsForCurrentDisplay.count == count {
                return
            }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
    }

    private static func placeRecord(id: Int, name: String) -> V4PlaceRecord {
        V4PlaceRecord(
            id: id,
            lat: 36.17,
            lon: -86.78,
            icon: "local_cafe",
            name: name,
            address: nil,
            openingHours: nil,
            comments: nil,
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: "2026-01-01T00:00:00Z",
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
            osmAddrCountry: nil,
            osmAddrState: nil,
            osmAddrPostcode: nil,
            osmOperator: nil,
            osmBrand: name,
            osmBrandWikidata: nil
        )
    }
}

private final class DigestLookupRepository: BTCMapRepositoryProtocol {
    var elementsByID: [String: Element] = [:]
    var fetchedPlaceIDs: [String] = []
    var refreshElementsCallCount = 0
    var fetchPlaceHandler: ((String, @escaping (Result<V4PlaceRecord, Error>) -> Void) -> Void)?

    func searchPlaces(query: V4SearchQuery, completion: @escaping (Result<[V4PlaceRecord], Error>) -> Void) {
        completion(.success([]))
    }

    func fetchPlace(id: String, completion: @escaping (Result<V4PlaceRecord, Error>) -> Void) {
        fetchedPlaceIDs.append(id)
        if let fetchPlaceHandler {
            fetchPlaceHandler(id, completion)
        } else {
            completion(.failure(NSError(domain: "DigestLookupRepository", code: 404)))
        }
    }

    func fetchEvents(query: V4EventsQuery, completion: @escaping (Result<[V4EventRecord], Error>) -> Void) {
        completion(.success([]))
    }

    func fetchPlaceComments(placeID: String, completion: @escaping (Result<[V4PlaceCommentRecord], Error>) -> Void) {
        completion(.success([]))
    }

    func loadCachedElements() -> [Element]? {
        Array(elementsByID.values)
    }

    func loadCachedElements(ids: [String]) -> [Element] {
        ids.compactMap { elementsByID[$0] }
    }

    func hasCachedData() -> Bool {
        !elementsByID.isEmpty
    }

    func refreshElements(completion: @escaping ([Element]?) -> Void) {
        refreshElementsCallCount += 1
        completion(Array(elementsByID.values))
    }

    func upsertFetchedPlace(_ record: V4PlaceRecord) -> Element {
        let element = V4PlaceToElementMapper.placeRecordToElement(record)
        elementsByID[element.id] = element
        return element
    }

    func persistMergedAddress(_ address: Address?, forMerchantID merchantID: String) -> Element? {
        guard var element = elementsByID[merchantID] else { return nil }
        element.address = address
        elementsByID[merchantID] = element
        return element
    }

    func processAddressEnrichmentJobs(limit: Int) {}

    func fetchV2Areas(updatedSince: String, limit: Int, completion: @escaping (Result<[V2AreaRecord], Error>) -> Void) {
        completion(.success([]))
    }

    func fetchV3Areas(updatedSince: String, limit: Int, completion: @escaping (Result<[V3AreaRecord], Error>) -> Void) {
        completion(.success([]))
    }

    func fetchV3Area(id: Int, completion: @escaping (Result<V3AreaRecord, Error>) -> Void) {
        completion(.failure(NSError(domain: "DigestLookupRepository", code: 404)))
    }

    func fetchV3AreaElements(areaID: Int, updatedSince: String, limit: Int, completion: @escaping (Result<[V3AreaElementRecord], Error>) -> Void) {
        completion(.success([]))
    }
}
