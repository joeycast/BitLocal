import SwiftUI

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
