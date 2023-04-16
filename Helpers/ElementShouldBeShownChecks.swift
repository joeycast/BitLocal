import SwiftUI

// If any accepts any form of bitcoin, perform deletedAt and updatedAt checks.
    // If deletedAt is nil, updatedAt is not nil: return true. 
    // If deletedAt is nil, updatedAt is nil: return true.
    // If deletedAt is not nil, updatedAt is not nil, perform deletedAt/updatedAt comparison.
        // If deletedAt is greater than or equal to updatedAt: return false.
        // If deletedAt is less than updatedAt: return true.
    // If deletedAt is not nil, updatedAt is nil: return false.
// If none of payment:bitcoin, currency:XBT, payment:onchain, payment:lightning, payment:lightning_contactless are "yes": return false.
func elementShouldBeShownAsAnnotation(element: Element) -> Bool {
    
    let dateFormatter = ISO8601DateFormatter()
    
    if acceptsBitcoin(element: element) || acceptsBitcoinOnChain(element: element) || acceptsLightning(element: element) || acceptsContactlessLightning(element: element) {
        
        if let deletedAt = element.deletedAt, let updatedAt = element.updatedAt {
            if let deletedDate = dateFormatter.date(from: deletedAt), let updatedDate = dateFormatter.date(from: updatedAt) {
                return updatedDate > deletedDate
            }
        } else if element.deletedAt == nil && element.updatedAt != nil {
            return true
        } else if element.deletedAt == nil && element.updatedAt == nil {
            return true
        } else if element.deletedAt != nil && element.updatedAt == nil {
            return false
        }
    }
    return false
}
