import SwiftUI
import MapKit

@available(iOS 16.4, *)
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
        @ViewBuilder content: @escaping ()->Content,
        onDismiss: @escaping()->()
    )-> some View {
        self
            .sheet(isPresented: isPresented) {                
                onDismiss()
            } content: {
                content()
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
                            
                            // Ensures About sheet button does not inadvertently change to dimmed 
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
