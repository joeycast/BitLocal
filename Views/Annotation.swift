import Foundation
import MapKit

class Annotation: NSObject, Identifiable, MKAnnotation {
    static func == (lhs: Annotation, rhs: Annotation) -> Bool {
        lhs.id == rhs.id
    }
    
    let id = UUID()
    let element: Element?
    
    var coordinate: CLLocationCoordinate2D {
        element?.mapCoordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
    }
    
    var title: String? {
        element?.osmJSON?.tags?.name
    }
    
    init(element: Element) {
        self.element = element
    }
}