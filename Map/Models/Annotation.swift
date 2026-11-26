//
//  Annotation.swift
//  bitlocal
//
//  Created by Joe Castagnaro on 5/24/25.
//


import Foundation
import MapKit

class Annotation: NSObject, Identifiable, MKAnnotation {
    /// Stable identity for the place, not a random UUID per annotation instance.
    var id: String { element?.id ?? ObjectIdentifier(self).debugDescription }
    let element: Element?

    var coordinate: CLLocationCoordinate2D {
        element?.mapCoordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
    }

    var title: String? {
        element?.displayNameForUI
    }

    init(element: Element) {
        self.element = element
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? Annotation else { return false }
        return id == other.id
    }

    override var hash: Int {
        id.hashValue
    }
}
