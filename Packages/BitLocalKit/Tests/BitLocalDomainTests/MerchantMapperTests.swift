import Foundation
import Testing
@testable import BitLocalDomain

@Suite("MerchantMapper")
struct MerchantMapperTests {
    let mapper = MerchantMapper(categoryName: { $0.rawValue == "local_cafe" ? "Coffee shop" : "Place" })

    func place(_ configure: (inout BTCMapPlace) -> Void = { _ in }) -> BTCMapPlace {
        var place = BTCMapPlace(id: 42)
        place.lat = 36.16
        place.lon = -86.78
        place.icon = "local_cafe"
        place.name = "Prickly Pear Coffee"
        place.updatedAt = "2026-10-01T12:00:00.000Z"
        configure(&place)
        return place
    }

    @Test func mapsTypedFields() throws {
        let merchant = try #require(mapper.merchant(from: place {
            $0.osmPaymentLightning = "yes"
            $0.osmPaymentOnchain = "yes"
            $0.website = "pricklypear.coffee"
            $0.osmAddrHouseNumber = "12"
            $0.osmAddrStreet = "Main St"
            $0.osmAddrCity = "Nashville"
            $0.osmAddrPostcode = "37203-1234"
            $0.comments = 3
        }))
        #expect(merchant.id == MerchantID(42))
        #expect(merchant.summary.name == "Prickly Pear Coffee")
        #expect(merchant.summary.hasRealName)
        #expect(merchant.summary.paymentMethods == [.lightning, .onchain])
        #expect(merchant.contact.website?.absoluteString == "https://pricklypear.coffee")
        #expect(merchant.address?.streetLine == "12 Main St")
        #expect(merchant.address?.postalCode == "37203")
        #expect(merchant.commentsCount == 3)
        #expect(merchant.isHydrated)
    }

    @Test func placeholderNameFallsBackToCategory() throws {
        let merchant = try #require(mapper.merchant(from: place { $0.name = "BTC Map Place #42" }))
        #expect(merchant.summary.name == "Coffee shop")
        #expect(!merchant.summary.hasRealName)
    }

    @Test func brandAndOperatorBeatCategoryFallback() throws {
        let branded = try #require(mapper.merchant(from: place { $0.name = nil; $0.osmBrand = "Starbucks" }))
        #expect(branded.summary.name == "Starbucks")
        let operated = try #require(mapper.merchant(from: place { $0.name = "unnamed"; $0.osmOperator = "City" }))
        #expect(operated.summary.name == "City")
    }

    @Test func deletedOrUnlocatedPlacesAreDropped() {
        #expect(mapper.merchant(from: place { $0.deletedAt = "2026-10-02T00:00:00Z" }) == nil)
        #expect(mapper.merchant(from: place { $0.lat = nil }) == nil)
        #expect(mapper.merchant(from: place { $0.lat = 0; $0.lon = 0 }) == nil)
    }

    @Test func snapshotRecordsAreThin() throws {
        let merchant = try #require(mapper.merchant(from: BTCMapSnapshotPlace(id: 7, lat: 1, lon: 2, icon: "local_cafe")))
        #expect(!merchant.isHydrated)
        #expect(merchant.summary.name == "Coffee shop")
        #expect(merchant.summary.paymentMethods.isEmpty)
    }

    @Test func boostIsTimeDependent() throws {
        let merchant = try #require(mapper.merchant(from: place { $0.boostedUntil = "2026-12-01T00:00:00Z" }))
        let before = try #require(BTCMapDate.parse("2026-11-01"))
        let after = try #require(BTCMapDate.parse("2026-12-02"))
        #expect(merchant.summary.isBoosted(at: before))
        #expect(!merchant.summary.isBoosted(at: after))
    }

    @Test func socialHandlesBecomeURLs() throws {
        let merchant = try #require(mapper.merchant(from: place {
            $0.twitter = "@prickly"
            $0.instagram = "https://instagram.com/prickly"
        }))
        #expect(merchant.socials.map(\.url.absoluteString) == ["https://x.com/prickly", "https://instagram.com/prickly"])
    }

    @Test func rejectsNonWebURLs() {
        #expect(MerchantMapper.webURL("javascript:alert(1)") == nil)
        #expect(MerchantMapper.webURL("  ") == nil)
        #expect(MerchantMapper.webURL("http://example.com")?.host == "example.com")
    }
}

@Suite("PaymentMethods")
struct PaymentMethodsTests {
    @Test func genericBitcoinOnlyWithoutSpecificTags() {
        #expect(PaymentMethods(paymentBitcoin: "yes") == [.bitcoinUnspecified])
        #expect(PaymentMethods(paymentBitcoin: "yes", paymentLightning: "yes") == [.lightning])
        #expect(PaymentMethods(currencyXBT: "YES") == [.bitcoinUnspecified])
    }

    @Test func lightningOnlyBrandsInferredWhenUntagged() {
        #expect(PaymentMethods(brandWikidata: "Q7605233") == [.lightning])
        #expect(PaymentMethods(paymentOnchain: "no", brand: "Steak n Shake") == [])
    }

    @Test func contactless() {
        #expect(PaymentMethods(paymentLightningContactless: "yes") == [.lightningContactless])
    }
}

@Suite("Geometry")
struct GeometryTests {
    @Test func haversine() {
        let nashville = Coordinate(latitude: 36.1627, longitude: -86.7816)
        let memphis = Coordinate(latitude: 35.1495, longitude: -90.0490)
        #expect(abs(nashville.distance(to: memphis) - 316_000) < 3_000)
    }

    @Test func antimeridianSplit() {
        let rect = GeoRect(center: Coordinate(latitude: 0, longitude: 179), latitudeDelta: 2, longitudeDelta: 4)
        #expect(rect.crossesAntimeridian)
        #expect(rect.normalizedParts.count == 2)
        #expect(rect.contains(Coordinate(latitude: 0, longitude: -179.5)))
        #expect(!rect.contains(Coordinate(latitude: 0, longitude: 170)))
    }

    @Test func expandByMargin() {
        let rect = GeoRect(minLatitude: 0, maxLatitude: 10, minLongitude: 0, maxLongitude: 10).expanded(by: 0.25)
        #expect(rect.minLatitude == -2.5)
        #expect(rect.maxLongitude == 12.5)
    }

    @Test func merchantIDParsesLegacyStrings() {
        #expect(MerchantID(string: " 123 ") == MerchantID(123))
        #expect(MerchantID(string: "abc") == nil)
    }

    @Test func summaryEqualityUsesIDAndUpdatedAt() {
        func summary(_ name: String, _ t: TimeInterval) -> MerchantSummary {
            MerchantSummary(id: MerchantID(1), coordinate: Coordinate(latitude: 1, longitude: 1), name: name,
                            hasRealName: true, category: .unknown, paymentMethods: [], boostedUntil: nil,
                            openingHours: nil, updatedAt: Date(timeIntervalSince1970: t))
        }
        #expect(summary("A", 1) == summary("B", 1))
        #expect(summary("A", 1) != summary("A", 2))
    }
}
