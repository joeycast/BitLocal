import SwiftUI
import Synchronization
import UIKit
import Foundation // for Debug logging
import MapKit
import CoreLocation

// MARK: - Safe ID indexing

enum IdentifiableIndex {
    /// Builds an id→value dictionary without trapping on duplicate IDs.
    /// Default policy keeps the later value (last wins).
    static func byID<T: Identifiable>(
        _ items: [T],
        uniquingKeysWith combine: (T, T) -> T = { _, new in new }
    ) -> [T.ID: T] where T.ID: Hashable {
        Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: combine)
    }

    /// Same as `byID` for arbitrary Hashable keys (e.g. string IDs that are not `Identifiable.id`).
    static func dictionary<Key: Hashable, Value>(
        _ pairs: [(Key, Value)],
        uniquingKeysWith combine: (Value, Value) -> Value = { _, new in new }
    ) -> [Key: Value] {
        Dictionary(pairs, uniquingKeysWith: combine)
    }
}

// Bottom Sheet
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

// Element identity is place id (Equatable + Hashable). Hash is defined on Element;
// equality lives here to keep the model file focused on decoding.
extension Element {
    static func == (lhs: Element, rhs: Element) -> Bool {
        lhs.id == rhs.id
    }
}

extension UserDefaults {
    func setElements(_ elements: [Element], forKey key: String) {
        if let encoded = try? JSONEncoder().encode(elements) {
            self.set(encoded, forKey: key)
        }
    }
    
    func getElements(forKey key: String) -> [Element]? {
        if let data = self.data(forKey: key),
           let elements = try? JSONDecoder().decode([Element].self, from: data) {
            return elements
        }
        return nil
    }
}

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
            .foregroundStyle(color)
    }
}

extension View {
    @ViewBuilder
    func clearNavigationContainerBackgroundIfAvailable() -> some View {
        self.containerBackground(.clear, for: .navigation)
    }

    @ViewBuilder
    func bitLocalDetailNavigationChrome() -> some View {
        self
            .toolbarVisibility(.visible, for: .navigationBar)
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
            .toolbar(removing: .sidebarToggle)
            .clearNavigationContainerBackgroundIfAvailable()
            .tint(.accentColor)
    }
    
    func clearListRowBackground(if condition: Bool) -> some View {
        self.listRowBackground(condition ? Color.clear : nil)
    }

    @ViewBuilder
    func groupedCardListRowBackground(if shouldBeGlassy: Bool) -> some View {
        self
    }

    @ViewBuilder
    func settingsSheetBackground() -> some View {
        self
    }

    @ViewBuilder
    func pagePresentationSizingIfAvailable() -> some View {
        self.presentationSizing(.page)
    }

    func cityPickerResultBackground(glassy: Bool) -> some View {
        self.background(
            glassy ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground)),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }

    func cityPickerSearchBackground(glassy: Bool) -> some View {
        self.background(
            glassy ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(Color(uiColor: .tertiarySystemFill)),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }
}


// Website string cleaning
extension String {
    private static let insecureProtocolPrefix = "http" + "://"
    private static let secureProtocolPrefix = "https" + "://"

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
        let duplicatedSecurePrefix = Self.secureProtocolPrefix + Self.insecureProtocolPrefix
        let duplicatedInsecurePrefix = Self.insecureProtocolPrefix + Self.secureProtocolPrefix
        cleanURL = cleanURL.replacing(duplicatedSecurePrefix, with: Self.secureProtocolPrefix)
        cleanURL = cleanURL.replacing(duplicatedInsecurePrefix, with: Self.secureProtocolPrefix)
        
        // Try to create URL as-is first
        if let url = URL(string: cleanURL), url.scheme != nil {
            return url
        }
        
