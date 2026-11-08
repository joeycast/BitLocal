//
//  ElementMerchantAdapter.swift
//  bitlocal
//
//  Redesign phase 1 bridge: lets existing views and models read the new
//  BitLocalKit domain types while `Element` is still the app's merchant model.
//  Deleted in phase 8 together with `Element`.
//

import Foundation
import BitLocalDomain

extension MerchantMapper {
    /// The app's mapper: unnamed merchants fall back to the localized category label.
    static let app = MerchantMapper(categoryName: { category in
        ElementCategorySymbols.friendlyCategoryLabel(forIcon: category.rawValue)
            ?? String(localized: "Place")
    })
}

extension Element {
    /// The merchant's id in the new domain model, if the legacy string id is numeric.
    var merchantID: MerchantID? { MerchantID(string: id) }

    var merchantCoordinate: Coordinate? {
        guard let lat = osmJSON?.lat, let lon = osmJSON?.lon else { return nil }
        let coordinate = Coordinate(latitude: lat, longitude: lon)
        return coordinate.isValid ? coordinate : nil
    }

    var merchantPaymentMethods: PaymentMethods {
        let tags = osmJSON?.tags
        return PaymentMethods(
            paymentBitcoin: tags?.paymentBitcoin,
            currencyXBT: tags?.currencyXBT,
            paymentOnchain: tags?.paymentOnchain,
            paymentLightning: tags?.paymentLightning,
            paymentLightningContactless: tags?.paymentLightningContactless,
            brand: tags?.brand,
            brandWikidata: tags?.brandWikidata
        )
    }

    /// The light domain shape for map, list and card. Nil for merchants without a usable id or location.
    var merchantSummary: MerchantSummary? {
        guard let merchantID, let merchantCoordinate else { return nil }
        let category = MerchantCategory(icon: v4Metadata?.icon ?? tags?.iconPlatform)
        let realName = displayName
        return MerchantSummary(
            id: merchantID,
            coordinate: merchantCoordinate,
            name: realName ?? MerchantMapper.app.categoryName(category),
            hasRealName: realName != nil,
            category: category,
            paymentMethods: merchantPaymentMethods,
            boostedUntil: boostExpirationDate,
            openingHours: osmJSON?.tags?.openingHours,
            updatedAt: BTCMapDateParser.parse(updatedAt) ?? BTCMapDateParser.parse(createdAt) ?? .distantPast
        )
    }
}

extension Element {
    /// The full domain shape, used to import the legacy JSON cache into the SQLite store.
    /// Snapshot-only rows (placeholder names) import as not hydrated so the store fetches them later.
    var merchant: Merchant? {
        guard let summary = merchantSummary else { return nil }
        let tags = osmJSON?.tags
        let metadata = v4Metadata
        let postal = PostalAddress(
            houseNumber: address?.streetNumber,
            street: address?.streetName,
            city: address?.cityOrTownName,
            state: address?.regionOrStateName,
            postalCode: address?.postalCode,
            freeform: metadata?.rawAddress
        )
        var socials: [SocialLink] = []
        var place = BTCMapPlace(id: summary.id.rawValue)
        place.twitter = metadata?.twitter
        place.facebook = metadata?.facebook
        place.instagram = metadata?.instagram
        place.telegram = metadata?.telegram
        place.line = metadata?.line
        place.lat = summary.coordinate.latitude
        place.lon = summary.coordinate.longitude
        if let mapped = MerchantMapper.app.merchant(from: place) {
            socials = mapped.socials
        }
        return Merchant(
            summary: summary,
            address: postal.isEmpty ? nil : postal,
            contact: Contact(
                phone: tags?.phone ?? tags?.contactPhone,
                website: MerchantMapper.webURL(tags?.website ?? tags?.contactWebsite),
                email: metadata?.email
            ),
            socials: socials,
            about: tags?.description ?? tags?.descriptionEn,
            imageURL: MerchantMapper.webURL(metadata?.imageURL),
            requiredAppURL: MerchantMapper.webURL(metadata?.requiredAppURL),
            verifiedAt: BTCMapDateParser.parse(metadata?.verifiedAt),
            commentsCount: metadata?.commentsCount ?? 0,
            osmURL: MerchantMapper.webURL(metadata?.osmURL),
            isHydrated: summary.hasRealName || !(tags?.name.map(Element.isPlaceholderName) ?? true)
        )
    }
}

/// Searchable words for a category: its localized group labels, aliases and tag values.
/// Cached per icon because the catalog lookup is not free and runs for every imported row.
final class CategorySearchTerms: @unchecked Sendable {
    static let shared = CategorySearchTerms()

    private let lock = NSLock()
    private var cache: [String: String] = [:]

    func terms(for category: MerchantCategory) -> String {
        lock.lock()
        if let cached = cache[category.rawValue] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        var words: [String] = []
        if let label = ElementCategorySymbols.friendlyCategoryLabel(forIcon: category.rawValue) {
            words.append(label)
        }
        for group in ElementCategorySymbols.merchantCategoryGroups(forCategoryIcon: category.rawValue) {
            words += ElementCategorySymbols.searchTerms(for: group)
        }
        words.append(category.rawValue.replacingOccurrences(of: "_", with: " "))
        var seen = Set<String>()
        let joined = words.filter { seen.insert($0.lowercased()).inserted }.joined(separator: " ")

        lock.lock()
        cache[category.rawValue] = joined
        lock.unlock()
        return joined
    }
}
