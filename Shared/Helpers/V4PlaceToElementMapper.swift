import Foundation

struct V4PlaceToElementMapper {
    static func snapshotRecordToElement(_ record: V4PlaceSnapshotRecord, fallbackTimestamp: String) -> Element {
        // Prefer a real name when the CDN snapshot includes one; otherwise keep the
        // stable placeholder so incremental backfill / place hydration can still find it.
        // UI display falls back to a category label via `Element.displayNameForUI`
        // (not `displayName`, which feeds search scoring).
        let placeholderName = "BTC Map Place #\(record.id)"
        let resolvedName = record.preferredName ?? placeholderName
        let osmTags = makeOsmTags(
            name: resolvedName,
            operatorName: nil,
            brandName: nil,
            brandWikidata: nil,
            categoryIcon: record.icon,
            description: nil,
            website: nil,
            phone: nil,
            openingHours: nil,
            paymentBitcoin: nil,
            currencyXBT: nil,
            paymentOnchain: nil,
            paymentLightning: nil,
            paymentLightningContactless: nil,
            addrHousenumber: nil,
            addrStreet: nil,
            addrCity: nil,
            addrState: nil,
            addrPostcode: nil
        )
        let osmJSON = OsmJSON(
            changeset: nil,
            id: nil,
            lat: record.lat,
            lon: record.lon,
            tags: osmTags,
            timestamp: fallbackTimestamp,
            type: .node,
            uid: nil,
            user: nil,
            version: nil,
            bounds: nil,
            geometry: nil,
            nodes: nil,
            members: nil
        )
        return Element(
            id: String(record.id),
            osmJSON: osmJSON,
            tags: Tags(
                category: nil,
                iconPlatform: record.icon,
                paymentCoinos: nil,
                paymentPouch: nil,
                boostExpires: record.boostedUntil,
                categoryPlural: nil,
                paymentProvider: nil,
                paymentURI: nil
            ),
            createdAt: fallbackTimestamp,
            updatedAt: fallbackTimestamp,
            deletedAt: nil,
            address: nil,
            v4Metadata: ElementV4Metadata(
                icon: record.icon,
                commentsCount: record.comments,
                verifiedAt: nil,
                boostedUntil: record.boostedUntil,
                osmID: nil,
                osmURL: nil,
                email: nil,
                twitter: nil,
                facebook: nil,
                instagram: nil,
                telegram: nil,
                line: nil,
                requiredAppURL: nil,
                imageURL: nil,
                paymentProvider: nil,
                rawAddress: nil
            )
        )
    }