        // If no protocol, add https://
        if !cleanURL.hasPrefix(Self.insecureProtocolPrefix) && !cleanURL.hasPrefix(Self.secureProtocolPrefix) {
            cleanURL = Self.secureProtocolPrefix + cleanURL
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
        let withoutScheme = trimmed.replacing(#/^https?:\/\//#.ignoresCase(), with: "")
        let withoutWWW = withoutScheme.replacing(#/^www\./#.ignoresCase(), with: "")
        return withoutWWW.replacing(#/\/+$/#, with: "")
    }
}


// Simplified international phone number handling
extension String {
    func cleanedPhoneNumber() -> (cleaned: String, isValid: Bool) {
        // Just remove whitespace and common separators for tel: links
        let cleaned = self.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacing(" ", with: "")
            .replacing("-", with: "")
            .replacing("(", with: "")
            .replacing(")", with: "")
            .replacing(".", with: "")
        
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
        let validChars = phone.count(where: { $0.isNumber || $0 == "+" })
        let totalChars = phone.count
        
        // At least 70% should be digits or +
        guard validChars * 10 >= totalChars * 7 else { // 70% = 7/10
            return false
        }
        
        // Must contain at least 4 digits
        let digitCount = phone.count(where: \.isNumber)
        return digitCount >= 4
    }
    
    // Don't format - just clean up obvious issues
    func displayablePhoneNumber() -> String {
        let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Only clean up obvious formatting issues, preserve everything else
        guard !trimmed.isEmpty else { return self }
        
        // Remove excessive whitespace but preserve intentional formatting
        let cleaned = trimmed.replacing(#/ {2,}/#, with: " ")
            .replacing("+ ", with: "+")
        
        return cleaned
    }
}

enum FeatureFlags {
    static let sharePlaceLinksKey = "share_place_links_enabled"
    static let featureHintsKey = "feature_hints_enabled"

    /// Events discovery UI and network fetch. Off until the product is ready.
    /// Keep `EventsDiscoverySection`, `AllEventsListView`, and v4 events API code for later.
    static let isEventsUIEnabled = false

    static var isSharePlaceLinksEnabled: Bool {
        if UserDefaults.standard.object(forKey: sharePlaceLinksKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: sharePlaceLinksKey)
    }

    static var isFeatureHintsEnabled: Bool {
        if UserDefaults.standard.object(forKey: featureHintsKey) == nil {
            return false
        }
        return UserDefaults.standard.bool(forKey: featureHintsKey)
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

// MARK: - Design-Engineering Motion, Tactile Press & Layout Primitives

enum BitLocalMotion {
    /// Strong ease-out (cubic-bezier(0.23, 1, 0.32, 1)) for responsive UI entrances.
    static let strongEaseOut = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.22)

    /// Crisp tactile press/release feedback under 160ms.
    static let press = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.14)

    /// Asymmetric faster exit for dismissals and secondary reveals.
    static let fastExit = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.16)

    /// Interruptible, zero-bounce spring for disclosures (opening hours, info reveals).
    static let disclosureSpring = Animation.spring(duration: 0.28, bounce: 0.0)

    /// Subtle spring for micro icon state morphs (copy -> checkmark).
    static let morphSpring = Animation.spring(duration: 0.26, bounce: 0.12)

    /// Gentle opacity-only fallback when Reduce Motion is enabled.
    static let reducedFade = Animation.easeOut(duration: 0.16)

    static func animation(_ standard: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? reducedFade : standard
    }
}

@MainActor
enum BitLocalHaptics {
    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    static func lightTap() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }

    static func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }
}

struct TactilePressButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    var pressedOpacity: Double = 0.88

    func makeBody(configuration: Configuration) -> some View {
        Content(
            configuration: configuration,
            scale: scale,
            pressedOpacity: pressedOpacity
        )
    }

    private struct Content: View {
        let configuration: Configuration
        let scale: CGFloat
        let pressedOpacity: Double
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1.0)
                .opacity(configuration.isPressed ? pressedOpacity : 1.0)
                .animation(
                    BitLocalMotion.animation(BitLocalMotion.press, reduceMotion: reduceMotion),
                    value: configuration.isPressed
                )
        }
    }
}

