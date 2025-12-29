import SwiftUI
import MapKit

@available(iOS 17.0, *)
struct MapPreviewView: UIViewRepresentable {
    let coordinate: CLLocationCoordinate2D
    let mapType: MKMapType
    let onCoordinateChange: (CLLocationCoordinate2D) -> Void

    private let zoomSpan = MKCoordinateSpan(latitudeDelta: 0.0012, longitudeDelta: 0.0012)

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.mapType = mapType

        // Add draggable annotation
        let annotation = DraggableAnnotation(coordinate: coordinate)
        mapView.addAnnotation(annotation)

        // Center map on location
        let region = MKCoordinateRegion(
            center: coordinate,
            span: zoomSpan
        )
        mapView.setRegion(region, animated: false)

        // Add gesture recognizer for dragging
        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        mapView.addGestureRecognizer(longPress)

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Update annotation position if coordinate changed
        if let annotation = mapView.annotations.first as? DraggableAnnotation {
            if annotation.coordinate.latitude != coordinate.latitude ||
               annotation.coordinate.longitude != coordinate.longitude {
                annotation.coordinate = coordinate
                let region = MKCoordinateRegion(
                    center: coordinate,
                    span: zoomSpan
                )
                mapView.setRegion(region, animated: true)
            }
        }
        if mapView.mapType != mapType {
            mapView.mapType = mapType
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        let parent: MapPreviewView

        init(_ parent: MapPreviewView) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard annotation is DraggableAnnotation else { return nil }

            let identifier = "DraggablePin"
            var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView

            if annotationView == nil {
                annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                annotationView?.isDraggable = true
                annotationView?.canShowCallout = false
            }
            annotationView?.annotation = annotation
            annotationView?.markerTintColor = UIColor(named: "MarkerColor") ?? .systemRed

            return annotationView
        }

        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, didChange newState: MKAnnotationView.DragState, fromOldState oldState: MKAnnotationView.DragState) {
            if newState == .ending, let annotation = view.annotation {
                parent.onCoordinateChange(annotation.coordinate)
            }
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began else { return }
            guard let mapView = gesture.view as? MKMapView else { return }

            let point = gesture.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)

            // Move existing annotation
            if let annotation = mapView.annotations.first as? DraggableAnnotation {
                annotation.coordinate = coordinate
                parent.onCoordinateChange(coordinate)
            }
        }
    }
}

// MARK: - Draggable Annotation
class DraggableAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
        super.init()
    }
}
