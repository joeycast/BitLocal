import Foundation
import Testing
@testable import bitlocal

@Suite(.tags(.routing))
struct PlaceDeepLinkResolverTests {
    @Test func invalidIdentifier() async {
        let resolver = PlaceDeepLinkResolver(repository: StubSearchService())
        let result = await resolve(resolver, placeID: "not-a-number")
        #expect(result == .invalidIdentifier)
    }

    @Test func deletedPlace() async {
        let service = StubSearchService()
        service.placeResult = .success(
            makeRecord(id: 9, deletedAt: "2026-01-01T00:00:00Z")
        )
        let resolver = PlaceDeepLinkResolver(repository: service)
        let result = await resolve(resolver, placeID: "9")
        #expect(result == .deleted)
    }

    @Test func successMapsElement() async {
        let service = StubSearchService()
        service.placeResult = .success(makeRecord(id: 42, deletedAt: nil, name: "Cafe"))
        let resolver = PlaceDeepLinkResolver(repository: service)
        let result = await resolve(resolver, placeID: "42")

        if case .success(let element) = result {
            #expect(element.id == "42")
            #expect(element.displayName == "Cafe")
        } else {
            Issue.record("expected success, got \(result)")
        }
    }

    private func resolve(_ resolver: PlaceDeepLinkResolver, placeID: String) async -> PlaceDeepLinkResolution {
        await withCheckedContinuation { continuation in
            resolver.resolve(placeID: placeID) { result in
                continuation.resume(returning: result)
            }
        }
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

private final class StubSearchService: BTCMapSearchServiceProtocol, @unchecked Sendable {
    var placeResult: Result<V4PlaceRecord, Error> = .failure(NSError(domain: "test", code: 1))

    func searchPlaces(query: V4SearchQuery, completion: @escaping @Sendable (Result<[V4PlaceRecord], Error>) -> Void) {
        completion(.success([]))
    }

    func fetchPlace(id: String, completion: @escaping @Sendable (Result<V4PlaceRecord, Error>) -> Void) {
        completion(placeResult)
    }

    func fetchEvents(query: V4EventsQuery, completion: @escaping @Sendable (Result<[V4EventRecord], Error>) -> Void) {
        completion(.success([]))
    }

    func fetchPlaceComments(placeID: String, completion: @escaping @Sendable (Result<[V4PlaceCommentRecord], Error>) -> Void) {
        completion(.success([]))
    }
}