struct TactileRowButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.985
    var cornerRadius: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        Content(
            configuration: configuration,
            scale: scale,
            cornerRadius: cornerRadius
        )
    }

    private struct Content: View {
        let configuration: Configuration
        let scale: CGFloat
        let cornerRadius: CGFloat
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.06 : 0))
                )
                .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1.0)
                .animation(
                    BitLocalMotion.animation(BitLocalMotion.press, reduceMotion: reduceMotion),
                    value: configuration.isPressed
                )
        }
    }
}

extension ButtonStyle where Self == TactilePressButtonStyle {
    static var tactilePress: TactilePressButtonStyle { TactilePressButtonStyle() }

    static func tactilePress(
        scale: CGFloat,
        pressedOpacity: Double = 0.88
    ) -> TactilePressButtonStyle {
        TactilePressButtonStyle(scale: scale, pressedOpacity: pressedOpacity)
    }
}

extension ButtonStyle where Self == TactileRowButtonStyle {
    static var tactileRow: TactileRowButtonStyle { TactileRowButtonStyle() }

    static func tactileRow(
        scale: CGFloat = 0.985,
        cornerRadius: CGFloat = 12
    ) -> TactileRowButtonStyle {
        TactileRowButtonStyle(scale: scale, cornerRadius: cornerRadius)
    }
}

/// Wrapping horizontal flow layout for compact badges, payment rails, and social chips.
struct BitLocalFlowLayout: Layout {
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var measuredWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > 0 && currentX + size.width > maxWidth {
                currentX = 0
                currentY += lineHeight + verticalSpacing
                lineHeight = 0
            }
            measuredWidth = max(measuredWidth, currentX + size.width)
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + horizontalSpacing
        }

        let totalHeight = subviews.isEmpty ? 0 : currentY + lineHeight
        let resolvedWidth = proposal.width ?? measuredWidth
        return CGSize(width: resolvedWidth, height: totalHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > bounds.minX && currentX + size.width > bounds.maxX {
                currentX = bounds.minX
                currentY += lineHeight + verticalSpacing
                lineHeight = 0
            }
            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                proposal: ProposedViewSize(size)
            )
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + horizontalSpacing
        }
    }
}

enum ElementCategoryBadgeHelper {
    /// Returns the crisp uncircled SF Symbol matching the map marker glyph 1:1.
    static func badgeSymbolName(for element: Element) -> String {
        let raw: String
        if let group = ElementCategorySymbols.merchantCategoryGroups(for: element).first {
            raw = ElementCategorySymbols.merchantCategoryDescriptor(for: group).chipSymbolName
        } else {
            raw = ElementCategorySymbols.symbolName(for: element)
        }
        return uncircledSymbolName(from: raw)
    }

    static func primaryCategoryLabel(for element: Element) -> String? {
        if let group = ElementCategorySymbols.merchantCategoryGroups(for: element).first {
            return group.localizedLabel
        }
        return ElementCategorySymbols.friendlyCategoryLabel(
            forIcon: element.v4Metadata?.icon ?? element.tags?.iconPlatform
        )
    }

    private static let uncircledSymbolCache = Mutex<[String: String]>([:])

    static func uncircledSymbolName(from raw: String) -> String {
        if let cached = uncircledSymbolCache.withLock({ $0[raw] }) {
            return cached
        }

        var resolved = raw
        for suffix in [".circle.fill", ".circle"] where raw.hasSuffix(suffix) {
            let base = String(raw.dropLast(suffix.count))
            let filled = "\(base).fill"
            if UIImage(systemName: filled) != nil {
                resolved = filled
                break
            }
            if UIImage(systemName: base) != nil {
                resolved = base
                break
            }
        }

        uncircledSymbolCache.withLock { $0[raw] = resolved }
        return resolved
    }
}

/// Adaptive translucent surface tokens for controls, cards, and search fields inside
/// floating Liquid Glass / material sheets.
///
/// Using primary-tinted translucent fills instead of stacking `.regularMaterial`
/// avoids white-on-white washout in Light Mode and harsh opaque charcoal cutouts
/// over translucent glass in Dark Mode, while letting elements follow the sheet's
/// underlying background seamlessly.
enum BitLocalSheetSurfaceRole: Sendable {
    /// Grouped detail cards (`PlaceGroupedSurface`, community icon frame).
    case card
    /// Interactive secondary buttons, pills, and unselected filter chips.
    case control
    /// Search input capsules that subtly follow the sheet background.
    case searchField
}

