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
        return lhs.id == rhs.id
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

    func groupedCardListRowBackground(if shouldBeGlassy: Bool) -> some View {
        let bg: Color? = shouldBeGlassy ? nil : Color(uiColor: .secondarySystemGroupedBackground)
        return self.listRowBackground(bg)
    }

    @ViewBuilder
    func settingsSheetBackground() -> some View {
        self
    }

    @ViewBuilder
    func pagePresentationSizingIfAvailable() -> some View {
        if #available(iOS 18.0, *) {
            self.presentationSizing(.page)
        } else {
            self
        }
    }

    @ViewBuilder
    func cityPickerResultBackground(glassy: Bool) -> some View {
        if glassy {
            self
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            self
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    @ViewBuilder
    func cityPickerSearchBackground(glassy: Bool) -> some View {
        if glassy {
            self
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            self
                .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
        let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutScheme = trimmed.replacingOccurrences(
            of: #"^https?://"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        let withoutWWW = withoutScheme.replacingOccurrences(
            of: #"^www\."#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        return withoutWWW.replacingOccurrences(
            of: #"/+$"#,
            with: "",
            options: .regularExpression
        )
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

enum FeatureFlags {
    static let sharePlaceLinksKey = "share_place_links_enabled"

    static var isSharePlaceLinksEnabled: Bool {
        if UserDefaults.standard.object(forKey: sharePlaceLinksKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: sharePlaceLinksKey)
    }
}

enum AppDeepLink: Equatable {
    case place(id: String)
}

enum PlaceShareLinkBuilder {
    static let canonicalHost = "www.bitlocal.app"
    private static let allowedIDCharacters = CharacterSet.decimalDigits

    static func makeShareURL(forPlaceID placeID: String) -> URL? {
        let trimmedID = placeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidPlaceID(trimmedID) else { return nil }

        guard let encodedID = trimmedID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = canonicalHost
        components.path = "/place/\(encodedID)"
        return components.url
    }

    static func isValidPlaceID(_ placeID: String) -> Bool {
        guard !placeID.isEmpty, placeID.count <= 64 else { return false }
        return placeID.unicodeScalars.allSatisfy { allowedIDCharacters.contains($0) }
    }
}

enum DeepLinkParser {
    private static let allowedHosts: Set<String> = ["bitlocal.app", "www.bitlocal.app"]

    static func parse(url: URL) -> AppDeepLink? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              scheme == "https",
              let host = components.host?.lowercased(),
              allowedHosts.contains(host) else {
            return nil
        }

        let pathComponents = components.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        guard pathComponents.count == 2,
              pathComponents[0].lowercased() == "place" else {
            return nil
        }

        let placeID = pathComponents[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard PlaceShareLinkBuilder.isValidPlaceID(placeID) else {
            return nil
        }

        return .place(id: placeID)
    }
}

enum BTCMapMerchantURLBuilder {
    static func makeURL(for element: Element) -> URL? {
        if let merchantURL = merchantURL(forPlaceID: element.id) {
            return merchantURL
        }

        guard let coordinate = element.mapCoordinate else {
            return nil
        }

        var components = URLComponents(string: "https://btcmap.org/map")
        components?.queryItems = [
            URLQueryItem(name: "lat", value: String(coordinate.latitude)),
            URLQueryItem(name: "long", value: String(coordinate.longitude))
        ]
        return components?.url
    }

    private static func merchantURL(forPlaceID placeID: String) -> URL? {
        let trimmedID = placeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard PlaceShareLinkBuilder.isValidPlaceID(trimmedID) else {
            return nil
        }
        return URL(string: "https://btcmap.org/merchant/\(trimmedID)")
    }
}
