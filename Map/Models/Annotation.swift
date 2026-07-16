//
//  Annotation.swift
//  bitlocal
//
//  Created by Joe Castagnaro on 5/24/25.
//


import Foundation
import MapKit

class Annotation: NSObject, Identifiable, MKAnnotation {
    static func == (lhs: Annotation, rhs: Annotation) -> Bool {
        lhs.id == rhs.id
    }

    /// Stable identity for the place, not a random UUID per annotation instance.
    var id: String { element?.id ?? ObjectIdentifier(self).debugDescription }
    let element: Element?

    var coordinate: CLLocationCoordinate2D {
        element?.mapCoordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
    }

    var title: String? {
        element?.displayName
    }

    init(element: Element) {
        self.element = element
    }
}
