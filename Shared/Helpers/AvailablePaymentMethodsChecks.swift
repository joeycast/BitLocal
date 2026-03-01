import SwiftUI

private let lightningOnlyBrandWikidataIDs: Set<String> = [
    "q7605233", // Steak 'n Shake
]

private let lightningOnlyBrandNames: Set<String> = [
    "steak 'n shake",
    "steak n shake",
]

private func hasNonEmptyValue(_ value: String?) -> Bool {
    guard let value else { return false }
    return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

private func hasExplicitPaymentMethodTags(_ tags: OsmTags) -> Bool {
    hasNonEmptyValue(tags.paymentBitcoin) ||
    hasNonEmptyValue(tags.currencyXBT) ||
    hasNonEmptyValue(tags.paymentOnchain) ||
    hasNonEmptyValue(tags.paymentLightning) ||
    hasNonEmptyValue(tags.paymentLightningContactless)
}

private func infersLightningOnlyByBrand(_ tags: OsmTags) -> Bool {
    guard !hasExplicitPaymentMethodTags(tags) else {
        return false
    }
    let wikidata = (tags.brandWikidata ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if lightningOnlyBrandWikidataIDs.contains(wikidata) {
        return true
    }
    let brand = (tags.brand ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return lightningOnlyBrandNames.contains(brand)
}

func acceptsBitcoin(element: Element) -> Bool {
    if let osmTags = element.osmJSON?.tags {
        if ((osmTags.paymentBitcoin == "yes") || (osmTags.currencyXBT == "yes")) &&
            (osmTags.paymentOnchain == nil) &&
            (osmTags.paymentLightning == nil) &&
            (osmTags.paymentLightningContactless == nil) {
            return true
        }
    }
    return false
}

func acceptsBitcoinOnChain(element: Element) -> Bool {
    if let osmTags = element.osmJSON?.tags, osmTags.paymentOnchain == "yes" {
        return true
    }
    return false
}

func acceptsLightning(element: Element) -> Bool {
    if let osmTags = element.osmJSON?.tags {
        if osmTags.paymentLightning == "yes" {
            return true
        }
        if infersLightningOnlyByBrand(osmTags) {
            return true
        }
    }
    return false
}

func acceptsContactlessLightning(element: Element) -> Bool {
    if let osmTags = element.osmJSON?.tags, osmTags.paymentLightningContactless == "yes" {
        return true
    }
    return false
}
