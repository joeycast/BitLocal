import SwiftUI
import MapKit
import CoreLocation

@available(iOS 17.0, *)
// Bottom Sheet
extension View {
    @ViewBuilder
    func bottomSheet<Content: View>(
        presentationDetents: Set<PresentationDetent>,
        isPresented: Binding<Bool>,
        dragIndicator: Visibility = .visible,
        sheetCornerRadius: CGFloat?,
        largestUndimmedIdentifier: UISheetPresentationController.Detent.Identifier = .medium,
        interactiveDisabled: Bool = true,
        // 1) Pass in a color scheme
        forcedColorScheme: ColorScheme? = nil,
        @ViewBuilder content: @escaping ()->Content,
        onDismiss: @escaping()->()
    ) -> some View {
        self
            .sheet(isPresented: isPresented) {
                onDismiss()
            } content: {
                content()
                // 2) Apply the color scheme if provided
                    .preferredColorScheme(forcedColorScheme)
                    .presentationDetents(presentationDetents)
                    .presentationDragIndicator(dragIndicator)
                    .interactiveDismissDisabled(interactiveDisabled)
                    .presentationBackgroundInteraction(.enabled)
                    .onAppear {
                        guard let windows = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
                            return
                        }
                        if let controller = windows.windows.first?.rootViewController?.presentedViewController,
                           let sheet = controller.presentationController as? UISheetPresentationController {
                            
                            controller.presentedViewController?.view.tintAdjustmentMode = .normal
                            sheet.largestUndimmedDetentIdentifier = largestUndimmedIdentifier
                            sheet.preferredCornerRadius = sheetCornerRadius
                        } else {
                            print("NO CONTROLLER FOUND")
                        }
                    }
            }
    }
}

//
extension CLLocationCoordinate2D: Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        return lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}


//
extension MKCoordinateRegion: Equatable {
    public static func == (lhs: MKCoordinateRegion, rhs: MKCoordinateRegion) -> Bool {
        return lhs.center == rhs.center &&
        lhs.span.latitudeDelta == rhs.span.latitudeDelta &&
        lhs.span.longitudeDelta == rhs.span.longitudeDelta
    }
}

// Determine topmost view for displaying alerts
extension UIViewController {
    func topMostViewController() -> UIViewController {
        if let presented = self.presentedViewController {
            return presented.topMostViewController()
        }
        if let nav = self as? UINavigationController {
            return nav.visibleViewController?.topMostViewController() ?? self
        }
        if let tab = self as? UITabBarController {
            return tab.selectedViewController?.topMostViewController() ?? self
        }
        return self
    }
}

extension Element: Equatable {
    static func == (lhs: Element, rhs: Element) -> Bool {
        return lhs.uuid == rhs.uuid // Assuming 'uuid' is a unique identifier for each Element
    }
}

extension UserDefaults {
    func setElements(_ elements: [Element], forKey key: String) {
        if let encoded = try? JSONEncoder().encode(elements) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
    
    func getElements(forKey key: String) -> [Element]? {
        if let data = UserDefaults.standard.data(forKey: key),
           let elements = try? JSONDecoder().decode([Element].self, from: data) {
            return elements
        }
        return nil
    }
}

@available(iOS 17.0, *)
extension MKCoordinateRegion {
    var mapRect: MKMapRect {
        let topLeft = CLLocationCoordinate2D(
            latitude: center.latitude + (span.latitudeDelta / 2),
            longitude: center.longitude - (span.longitudeDelta / 2)
        )
        let bottomRight = CLLocationCoordinate2D(
            latitude: center.latitude - (span.latitudeDelta / 2),
            longitude: center.longitude + (span.longitudeDelta / 2)
        )
        
        let topLeftPoint = MKMapPoint(topLeft)
        let bottomRightPoint = MKMapPoint(bottomRight)
        
        return MKMapRect(
            x: min(topLeftPoint.x, bottomRightPoint.x),
            y: min(topLeftPoint.y, bottomRightPoint.y),
            width: abs(topLeftPoint.x - bottomRightPoint.x),
            height: abs(topLeftPoint.y - bottomRightPoint.y)
        )
    }
}

extension MKMapType {
    var intValue: Int {
        return Int(self.rawValue)
    }
    
    static func from(int: Int) -> MKMapType {
        return MKMapType(rawValue: UInt(int)) ?? .standard
    }
}

extension Element {
    /// Returns a coordinate for node or way (first geometry point), or nil if unavailable
    var mapCoordinate: CLLocationCoordinate2D? {
        // For node
        if let lat = osmJSON?.lat, let lon = osmJSON?.lon {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        // For way: use first geometry point, but make sure lat/lon are not nil
        if let geometry = osmJSON?.geometry, let first = geometry.first,
           let lat = first.lat, let lon = first.lon {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        return nil
    }
}

extension Image {
    func aboutIconStyle(size: CGFloat, color: Color = .accentColor) -> some View {
        self
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .foregroundColor(color)
    }
}
