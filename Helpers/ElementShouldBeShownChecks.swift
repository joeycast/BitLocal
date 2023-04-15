import SwiftUI
 
// TODO: This logic seems to be slightly off. Some elements that do not accept bitcoin are showing.

// deletedAt is nil, and updatedAt is not nil: the function will return true.
// deletedAt is nil, and updatedAt is nil: the function will return true.
// deletedAt is not nil, updatedAt is not nil, and deletedAt is after or equal to updatedAt: the function will return false.
// deletedAt is not nil, updatedAt is not nil, and deletedAt is before updatedAt: the function will return true.
// deletedAt is not nil, and updatedAt is nil: the function will return false.
// No deletedAt or updatedAt are present: the function will return true.
func elementShouldBeShownAsAnnotation(element: Element) -> Bool {
    
    let dateFormatter = ISO8601DateFormatter()
    
    if ((element.osmJSON?.tags?["payment:bitcoin"] == "yes" ||
         element.osmJSON?.tags?["currency:XBT"] == "yes" ||
         element.osmJSON?.tags?["payment:onchain"] == "yes" ||
         element.osmJSON?.tags?["payment:lightning"] == "yes" ||
         element.osmJSON?.tags?["payment:lightning_contactless"] == "yes") &&
        ((element.deletedAt == nil && element.updatedAt != nil) ||
         (element.deletedAt == nil && element.updatedAt == nil) ||
         (element.deletedAt != nil && element.updatedAt != nil)) ||
        (element.deletedAt != nil && element.updatedAt != nil && {
        if let deletedDate = dateFormatter.date(from: element.deletedAt!),
           let updatedDate = dateFormatter.date(from: element.updatedAt!),
           deletedDate >= updatedDate {
            return false
        } else {
            return true
        }
    }()) ||
        (element.deletedAt != nil && element.updatedAt == nil)) {
        return true
    } else {
        return false
    }
}

