import XCTest
@testable import bitlocal

final class PlaceDeepLinkResolverTests: XCTestCase {
    func testInvalidIdentifier() {
        let resolver = PlaceDeepLinkResolver(repository: StubSearchService())
        let expectation = expectation(description: "resolve")
        resolver.resolve(placeID: "not-a-number") { result in
            XCTAssertEqual(result, .invalidIdentifier)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }

    func testDeletedPlace() {
        let service = StubSearchService()
        service.placeResult = .success(
            makeRecord(id: 9, deletedAt: "2026-01-01T00:00:00Z")
        )
        let resolver = PlaceDeepLinkResolver(repository: service)
        let expectation = expectation(description: "resolve")
        resolver.resolve(placeID: "9") { result in
            XCTAssertEqual(result, .deleted)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }

    func testSuccessMapsElement() {
        let service = StubSearchService()
        service.placeResult = .success(makeRecord(id: 42, deletedAt: nil, name: "Cafe"))
        let resolver = PlaceDeepLinkResolver(repository: service)
        let expectation = expectation(description: "resolve")
        resolver.resolve(placeID: "42") { result in
            if case .success(let element) = result {
                XCTAssertEqual(element.id, "42")
                XCTAssertEqual(element.displayName, "Cafe")
            } else {
                XCTFail("expected success, got \(result)")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1)
    }

    private func makeRecord(id: Int, deletedAt: String?, name: String = "Place") -> V4PlaceRecord {
        V4PlaceRecord(
            id: id,
            lat: 1,
            lon: 2,
            icon: "cafe",
            name: name,
            address: nil,
            openingHours: nil,
            comments: nil,
            createdAt: "2026-01-01T00:00:00Z",
            updatedAt: "2026-01-01T00:00:00Z",
            deletedAt: deletedAt,
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
    }
}

private final class StubSearchService: BTCMapSearchServiceProtocol {
    var placeResult: Result<V4PlaceRecord, Error> = .failure(NSError(domain: "test", code: 1))

    func searchPlaces(query: V4SearchQuery, completion: @escaping (Result<[V4PlaceRecord], Error>) -> Void) {
        completion(.success([]))
    }

    func fetchPlace(id: String, completion: @escaping (Result<V4PlaceRecord, Error>) -> Void) {
        completion(placeResult)
    }

    func fetchEvents(query: V4EventsQuery, completion: @escaping (Result<[V4EventRecord], Error>) -> Void) {
        completion(.success([]))
    }

    func fetchPlaceComments(placeID: String, completion: @escaping (Result<[V4PlaceCommentRecord], Error>) -> Void) {
        completion(.success([]))
    }
}