enum BitLocalSheetSurface {
    static func fillOpacity(
        for role: BitLocalSheetSurfaceRole,
        colorScheme: ColorScheme,
        contrast: ColorSchemeContrast
    ) -> Double {
        let isDark = colorScheme == .dark
        let isIncreased = contrast == .increased
        switch role {
        case .card:
            if isIncreased { return isDark ? 0.16 : 0.10 }
            return isDark ? 0.08 : 0.06
        case .control:
            if isIncreased { return isDark ? 0.18 : 0.13 }
            return isDark ? 0.11 : 0.08
        case .searchField:
            if isIncreased { return isDark ? 0.14 : 0.09 }
            return isDark ? 0.06 : 0.05
        }
    }

    static func borderOpacity(
        for role: BitLocalSheetSurfaceRole,
        colorScheme: ColorScheme,
        contrast: ColorSchemeContrast
    ) -> Double {
        let isDark = colorScheme == .dark
        let isIncreased = contrast == .increased
        switch role {
        case .card:
            if isIncreased { return isDark ? 0.30 : 0.28 }
            return isDark ? 0.14 : 0.11
        case .control:
            if isIncreased { return isDark ? 0.32 : 0.30 }
            return isDark ? 0.16 : 0.12
        case .searchField:
            if isIncreased { return isDark ? 0.30 : 0.26 }
            return isDark ? 0.15 : 0.12
        }
    }

    static func fillColor(
        for role: BitLocalSheetSurfaceRole,
        colorScheme: ColorScheme,
        contrast: ColorSchemeContrast
    ) -> Color {
        Color.primary.opacity(fillOpacity(for: role, colorScheme: colorScheme, contrast: contrast))
    }

    static func borderColor(
        for role: BitLocalSheetSurfaceRole,
        colorScheme: ColorScheme,
        contrast: ColorSchemeContrast
    ) -> Color {
        Color.primary.opacity(borderOpacity(for: role, colorScheme: colorScheme, contrast: contrast))
    }
}

/// Adaptive translucent grouped container shared by Merchant and Community detail screens.
struct PlaceGroupedSurface<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let padding: EdgeInsets
    let content: Content

    init(
        padding: EdgeInsets = EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14),
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                BitLocalSheetSurface.fillColor(
                    for: .card,
                    colorScheme: colorScheme,
                    contrast: colorSchemeContrast
                ),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        BitLocalSheetSurface.borderColor(
                            for: .card,
                            colorScheme: colorScheme,
                            contrast: colorSchemeContrast
                        ),
                        lineWidth: 0.5
                    )
            }
    }
}

/// Inline 44x44pt tactile copy button with symbol morph (doc.on.doc -> green checkmark) and success haptic.
struct TactileCopyButton: View {
    let value: String
    let accessibilityLabel: String

    @State private var copied = false
    @State private var resetTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            UIPasteboard.general.string = value

            resetTask?.cancel()
            withAnimation(
                BitLocalMotion.animation(BitLocalMotion.morphSpring, reduceMotion: reduceMotion)
            ) {
                copied = true
            }

            resetTask = Task {
                try? await Task.sleep(for: .milliseconds(1600))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    withAnimation(
                        BitLocalMotion.animation(BitLocalMotion.fastExit, reduceMotion: reduceMotion)
                    ) {
                        copied = false
                    }
                }
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.footnote.weight(.medium))
                .foregroundStyle(copied ? Color.green : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.tactilePress(scale: 0.92))
        .sensoryFeedback(.success, trigger: copied) { _, isCopied in
            isCopied
        }
        .accessibilityLabel(copied ? Text("Copied") : Text(accessibilityLabel))
        .onDisappear {
            resetTask?.cancel()
        }
    }
}


