import SwiftUI
import Foundation // for Debug logging
import MapKit
import CoreLocation

//@available(iOS 17.0, *)
//// Bottom Sheet
//extension View {
//    @ViewBuilder
//    func bottomSheet<Content: View>(
//        presentationDetents: Set<PresentationDetent>,
//        isPresented: Binding<Bool>,
//        dragIndicator: Visibility = .visible,
//        sheetCornerRadius: CGFloat?,
//        largestUndimmedIdentifier: UISheetPresentationController.Detent.Identifier = .medium,
//        interactiveDisabled: Bool = true,
//        // 1) Pass in a color scheme
//        forcedColorScheme: ColorScheme? = nil,
//        @ViewBuilder content: @escaping ()->Content,
//        onDismiss: @escaping()->()
//    ) -> some View {
//        self
//            .sheet(isPresented: isPresented) {
//                onDismiss()
//            } content: {
//                content()
//                // 2) Apply the color scheme if provided
//                    .preferredColorScheme(forcedColorScheme)
//                    .presentationDetents(presentationDetents)
//                    .presentationDragIndicator(dragIndicator)
//                    .interactiveDismissDisabled(interactiveDisabled)
//                    .presentationBackgroundInteraction(.enabled)
//                    .onAppear {
//                        guard let windows = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
//                            return
//                        }
//                        if let controller = windows.windows.first?.rootViewController?.presentedViewController,
//                           let sheet = controller.presentationController as? UISheetPresentationController {
//                            
//                            controller.presentedViewController?.view.tintAdjustmentMode = .normal
//                            sheet.largestUndimmedDetentIdentifier = largestUndimmedIdentifier
//                            sheet.preferredCornerRadius = sheetCornerRadius
//                        } else {
//                            Debug.log("NO CONTROLLER FOUND")
//                        }
//                    }
//            }
//    }
//}

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

@available(iOS 17.0, *)
extension View {
    @ViewBuilder
    func clearNavigationContainerBackgroundIfAvailable() -> some View {
        if #available(iOS 18.0, *) {
            self.containerBackground(.clear, for: .navigation)
        } else {
            self
        }
    }
    
    @ViewBuilder
    func clearListRowBackground(if condition: Bool) -> some View {
        if condition {
            self.listRowBackground(Color.clear)
        } else {
            self
        }
    }
}


// Website string cleaning
extension String {
    func cleanedWebsiteURL() -> URL? {
        // Remove common prefixes for display
        let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check for obvious junk data patterns
        guard !trimmed.isEmpty,
              !trimmed.contains("currency:"),  // Detect currency tag contamination
              !trimmed.contains("=yes"),       // Detect tag value contamination
              !trimmed.contains("payment:"),   // Detect payment tag contamination
              !trimmed.contains("addr:"),      // Detect address tag contamination
              trimmed.count < 200,             // Reasonable URL length limit
              !trimmed.contains("\n"),         // No line breaks
              !trimmed.contains("\t")          // No tabs
        else {
            Debug.log("Rejected junk URL: '\(trimmed)'")
            return nil
        }
        
        // Clean up the URL
        var cleanURL = trimmed
        
        // Remove multiple protocols if they exist
        cleanURL = cleanURL.replacingOccurrences(of: "https://http://", with: "https://")
        cleanURL = cleanURL.replacingOccurrences(of: "http://https://", with: "https://")
        
        // Try to create URL as-is first
        if let url = URL(string: cleanURL), url.scheme != nil {
            return url
        }
        
        // If no protocol, add https://
        if !cleanURL.hasPrefix("http://") && !cleanURL.hasPrefix("https://") {
            cleanURL = "https://\(cleanURL)"
        }
        
        // Final attempt
        if let url = URL(string: cleanURL), url.scheme != nil {
            return url
        }
        
        Debug.log("Could not create valid URL from: '\(trimmed)'")
        return nil
    }
    
    func cleanedForDisplay() -> String {
        return self
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "www.", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}


// Simplified international phone number handling
extension String {
    func cleanedPhoneNumber() -> (cleaned: String, isValid: Bool) {
        // Just remove whitespace and common separators for tel: links
        let cleaned = self.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: ".", with: "")
        
        let isValid = isValidPhoneNumber(cleaned)
        return (cleaned, isValid)
    }
    
    private func isValidPhoneNumber(_ phone: String) -> Bool {
        // Minimal validation - just reject obvious junk
        guard !phone.isEmpty,
              phone.count >= 4,  // Minimum reasonable length
              phone.count <= 20, // Maximum reasonable length
              
              // Reject obvious junk data patterns
              !phone.contains("currency:"),
              !phone.contains("=yes"),
              !phone.contains("http"),
              !phone.contains("@"),
              !phone.contains("www.")
        else {
            return false
        }
        
        // Must be mostly digits (allow + for country codes)
        let validChars = phone.filter({ $0.isNumber || $0 == "+" }).count
        let totalChars = phone.count
        
        // At least 70% should be digits or +
        guard validChars * 10 >= totalChars * 7 else { // 70% = 7/10
            return false
        }
        
        // Must contain at least 4 digits
        let digitCount = phone.filter { $0.isNumber }.count
        return digitCount >= 4
    }
    
    // Don't format - just clean up obvious issues
    func displayablePhoneNumber() -> String {
        let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Only clean up obvious formatting issues, preserve everything else
        guard !trimmed.isEmpty else { return self }
        
        // Remove excessive whitespace but preserve intentional formatting
        let cleaned = trimmed.replacingOccurrences(of: "  +", with: " ")
                           .replacingOccurrences(of: "+ ", with: "+")
        
        return cleaned
    }
}