    static func placeRecordToElement(_ record: V4PlaceRecord) -> Element {
        let createdAt = record.createdAt ?? record.updatedAt ?? BTCMapRepository.epochISO8601
        let updatedAt = record.updatedAt ?? createdAt
        let osmTags = makeOsmTags(
            name: record.preferredName ?? "BTC Map Place #\(record.id)",
            operatorName: record.osmOperator,
            brandName: record.osmBrand,
            brandWikidata: record.osmBrandWikidata,
            categoryIcon: record.icon,
            description: record.description,
            website: record.website,
            phone: record.phone,
            openingHours: record.openingHours,
            paymentBitcoin: record.osmPaymentBitcoin,
            currencyXBT: record.osmCurrencyXBT,
            paymentOnchain: record.osmPaymentOnchain,
            paymentLightning: record.osmPaymentLightning,
            paymentLightningContactless: record.osmPaymentLightningContactless,
            addrHousenumber: record.osmAddrHouseNumber,
            addrStreet: record.osmAddrStreet ?? record.address,
            addrCity: record.osmAddrCity,
            addrState: record.osmAddrState,
            addrPostcode: record.osmAddrPostcode
        )
        let osmJSON = OsmJSON(
            changeset: nil,
            id: nil,
            lat: record.lat,
            lon: record.lon,
            tags: osmTags,
            timestamp: updatedAt,
            type: .node,
            uid: nil,
            user: nil,
            version: nil,
            bounds: nil,
            geometry: nil,
            nodes: nil,
            members: nil
        )

        let address: Address?
        if record.osmAddrStreet != nil || record.osmAddrCity != nil || record.osmAddrState != nil || record.osmAddrPostcode != nil {
            address = Address(
                streetNumber: record.osmAddrHouseNumber,
                streetName: record.osmAddrStreet,
                cityOrTownName: record.osmAddrCity,
                postalCode: Address.normalizedPostalCode(record.osmAddrPostcode, countryName: nil),
                regionOrStateName: record.osmAddrState,
                countryName: nil
            )
        } else if let raw = record.address, !raw.isEmpty {
            address = Address(
                streetNumber: nil,
                streetName: raw,
                cityOrTownName: nil,
                postalCode: nil,
                regionOrStateName: nil,
                countryName: nil
            )
        } else {
            address = nil
        }

        let tags = Tags(
            category: nil,
            iconPlatform: record.icon,
            paymentCoinos: nil,
            paymentPouch: nil,
            boostExpires: record.boostedUntil,
            categoryPlural: nil,
            paymentProvider: record.paymentProvider,
            paymentURI: nil
        )

        let metadata = ElementV4Metadata(
            icon: record.icon,
            commentsCount: record.comments,
            verifiedAt: record.verifiedAt,
            boostedUntil: record.boostedUntil,
            osmID: record.osmID,
            osmURL: record.osmURL,
            email: record.email,
            twitter: record.twitter,
            facebook: record.facebook,
            instagram: record.instagram,
            telegram: record.telegram,
            line: record.line,
            requiredAppURL: record.requiredAppURL,
            imageURL: record.image,
            paymentProvider: record.paymentProvider,
            rawAddress: record.address
        )

        return Element(
            id: String(record.id),
            osmJSON: osmJSON,
            tags: tags,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: record.deletedAt,
            address: address,
            v4Metadata: metadata
        )
    }

    private static func makeOsmTags(
        name: String?,
        operatorName: String?,
        brandName: String?,
        brandWikidata: String?,
        categoryIcon: String?,
        description: String?,
        website: String?,
        phone: String?,
        openingHours: String?,
        paymentBitcoin: String?,
        currencyXBT: String?,
        paymentOnchain: String?,
        paymentLightning: String?,
        paymentLightningContactless: String?,
        addrHousenumber: String?,
        addrStreet: String?,
        addrCity: String?,
        addrState: String?,
        addrPostcode: String?
    ) -> OsmTags {
        let categoryAssignment = ElementCategorySymbols.osmTagAssignment(forCategoryIcon: categoryIcon)

        return OsmTags(
            addrCity: addrCity,
            addrHousenumber: addrHousenumber,
            addrPostcode: addrPostcode,
            addrState: addrState,
            addrStreet: addrStreet,
            paymentBitcoin: paymentBitcoin,
            currencyXBT: currencyXBT,
            paymentOnchain: paymentOnchain,
            paymentLightning: paymentLightning,
            paymentLightningContactless: paymentLightningContactless,
            name: name,
            operator: operatorName,
            brand: brandName,
            brandWikidata: brandWikidata,
            description: description,
            descriptionEn: nil,
            website: website,
            contactWebsite: nil,
            phone: phone,
            contactPhone: nil,
            openingHours: openingHours,
            cuisine: value(forTagKey: "cuisine", assignment: categoryAssignment),
            shop: value(forTagKey: "shop", assignment: categoryAssignment),
            sport: value(forTagKey: "sport", assignment: categoryAssignment),
            tourism: value(forTagKey: "tourism", assignment: categoryAssignment),
            healthcare: value(forTagKey: "healthcare", assignment: categoryAssignment),
            craft: value(forTagKey: "craft", assignment: categoryAssignment),
            amenity: value(forTagKey: "amenity", assignment: categoryAssignment),
            place: value(forTagKey: "place", assignment: categoryAssignment),
            leisure: value(forTagKey: "leisure", assignment: categoryAssignment),
            office: value(forTagKey: "office", assignment: categoryAssignment),
            building: value(forTagKey: "building", assignment: categoryAssignment),
            company: value(forTagKey: "company", assignment: categoryAssignment)
        )
    }

    private static func value(
        forTagKey key: String,
        assignment: (tagKey: String, tagValue: String)?
    ) -> String? {
        guard assignment?.tagKey == key else { return nil }
        return assignment?.tagValue
    }
}
