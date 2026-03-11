import XCTest
@testable import bitlocal

final class MerchantStoreTests: XCTestCase {
    private var temporaryDirectoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        temporaryDirectoryURL = nil
        try super.tearDownWithError()
    }

    func testUpsertAndLoadRoundTripPreservesStructuredAddress() {
        let store = makeStore()
        let element = V4PlaceToElementMapper.placeRecordToElement(
            Self.placeRecord(
                id: 101,
                name: "Cafe Test",
                houseNumber: "12",
                street: "Main Street",
                city: "Nashville",
                state: "TN",
                postcode: "37203",
                country: "US"
            )
        )

        store.upsert(element)

        let loaded = store.loadElements()

        XCTAssertEqual(loaded?.count, 1)
        XCTAssertEqual(loaded?.first?.id, "101")
        XCTAssertEqual(loaded?.first?.address?.streetNumber, "12")
        XCTAssertEqual(loaded?.first?.address?.streetName, "Main Street")
        XCTAssertEqual(loaded?.first?.address?.cityOrTownName, "Nashville")
        XCTAssertEqual(loaded?.first?.address?.postalCode, "37203")
        XCTAssertEqual(loaded?.first?.address?.countryCode, "US")
    }

    func testPersistMergedAddressFillsOnlyMissingFields() {
        let store = makeStore()
        let sourceElement = V4PlaceToElementMapper.placeRecordToElement(
            Self.placeRecord(
                id: 202,
                name: "Partial Place",
                houseNumber: "5",
                street: "Lenox Avenue",
                city: "Miami Beach",
                state: "FL",
                postcode: nil,
                country: nil
            )
        )

        store.upsert(sourceElement)

        let persisted = store.persistMergedAddress(
            Address(
                streetNumber: "999",
                streetName: "Wrong Street",
                cityOrTownName: "Miami Beach",
                postalCode: "33139",
                regionOrStateName: "FL",
                countryName: "United States",
                countryCode: "US"
            ),
            forMerchantID: "202"
        )

        XCTAssertEqual(persisted?.address?.streetNumber, "5")
        XCTAssertEqual(persisted?.address?.streetName, "Lenox Avenue")
        XCTAssertEqual(persisted?.address?.postalCode, "33139")
        XCTAssertEqual(persisted?.address?.countryCode, "US")
    }

    func testLoadElementsByIDPreservesRequestedOrder() {
        let store = makeStore()
        store.upsert([
            V4PlaceToElementMapper.placeRecordToElement(Self.placeRecord(id: 1, name: "One")),
            V4PlaceToElementMapper.placeRecordToElement(Self.placeRecord(id: 2, name: "Two")),
            V4PlaceToElementMapper.placeRecordToElement(Self.placeRecord(id: 3, name: "Three"))
        ])

        let loaded = store.loadElements(ids: ["3", "1"])

        XCTAssertEqual(loaded.map(\.id), ["3", "1"])
    }

    func testSyncStateRoundTripsBundledMetadata() {
        let store = makeStore()
        let syncState = V4SyncState(
            snapshotLastModifiedRFC1123: "Mon, 10 Mar 2026 10:00:00 GMT",
            incrementalAnchorUpdatedSince: "2026-03-10T10:00:00Z",
            lastSuccessfulSyncAt: "2026-03-10T12:00:00Z",
            bundledGeneratedAt: "2026-03-10T09:00:00Z",
            bundledSourceAnchor: "2026-03-10T08:00:00Z",
            schemaVersion: V4SyncState.currentSchemaVersion
        )

        store.saveSyncState(syncState)

        XCTAssertEqual(store.loadSyncState(), syncState)
    }

    private func makeStore() -> MerchantStore {
        MerchantStore(
            fileManager: .default,
            bundle: Bundle(for: Self.self),
            writableDatabaseURL: temporaryDirectoryURL.appendingPathComponent("Merchants.sqlite"),
            bundledDatabaseURL: nil,
            legacyElementsURL: nil,
            legacySyncStateURL: nil
        )
    }

    private static func placeRecord(
        id: Int,
        name: String,
        houseNumber: String? = nil,
        street: String? = nil,
        city: String? = nil,
        state: String? = nil,
        postcode: String? = nil,
        country: String? = nil
    ) -> V4PlaceRecord {
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
            osmAddrHouseNumber: houseNumber,
            osmAddrStreet: street,
            osmAddrCity: city,
            osmAddrCountry: country,
            osmAddrState: state,
            osmAddrPostcode: postcode,
            osmOperator: nil,
            osmBrand: name,
            osmBrandWikidata: nil
        )
    }
}
