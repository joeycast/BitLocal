import SwiftUI

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
    if let osmTags = element.osmJSON?.tags, osmTags.paymentLightning == "yes" {
        return true
    }
    return false
}

func acceptsContactlessLightning(element: Element) -> Bool {
    if let osmTags = element.osmJSON?.tags, osmTags.paymentLightningContactless == "yes" {
        return true
    }
    return false
}
