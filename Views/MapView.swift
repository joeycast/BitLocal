import SwiftUI
import MapKit

@available(iOS 16.4, *)
struct MapView: UIViewRepresentable {
    @Binding var elements: [Element]
    var topPadding: CGFloat
    var bottomPadding: CGFloat
    var mapType: MKMapType

    func makeCoordinator() -> MapCoordinator {
        MapCoordinator(self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .none
        mapView.mapType = mapType
        mapView.isRotateEnabled = false
        mapView.pointOfInterestFilter = .excludingAll
        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        // Update map type if changed
        if uiView.mapType != mapType {
            uiView.mapType = mapType
        }

        // Remove all annotations and re-add them (simplest way)
        uiView.removeAnnotations(uiView.annotations)
        let annotations = elements.compactMap { element -> Annotation? in
            guard let _ = element.mapCoordinate else { return nil }
            return Annotation(element: element)
        }
        uiView.addAnnotations(annotations)
    }

    // MARK: - MapCoordinator

    class MapCoordinator: NSObject, MKMapViewDelegate {
        var parent: MapView

        init(_ parent: MapView) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let cluster = annotation as? MKClusterAnnotation {
                return AnnotationView(annotation: cluster, reuseIdentifier: "Cluster")
            } else if let annotation = annotation as? Annotation {
                return AnnotationView(annotation: annotation, reuseIdentifier: "Annotation")
            }
            return nil
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            // Optional: Add any actions on annotation select
        }
    }
}