import SwiftUI

// If on chain, lightning and contactless are missing or no and payment:bitcoin or currency:XBT = yes, Accepts Bitcoin = true
func acceptsBitcoin(element: Element) -> Bool {
    if ((element.osmJSON?.tags?["payment:bitcoin"] == "yes") || 
        (element.osmJSON?.tags?["currency:XBT"] == "yes")) && 
        ((element.osmJSON?.tags?["payment:onchain"] == nil) &&
        (element.osmJSON?.tags?["payment:lightning"] == nil) &&
        (element.osmJSON?.tags?["payment:lightning_contactless"] == nil)) {
        return true
    } else {
        return false
    }
}

func acceptsBitcoinOnChain(element: Element) -> Bool {
    if element.osmJSON?.tags?["payment:onchain"] == "yes" {
        return true
    } else {
        return false
    }
}

func acceptsLightning(element: Element) -> Bool {
    if element.osmJSON?.tags?["payment:lightning"] == "yes" {
        return true
    } else {
        return false
    }
}

func acceptsContactlessLightning(element: Element) -> Bool {
    if element.osmJSON?.tags?["payment:lightning_contactless"] == "yes" {
        return true
    } else {
        return false
    }
}
