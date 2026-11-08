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
