// BusinessDetailView.swift

import SwiftUI
import CoreLocation
import MapKit
import Contacts
import Foundation
import UIKit
import NaturalLanguage
#if canImport(Translation)
import Translation
#endif

// Helper function to open location in Maps with full details
func openLocationInMaps(coordinate: CLLocationCoordinate2D, name: String?, address: Address?) {
    Debug.log("openLocationInMaps called - Name: \(name ?? "nil"), Street#: \(address?.streetNumber ?? "nil"), Street: \(address?.streetName ?? "nil"), City: \(address?.cityOrTownName ?? "nil")")

    // Build search query with name and address to help find the actual place
    var searchQuery = ""
    if let name = name {
        searchQuery = name
    }

    // Build full street address with number
    var fullAddress = ""
    if let streetNumber = address?.streetNumber, !streetNumber.isEmpty {
        fullAddress = streetNumber + " "
    }
    if let streetName = address?.streetName {
        fullAddress += streetName
    }

    if !fullAddress.isEmpty, let city = address?.cityOrTownName {
        if !searchQuery.isEmpty {
            searchQuery += ", "
        }
        searchQuery += "\(fullAddress), \(city)"
    }

    Debug.log("Search query: \(searchQuery)")

    // If we have a search query, try to find the actual place in Apple Maps
    if !searchQuery.isEmpty {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchQuery
        request.region = MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))

        let search = MKLocalSearch(request: request)
        search.start { response, error in
            if let mapItem = response?.mapItems.first {
                Debug.log("MKLocalSearch found match: \(mapItem.name ?? "nil")")
                // Found a matching place in Apple Maps - open it
                mapItem.openInMaps(launchOptions: nil)
            } else {
                Debug.log("MKLocalSearch failed, using fallback. Error: \(error?.localizedDescription ?? "none")")
                // Fallback: open with coordinates if search fails
                openCoordinateInMaps(coordinate: coordinate, name: name, address: address)
            }
        }
    } else {
        Debug.log("No search query, using fallback")
        // No search info available, fallback to coordinates
        openCoordinateInMaps(coordinate: coordinate, name: name, address: address)
    }
}

// Fallback function to open just the coordinates
private func openCoordinateInMaps(coordinate: CLLocationCoordinate2D, name: String?, address: Address?) {
    var addressDict: [String: Any] = [:]

    // Build full street address with street number
    var fullStreet = ""
    if let streetNumber = address?.streetNumber, !streetNumber.isEmpty {
        fullStreet = streetNumber
    }
    if let streetName = address?.streetName {
        if !fullStreet.isEmpty {
            fullStreet += " "
        }
        fullStreet += streetName
    }
    if !fullStreet.isEmpty {
        addressDict[CNPostalAddressStreetKey] = fullStreet
    }

    if let city = address?.cityOrTownName {
        addressDict[CNPostalAddressCityKey] = city
    }

    if let state = address?.regionOrStateName {
        addressDict[CNPostalAddressStateKey] = state
    }

    if let postalCode = address?.postalCode {
        addressDict[CNPostalAddressPostalCodeKey] = postalCode
    }

    Debug.log("Opening coordinate in Maps - Name: \(name ?? "nil"), Street: \(fullStreet), City: \(addressDict[CNPostalAddressCityKey] ?? "nil"), State: \(addressDict[CNPostalAddressStateKey] ?? "nil"), Zip: \(addressDict[CNPostalAddressPostalCodeKey] ?? "nil")")

    let placemark = MKPlacemark(coordinate: coordinate, addressDictionary: addressDict)
    let mapItem = MKMapItem(placemark: placemark)
    mapItem.name = name
    mapItem.openInMaps(launchOptions: nil)
}

// MARK: - Verification State Model

private enum PlaceVerificationState: Equatable {
    case verified(Date)
    case outdated(Date)
    case loading
    case unverified

    var icon: String {
        switch self {
        case .verified:
            return "checkmark.seal.fill"
        case .outdated:
            return "exclamationmark.triangle.fill"
        case .loading:
            return "clock"
        case .unverified:
            return "questionmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .verified:
            return .green
        case .outdated:
            return .orange
        case .loading, .unverified:
            return .secondary
        }
    }

    var compactStatusTitle: LocalizedStringKey {
        switch self {
        case .verified:
            return "Verified"
        case .outdated:
            return "Not Recently Verified"
        case .loading:
            return "Checking…"
        case .unverified:
            return "Unverified"
        }
    }

    var detailTitle: LocalizedStringKey {
        switch self {
        case .verified:
            return "Verified"
        case .outdated:
            return "Not Recently Verified"
        case .loading:
            return "Loading verification status…"
        case .unverified:
            return "Not Yet Verified"
        }
    }

    var explanation: LocalizedStringKey {
        switch self {
        case .verified:
            return "Someone physically confirmed this place accepts bitcoin within the past year."
        case .outdated:
            return "It has been more than a year since someone reported that this location accepts bitcoin. It likely still does, but no one has confirmed so recently."
        case .loading:
            return "Checking community verification history on BTC Map."
        case .unverified:
            return "This place was added to BitLocal but hasn't been physically checked by a community member."
        }
    }

    var formattedDate: String? {
        switch self {
        case .verified(let date), .outdated(let date):
            return date.formatted(date: .abbreviated, time: .omitted)
        case .loading, .unverified:
            return nil
        }
    }
}

// MARK: - BusinessDetailView

struct BusinessDetailView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @State private var showingShareErrorAlert = false
    @State private var showingFeaturedInfo = false
    @State private var shareItem: ShareURLItem?
    @State private var isHeroScrolledPast = false
    @State private var hydratedVerifiedAt: String?
    @State private var isLoadingVerifiedAt = false
    @State private var hasAttemptedVerificationHydration = false
    @StateObject var elementCellViewModel: ElementCellViewModel
    @EnvironmentObject var contentViewModel: ContentViewModel

    @AppStorage("distanceUnit") private var distanceUnit: DistanceUnit = .auto

    var element: Element
    var userLocation: CLLocation?
    @Binding private var currentDetent: PresentationDetent?

    private let repository: BTCMapRepositoryProtocol = BTCMapRepository.shared

    init(
        element: Element,
        userLocation: CLLocation?,
        contentViewModel: ContentViewModel,
        currentDetent: Binding<PresentationDetent?> = .constant(nil)
    ) {
        self.element = element
        self.userLocation = userLocation
        self._currentDetent = currentDetent
        self._elementCellViewModel = StateObject(
            wrappedValue: ElementCellViewModel(
                element: element,
                userLocation: userLocation,
                viewModel: contentViewModel
            )
        )
    }

    private var displayName: String {
        element.displayNameForUI ?? NSLocalizedString("name_not_available", comment: "Fallback name when no name is available")
    }

    private var categoryBadgeSymbolName: String {
        ElementCategoryBadgeHelper.badgeSymbolName(for: element)
    }

    private var primaryCategoryLabel: String? {
        ElementCategoryBadgeHelper.primaryCategoryLabel(for: element)
    }

    private var websiteInfo: (display: String, url: URL)? {
        guard let raw = element.osmJSON?.tags?.website ?? element.osmJSON?.tags?.contactWebsite,
              let url = raw.cleanedWebsiteURL() else {
            return nil
        }
        return (raw.cleanedForDisplay(), url)
    }

    private var phoneInfo: (display: String, url: URL)? {
        guard let raw = element.osmJSON?.tags?.phone ?? element.osmJSON?.tags?.contactPhone else {
            return nil
        }
        let (cleanPhone, isValid) = raw.cleanedPhoneNumber()
        guard isValid, let url = URL(string: "tel:\(cleanPhone)") else {
            return nil
        }
        return (raw.displayablePhoneNumber(), url)
    }

    private var emailInfo: (display: String, url: URL)? {
        guard let raw = element.v4Metadata?.email,
              !raw.isEmpty,
              let url = URL(string: "mailto:\(raw)") else {
            return nil
        }
        return (raw, url)
    }

    private var descriptionText: String? {
        let raw = element.osmJSON?.tags?.description ?? element.osmJSON?.tags?.descriptionEn
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private var openingHoursRaw: String? {
        guard let raw = element.osmJSON?.tags?.openingHours?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        return raw
    }

    private var parsedOpeningSchedule: OSMOpeningHoursWeekSchedule? {
        guard let openingHoursRaw else { return nil }
        return OSMOpeningHoursParser.parseWeekSchedule(openingHoursRaw)
    }

    private var verificationState: PlaceVerificationState {
        let raw = hydratedVerifiedAt ?? element.v4Metadata?.verifiedAt
        if let raw, let verifiedDate = raw.parsedBTCMapDate(),
           let oneYearAgo = Calendar.current.date(byAdding: .year, value: -1, to: Date()) {
            return verifiedDate > oneYearAgo ? .verified(verifiedDate) : .outdated(verifiedDate)
        }
        if isLoadingVerifiedAt {
            return .loading
        }
        return .unverified
    }

    private var reviewsCount: Int {
        element.v4Metadata?.commentsCount ?? 0
    }

    private func localizedDistanceString() -> String? {
        guard let userLocation = userLocation, let coord = element.mapCoordinate else { return nil }
        let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        let distanceInMeters = userLocation.distance(from: location)
        let useMetric: Bool
        switch distanceUnit {
        case .auto:
            useMetric = Locale.current.measurementSystem == .metric
        case .miles:
            useMetric = false
        case .kilometers:
            useMetric = true
        }
        if useMetric {
            let km = distanceInMeters / 1000
            return String(format: "%.1f km", km)
        } else {
            let miles = distanceInMeters / 1609.34
            return String(format: "%.1f mi", miles)
        }
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 18) {
                    heroHeader(scrollProxy: scrollProxy)

                    quickActionBar

                    PlacePaymentRailsStrip(element: element)

                    PlaceDetailsSurface(
                        element: element,
                        elementCellViewModel: elementCellViewModel,
                        openingHoursRaw: openingHoursRaw,
                        parsedOpeningSchedule: parsedOpeningSchedule,
                        websiteInfo: websiteInfo,
                        phoneInfo: phoneInfo,
                        emailInfo: emailInfo
                    )

                    if let descriptionText {
                        PlaceDescriptionSection(description: descriptionText)
                    }

                    if reviewsCount > 0 {
                        PlaceReviewsRow(element: element, count: reviewsCount)
                    }

                    PlaceTrustAndBoostSection(
                        element: element,
                        verificationState: verificationState
                    )
                    .id("place-verification-section")
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
            .background(Color.clear)
            .scrollContentBackground(.hidden)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 56
            } action: { _, scrolledPast in
                guard isHeroScrolledPast != scrolledPast else { return }
                withAnimation(BitLocalMotion.animation(BitLocalMotion.fastExit, reduceMotion: reduceMotion)) {
                    isHeroScrolledPast = scrolledPast
                }
            }
        }
        // Only observes live height while collapsed-like; expanded detail is free of drag churn.
        .sheetCollapsedReveal(
            geometry: contentViewModel.sheetGeometry,
            isCollapsedLike: isCollapsedLikeDetent
        )
        .onAppear {
            Debug.log("BusinessDetailView appeared for element: \(element.id)")
            Debug.log("ElementCellViewModel address: \(elementCellViewModel.address?.streetName ?? "nil")")
            elementCellViewModel.onCellAppear()
        }
        .task(id: element.id) {
            hydrateVerificationIfNeeded()
        }
        .navigationTitle((isHeroScrolledPast || isCollapsedLikeDetent) ? displayName : "")
        .navigationBarTitleDisplayMode(.inline)
        .bitLocalDetailNavigationChrome()
        .toolbar {
            if isHeroScrolledPast && FeatureFlags.isSharePlaceLinksEnabled {
                ToolbarItem(placement: .topBarTrailing) {
                    shareToolbarItem
                }
            }
        }
        .alert("Unable to share this place", isPresented: $showingShareErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The place link could not be created.")
        }
        .alert("Featured Merchant", isPresented: $showingFeaturedInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This business has been boosted on BTC Map, which means someone in the community has paid to help more people discover it.")
        }
        .sheet(item: $shareItem) { item in
            if let name = item.merchantName, !name.isEmpty {
                ShareActivityView(items: [String(localized: "Check out \(name) on BitLocal! 🟠"), item.url])
            } else {
                ShareActivityView(items: [item.url])
            }
        }
    }
}

// MARK: - Hero Header & Quick Actions

private extension BusinessDetailView {
    @ViewBuilder
    func heroHeader(scrollProxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                // Solid map-pin badge linking the place card 1:1 to its map marker.
                let isBoosted = element.isCurrentlyBoosted()
                Image(systemName: categoryBadgeSymbolName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        isBoosted ? Color.orange : Color("MarkerColor"),
                        in: Circle()
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(0.24), lineWidth: 0.75)
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(displayName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    if let metadataLine = heroMetadataLine {
                        Text(metadataLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Quiet inline status metadata (no extra capsule clutter)
            if parsedOpeningSchedule != nil || verificationState != .loading || shouldShowFeaturedBadgeInExpandedContent {
                BitLocalFlowLayout(horizontalSpacing: 12, verticalSpacing: 0) {
                    if let schedule = parsedOpeningSchedule {
                        let status = OpeningHoursLiveStatus.evaluate(schedule: schedule)
                        HStack(spacing: 5) {
                            Circle()
                                .fill(status.isOpen ? Color.green : Color.secondary)
                                .frame(width: 6, height: 6)
                            Text(status.shortLabel)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(status.isOpen ? Color.green : Color.secondary)
                        }
                        .frame(minHeight: 44)
                    }

                    if verificationState != .loading {
                        Button {
                            BitLocalHaptics.selection()
                            withAnimation(BitLocalMotion.animation(BitLocalMotion.disclosureSpring, reduceMotion: reduceMotion)) {
                                scrollProxy.scrollTo("place-verification-section", anchor: .center)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: verificationState.icon)
                                    .font(.caption.weight(.semibold))
                                Text(verificationState.compactStatusTitle)
                                    .font(.footnote.weight(.medium))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(verificationState.tint)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.tactilePress(scale: 0.96))
                    }

                    if shouldShowFeaturedBadgeInExpandedContent {
                        Button {
                            BitLocalHaptics.selection()
                            showingFeaturedInfo = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                    .font(.caption.weight(.semibold))
                                Text("Featured")
                                    .font(.footnote.weight(.semibold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(.orange)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.tactilePress(scale: 0.96))
                    }
                }
                .padding(.vertical, -8)
            }
        }
        .padding(.top, 2)
    }

    var heroMetadataLine: String? {
        var parts: [String] = []
        if let category = primaryCategoryLabel, !category.isEmpty {
            parts.append(category)
        }
        if let distance = localizedDistanceString() {
            parts.append(distance)
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    var quickActionBar: some View {
        let hasAnyAction = element.mapCoordinate != nil || phoneInfo != nil || websiteInfo != nil || FeatureFlags.isSharePlaceLinksEnabled
        if hasAnyAction {
            HStack(spacing: 8) {
                if let coord = element.mapCoordinate {
                    quickActionButton(
                        title: LocalizedStringKey("Directions"),
                        systemImage: "arrow.triangle.turn.up.right.diamond.fill",
                        isPrimary: true
                    ) {
                        BitLocalHaptics.lightTap()
                        openLocationInMaps(
                            coordinate: coord,
                            name: element.displayName,
                            address: elementCellViewModel.address
                        )
                    }
                }

                if let phone = phoneInfo {
                    quickActionButton(
                        title: LocalizedStringKey("Call"),
                        systemImage: "phone.fill",
                        isPrimary: false
                    ) {
                        BitLocalHaptics.lightTap()
                        openURL(phone.url)
                    }
                }

                if let website = websiteInfo {
                    quickActionButton(
                        title: LocalizedStringKey("Website"),
                        systemImage: "safari.fill",
                        isPrimary: false
                    ) {
                        BitLocalHaptics.lightTap()
                        openURL(website.url)
                    }
                }

                if FeatureFlags.isSharePlaceLinksEnabled {
                    quickActionButton(
                        title: LocalizedStringKey("Share"),
                        systemImage: "square.and.arrow.up",
                        isPrimary: false
                    ) {
                        BitLocalHaptics.lightTap()
                        triggerShare()
                    }
                }
            }
        }
    }

    func quickActionButton(
        title: LocalizedStringKey,
        systemImage: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.callout.weight(.semibold))
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isPrimary ? Color.white : Color.accentColor)
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
            .background {
                if isPrimary {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.accentColor)
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.regularMaterial)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isPrimary ? Color.clear : Color(.separator).opacity(0.35),
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(.tactilePress(scale: 0.96))
    }

    @ViewBuilder
    var shareToolbarItem: some View {
        if FeatureFlags.isSharePlaceLinksEnabled {
            Button {
                BitLocalHaptics.lightTap()
                triggerShare()
            } label: {
                Label("Share place", systemImage: "square.and.arrow.up")
            }
        }
    }

    func triggerShare() {
        if let shareURL = PlaceShareLinkBuilder.makeShareURL(forPlaceID: element.id) {
            shareItem = ShareURLItem(url: shareURL, merchantName: element.displayName)
        } else {
            Debug.log("Share link generation failed for place id: \(element.id)")
            showingShareErrorAlert = true
        }
    }

    var shouldShowFeaturedBadgeInExpandedContent: Bool {
        // Detent-based only so featured chrome does not thrash during drag.
        element.isCurrentlyBoosted() && !isCollapsedLikeDetent
    }

    var isCollapsedLikeDetent: Bool {
        guard let currentDetent else { return false }
        return currentDetent == BottomSheetDetents.collapsed || detentIdentifier(currentDetent).contains("fraction 0.11")
    }

    func detentIdentifier(_ detent: PresentationDetent) -> String {
        String(describing: detent).lowercased()
    }

    func hydrateVerificationIfNeeded() {
        let existing = hydratedVerifiedAt ?? element.v4Metadata?.verifiedAt
        guard existing == nil else { return }
        guard !isLoadingVerifiedAt else { return }
        guard !hasAttemptedVerificationHydration else { return }

        hasAttemptedVerificationHydration = true
        isLoadingVerifiedAt = true

        repository.fetchPlace(id: element.id) { result in
            DispatchQueue.main.async {
                if case .success(let record) = result,
                   let verifiedAt = record.verifiedAt,
                   !verifiedAt.isEmpty {
                    hydratedVerifiedAt = verifiedAt
                }
                isLoadingVerifiedAt = false
            }
        }
    }
}

// MARK: - Native Material Grouped Surface

private struct PlaceGroupedSurface<Content: View>: View {
    var padding: EdgeInsets = EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color(.separator).opacity(0.35), lineWidth: 0.5)
            )
    }
}

// MARK: - Bitcoin Payment Rails Strip (Signature Unboxed Strip)

private struct PlacePaymentRailsStrip: View {
    let element: Element
    @Environment(\.openURL) private var openURL

    private struct PaymentRail: Identifiable {
        let id: String
        let icon: String
        let shortLabel: String
        let accessibilityLabel: String
        let tint: Color
    }

    private var rails: [PaymentRail] {
        var items: [PaymentRail] = []
        if acceptsLightning(element: element) {
            items.append(
                PaymentRail(
                    id: "lightning",
                    icon: "bolt.fill",
                    shortLabel: "Lightning",
                    accessibilityLabel: NSLocalizedString("accepts_bitcoin_lightning", comment: "Label for accepting Bitcoin over Lightning"),
                    tint: .orange
                )
            )
        }
        if acceptsContactlessLightning(element: element) {
            items.append(
                PaymentRail(
                    id: "nfc",
                    icon: "wave.3.right",
                    shortLabel: "NFC",
                    accessibilityLabel: NSLocalizedString("accepts_contactless_lightning", comment: "Label for accepting Contactless Lightning"),
                    tint: .accentColor
                )
            )
        }
        if acceptsBitcoinOnChain(element: element) {
            items.append(
                PaymentRail(
                    id: "onchain",
                    icon: "bitcoinsign",
                    shortLabel: "On-Chain",
                    accessibilityLabel: NSLocalizedString("accepts_bitcoin_onchain", comment: "Label for accepting Bitcoin on Chain"),
                    tint: .orange
                )
            )
        }
        if acceptsBitcoin(element: element) {
            items.append(
                PaymentRail(
                    id: "bitcoin",
                    icon: "bitcoinsign",
                    shortLabel: NSLocalizedString("accepts_bitcoin", comment: "Label for accepting Bitcoin"),
                    accessibilityLabel: NSLocalizedString("accepts_bitcoin", comment: "Label for accepting Bitcoin"),
                    tint: .orange
                )
            )
        }
        return items
    }

    private var requiredApp: (raw: String, url: URL)? {
        guard let raw = element.v4Metadata?.requiredAppURL,
              !raw.isEmpty,
              let url = URL(string: raw) else {
            return nil
        }
        return (raw, url)
    }

    var body: some View {
        if !rails.isEmpty || requiredApp != nil {
            VStack(alignment: .leading, spacing: 10) {
                if !rails.isEmpty {
                    BitLocalFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                        ForEach(rails) { rail in
                            HStack(spacing: 5) {
                                Image(systemName: rail.icon)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(rail.tint)
                                Text(rail.shortLabel)
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(.regularMaterial, in: Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color(.separator).opacity(0.35), lineWidth: 0.5)
                            )
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(rail.accessibilityLabel)
                        }
                    }
                }

                if let requiredApp {
                    PlaceGroupedSurface(padding: EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)) {
                        Button {
                            BitLocalHaptics.lightTap()
                            openURL(requiredApp.url)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "app.badge.fill")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.orange)
                                    .frame(width: 20, alignment: .center)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Required App")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(requiredApp.raw.cleanedForDisplay())
                                        .font(.subheadline)
                                        .foregroundStyle(.accent)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 0)

                                Image(systemName: "arrow.up.forward")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(minHeight: 36)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.tactileRow(cornerRadius: 10))
                    }
                }
            }
        }
    }
}

// MARK: - Live Opening Hours Evaluator

private struct OpeningHoursLiveStatus {
    let isOpen: Bool
    let shortLabel: LocalizedStringKey

    static func evaluate(
        schedule: OSMOpeningHoursWeekSchedule,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> OpeningHoursLiveStatus {
        if schedule.isTwentyFourSeven {
            return OpeningHoursLiveStatus(isOpen: true, shortLabel: "Open 24/7")
        }

        let today = weekday(for: calendar.component(.weekday, from: now))
        let components = calendar.dateComponents([.hour, .minute], from: now)
        let nowMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)

        if let todaySchedule = schedule.days.first(where: { $0.weekday == today }) {
            for range in todaySchedule.ranges {
                if range.isAllDay {
                    return OpeningHoursLiveStatus(isOpen: true, shortLabel: "Open")
                }
                if range.endMinutes >= range.startMinutes {
                    if nowMinutes >= range.startMinutes && nowMinutes < range.endMinutes {
                        return OpeningHoursLiveStatus(isOpen: true, shortLabel: "Open")
                    }
                } else {
                    if nowMinutes >= range.startMinutes {
                        return OpeningHoursLiveStatus(isOpen: true, shortLabel: "Open")
                    }
                }
            }
        }

        if let yesterdayDate = calendar.date(byAdding: .day, value: -1, to: now) {
            let yesterday = weekday(for: calendar.component(.weekday, from: yesterdayDate))
            if let yesterdaySchedule = schedule.days.first(where: { $0.weekday == yesterday }) {
                for range in yesterdaySchedule.ranges {
                    if range.endMinutes > 24 * 60 {
                        let spilloverEnd = range.endMinutes - 24 * 60
                        if nowMinutes < spilloverEnd {
                            return OpeningHoursLiveStatus(isOpen: true, shortLabel: "Open")
                        }
                    } else if range.endMinutes < range.startMinutes && nowMinutes < range.endMinutes {
                        return OpeningHoursLiveStatus(isOpen: true, shortLabel: "Open")
                    }
                }
            }
        }

        return OpeningHoursLiveStatus(isOpen: false, shortLabel: "Closed")
    }

    static func weekday(for calendarWeekday: Int) -> WeeklyHours.Weekday {
        switch calendarWeekday {
        case 1: return .sunday
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        case 7: return .saturday
        default: return .monday
        }
    }
}

// MARK: - Unified Details Surface (Hours, Address, Contact & Socials)

private struct PlaceDetailsSurface: View {
    let element: Element
    @ObservedObject var elementCellViewModel: ElementCellViewModel
    let openingHoursRaw: String?
    let parsedOpeningSchedule: OSMOpeningHoursWeekSchedule?
    let websiteInfo: (display: String, url: URL)?
    let phoneInfo: (display: String, url: URL)?
    let emailInfo: (display: String, url: URL)?

    @State private var isHoursExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    private struct SocialItem: Identifiable {
        let id: String
        let label: String
        let icon: String
        let value: String
        let url: URL?
    }

    private var addressDisplayText: String {
        elementCellViewModel.address?.formatted(.compact) ?? ""
    }

    private var todayWeekday: WeeklyHours.Weekday {
        OpeningHoursLiveStatus.weekday(for: Calendar.current.component(.weekday, from: Date()))
    }

    private var socialItems: [SocialItem] {
        guard let metadata = element.v4Metadata else { return [] }
        let candidates: [(String, String, String?, URL?)] = [
            ("X", "xmark", metadata.twitter, metadata.twitter.flatMap { urlForSocialHandle($0, base: "https://twitter.com/") }),
            ("Instagram", "camera", metadata.instagram, metadata.instagram.flatMap { urlForSocialHandle($0, base: "https://instagram.com/") }),
            ("Telegram", "paperplane", metadata.telegram, metadata.telegram.flatMap { urlForSocialHandle($0, base: "https://t.me/") }),
            ("Facebook", "f.cursive", metadata.facebook, metadata.facebook.flatMap { urlForSocialHandle($0, base: "https://facebook.com/") }),
            ("LINE", "message", metadata.line, metadata.line.flatMap(URL.init(string:)))
        ]
        return candidates.compactMap { item in
            guard let raw = item.2?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
                return nil
            }
            return SocialItem(
                id: item.0,
                label: item.0,
                icon: item.1,
                value: raw.cleanedForDisplay(),
                url: item.3
            )
        }
    }

    private var hasHours: Bool { openingHoursRaw != nil }
    private var hasAddress: Bool { element.mapCoordinate != nil }
    private var hasWebsite: Bool { websiteInfo != nil }
    private var hasPhone: Bool { phoneInfo != nil }
    private var hasEmail: Bool { emailInfo != nil }
    private var hasAnyContactOrHours: Bool { hasHours || hasAddress || hasWebsite || hasPhone || hasEmail }
    private var hasAnyContent: Bool { hasAnyContactOrHours || !socialItems.isEmpty }

    var body: some View {
        if hasAnyContent {
            PlaceGroupedSurface(padding: EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 10)) {
                VStack(alignment: .leading, spacing: 0) {
                    if let openingHoursRaw {
                        hoursSection(rawOpeningHours: openingHoursRaw)
                    }

                    if let coord = element.mapCoordinate {
                        if hasHours { rowDivider }
                        contactRow(
                            icon: "mappin.and.ellipse",
                            label: NSLocalizedString("address_label", comment: "Label for address"),
                            value: addressDisplayText.isEmpty ? "Open in Apple Maps" : addressDisplayText,
                            copyValue: addressDisplayText.isEmpty ? nil : addressDisplayText,
                            copyTitle: "Copy Address",
                            valueLineLimit: 3
                        ) {
                            BitLocalHaptics.lightTap()
                            openLocationInMaps(
                                coordinate: coord,
                                name: element.displayName,
                                address: elementCellViewModel.address
                            )
                        }
                    }

                    if let website = websiteInfo {
                        if hasHours || hasAddress { rowDivider }
                        contactRow(
                            icon: "globe",
                            label: NSLocalizedString("website_label", comment: "Label for website"),
                            value: website.display,
                            copyValue: website.display,
                            copyTitle: "Copy Website",
                            valueLineLimit: 2
                        ) {
                            BitLocalHaptics.lightTap()
                            openURL(website.url)
                        }
                    }

                    if let phone = phoneInfo {
                        if hasHours || hasAddress || hasWebsite { rowDivider }
                        contactRow(
                            icon: "phone",
                            label: NSLocalizedString("phone_label", comment: "Label for phone"),
                            value: phone.display,
                            copyValue: phone.display,
                            copyTitle: "Copy Phone",
                            valueLineLimit: 1
                        ) {
                            BitLocalHaptics.lightTap()
                            openURL(phone.url)
                        }
                    }

                    if let email = emailInfo {
                        if hasHours || hasAddress || hasWebsite || hasPhone { rowDivider }
                        contactRow(
                            icon: "envelope",
                            label: "Email",
                            value: email.display,
                            copyValue: email.display,
                            copyTitle: "Copy Email",
                            valueLineLimit: 2
                        ) {
                            BitLocalHaptics.lightTap()
                            openURL(email.url)
                        }
                    }

                    if !socialItems.isEmpty {
                        if hasAnyContactOrHours { rowDivider }
                        socialsRow
                    }
                }
            }
        }
    }

    private var rowDivider: some View {
        Divider()
            .padding(.leading, 32)
            .padding(.trailing, 4)
    }

    @ViewBuilder
    private func hoursSection(rawOpeningHours: String) -> some View {
        if let parsedSchedule = parsedOpeningSchedule {
            let status = OpeningHoursLiveStatus.evaluate(schedule: parsedSchedule)
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    BitLocalHaptics.selection()
                    withAnimation(
                        BitLocalMotion.animation(
                            BitLocalMotion.disclosureSpring,
                            reduceMotion: reduceMotion
                        )
                    ) {
                        isHoursExpanded.toggle()
                    }
                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "clock")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, alignment: .center)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                Text(NSLocalizedString("opening_hours_label", comment: "Label for opening hours"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("·")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                Text(status.shortLabel)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(status.isOpen ? Color.green : Color.secondary)
                            }

                            Text(todaySummaryText(for: parsedSchedule))
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .monospacedDigit()
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)

                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isHoursExpanded ? 180 : 0))
                            .padding(.trailing, 6)
                    }
                    .padding(.vertical, 8)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.tactileRow(cornerRadius: 10))
                .accessibilityHint(isHoursExpanded ? "Double-tap to collapse weekly hours" : "Double-tap to view weekly hours")

                if isHoursExpanded {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(parsedSchedule.days, id: \.weekday) { day in
                            let isToday = day.weekday == todayWeekday
                            HStack(alignment: .top, spacing: 12) {
                                Text(shortWeekdayLabel(for: day.weekday))
                                    .font(.footnote)
                                    .fontWeight(isToday ? .semibold : .regular)
                                    .foregroundStyle(isToday ? .primary : .secondary)
                                    .lineLimit(1)
                                    .frame(width: 40, alignment: .leading)

                                hoursText(for: day, isToday: isToday)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                        }
                    }
                    .padding(.leading, 32)
                    .padding(.trailing, 8)
                    .padding(.bottom, 10)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
                    )
                }
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "clock")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, alignment: .center)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("opening_hours_label", comment: "Label for opening hours"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(rawOpeningHours)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.vertical, 8)
            .padding(.trailing, 6)
        }
    }

    @ViewBuilder
    private func contactRow(
        icon: String,
        label: String,
        value: String,
        copyValue: String?,
        copyTitle: String,
        valueLineLimit: Int,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 4) {
            Button(action: action) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, alignment: .center)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(value)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(valueLineLimit)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.tactileRow(cornerRadius: 10))
            .copyValueContextMenu(copyValue, title: copyTitle)

            if let copyValue, !copyValue.isEmpty {
                TactileCopyButton(value: copyValue, accessibilityLabel: copyTitle)
            }
        }
    }

    private var socialsRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "at")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .center)
                .padding(.top, 12)

            VStack(alignment: .leading, spacing: 0) {
                Text("Socials")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)

                BitLocalFlowLayout(horizontalSpacing: 14, verticalSpacing: 0) {
                    ForEach(socialItems) { social in
                        socialLink(social)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private func socialLink(_ social: SocialItem) -> some View {
        let content = HStack(spacing: 5) {
            Image(systemName: social.icon)
                .font(.caption.weight(.semibold))
            Text(social.label)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(social.url != nil ? Color.accentColor : Color.primary)
        .frame(minHeight: 44)
        .contentShape(Rectangle())

        if let url = social.url {
            Button {
                BitLocalHaptics.lightTap()
                openURL(url)
            } label: {
                content
            }
            .buttonStyle(.tactilePress(scale: 0.96))
            .copyValueContextMenu(social.value, title: "Copy \(social.label)")
        } else {
            content
                .copyValueContextMenu(social.value, title: "Copy \(social.label)")
        }
    }

    private func todaySummaryText(for schedule: OSMOpeningHoursWeekSchedule) -> String {
        if schedule.isTwentyFourSeven {
            return "24/7"
        }
        guard let today = schedule.days.first(where: { $0.weekday == todayWeekday }) else {
            return NSLocalizedString("hours_closed", comment: "Closed label for business hours")
        }
        if today.ranges.isEmpty {
            return NSLocalizedString("hours_closed", comment: "Closed label for business hours")
        }
        if today.ranges.count == 1, today.ranges[0].isAllDay {
            return "24/7"
        }
        return today.ranges
            .map { formattedTime($0.startMinutes) + " \u{2013} " + formattedTime($0.endMinutes) }
            .joined(separator: ", ")
    }

    @ViewBuilder
    private func hoursText(for day: OSMOpeningHoursDaySchedule, isToday: Bool) -> some View {
        if day.ranges.isEmpty {
            Text(NSLocalizedString("hours_closed", comment: "Closed label for business hours"))
                .font(.footnote)
                .fontWeight(isToday ? .semibold : .regular)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else if day.ranges.count == 1, day.ranges[0].isAllDay {
            Text("24/7")
                .font(.footnote)
                .fontWeight(isToday ? .semibold : .regular)
                .foregroundStyle(.primary)
                .monospacedDigit()
                .lineLimit(1)
        } else {
            VStack(alignment: .trailing, spacing: 2) {
                ForEach(Array(day.ranges.enumerated()), id: \.offset) { _, range in
                    Text(formattedTime(range.startMinutes) + " \u{2013} " + formattedTime(range.endMinutes))
                        .font(.footnote)
                        .fontWeight(isToday ? .semibold : .regular)
                        .foregroundStyle(isToday ? .primary : .secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
        }
    }

    private func shortWeekdayLabel(for weekday: WeeklyHours.Weekday) -> String {
        let localizedWeekday: String
        switch weekday {
        case .monday:
            localizedWeekday = NSLocalizedString("weekday_mo", comment: "Monday abbreviation for business hours")
        case .tuesday:
            localizedWeekday = NSLocalizedString("weekday_tu", comment: "Tuesday abbreviation for business hours")
        case .wednesday:
            localizedWeekday = NSLocalizedString("weekday_we", comment: "Wednesday abbreviation for business hours")
        case .thursday:
            localizedWeekday = NSLocalizedString("weekday_th", comment: "Thursday abbreviation for business hours")
        case .friday:
            localizedWeekday = NSLocalizedString("weekday_fr", comment: "Friday abbreviation for business hours")
        case .saturday:
            localizedWeekday = NSLocalizedString("weekday_sa", comment: "Saturday abbreviation for business hours")
        case .sunday:
            localizedWeekday = NSLocalizedString("weekday_su", comment: "Sunday abbreviation for business hours")
        }

        let trimmed = localizedWeekday.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 3 {
            return trimmed
        }
        return String(trimmed.prefix(3))
    }

    private func formattedTime(_ totalMinutes: Int) -> String {
        let clampedMinutes = max(0, min(totalMinutes, 24 * 60))
        let hour = clampedMinutes / 60
        let minute = clampedMinutes % 60

        var components = DateComponents()
        components.calendar = Calendar.current
        components.hour = hour == 24 ? 0 : hour
        components.minute = minute

        guard let date = Calendar.current.date(from: components) else {
            return String(format: "%02d:%02d", hour, minute)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("jm")
        return formatter.string(from: date)
    }
}

// MARK: - Inline Tactile Copy Button (44pt Hit Target, Symbol Morph)

private struct TactileCopyButton: View {
    let value: String
    let accessibilityLabel: String

    @State private var copied = false
    @State private var resetTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            UIPasteboard.general.string = value
            BitLocalHaptics.success()

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
                .contentShape(Rectangle())
        }
        .buttonStyle(.tactilePress(scale: 0.92))
        .accessibilityLabel(copied ? "Copied" : accessibilityLabel)
        .onDisappear {
            resetTask?.cancel()
        }
    }
}

// MARK: - About / Description Section

private struct PlaceDescriptionSection: View {
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(NSLocalizedString("business_description_section", comment: "Section header for business description"))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            PlaceGroupedSurface {
                TranslatableBusinessDescriptionView(description: description)
            }
        }
    }
}

private struct TranslatableBusinessDescriptionView: View {
    let description: String

    @State private var translatedDescription: String?
    @State private var translationConfiguration: TranslationSession.Configuration?
    @State private var translationError: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hasSuccessfulTranslation: Bool {
        guard let translatedDescription else { return false }
        return !translatedDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var detectedLanguageCode: String? {
        guard description.count >= 20 else { return nil }
        return NLLanguageRecognizer.dominantLanguage(for: description)?.rawValue
    }

    private var preferredLanguageCode: String? {
        guard let preferredIdentifier = Locale.preferredLanguages.first else { return nil }
        return normalizedLanguageCode(preferredIdentifier)
    }

    private var sourceLanguage: Locale.Language? {
        guard let detectedLanguageCode else { return nil }
        return Locale.Language(identifier: detectedLanguageCode)
    }

    private var targetLanguage: Locale.Language? {
        guard let preferredLanguageCode else { return nil }
        return Locale.Language(identifier: preferredLanguageCode)
    }

    private var shouldOfferTranslation: Bool {
        guard let detectedLanguageCode, let preferredLanguageCode else { return false }
        return normalizedLanguageCode(detectedLanguageCode) != preferredLanguageCode
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineSpacing(3)

            if let translatedDescription, !translatedDescription.isEmpty {
                Text(translatedDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
                    )
            }

            if shouldOfferTranslation && !hasSuccessfulTranslation {
                Button(action: startTranslation) {
                    Label("Translate", systemImage: "translate")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.accent)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.tactilePress(scale: 0.96))
                .padding(.vertical, -8)
            }

            if hasSuccessfulTranslation {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Translated on device with Apple Translate")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .transition(.opacity)
            }

            if let translationError, !translationError.isEmpty {
                Text(translationError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .translationTask(translationConfiguration) { session in
            do {
                let response = try await session.translate(description)
                await MainActor.run {
                    withAnimation(
                        BitLocalMotion.animation(BitLocalMotion.strongEaseOut, reduceMotion: reduceMotion)
                    ) {
                        translatedDescription = response.targetText
                        translationError = nil
                    }
                }
            } catch {
                await MainActor.run {
                    withAnimation(
                        BitLocalMotion.animation(BitLocalMotion.fastExit, reduceMotion: reduceMotion)
                    ) {
                        translationError = error.localizedDescription
                    }
                }
            }
        }
    }

    private func startTranslation() {
        guard let sourceLanguage, let targetLanguage else { return }
        BitLocalHaptics.selection()
        translationError = nil
        translationConfiguration = TranslationSession.Configuration(
            source: sourceLanguage,
            target: targetLanguage
        )
    }

    private func normalizedLanguageCode(_ identifier: String) -> String {
        let normalized = identifier.replacingOccurrences(of: "_", with: "-").lowercased()
        return normalized.split(separator: "-", maxSplits: 1).first.map(String.init) ?? normalized
    }
}

// MARK: - Community Reviews Row & List View

private struct PlaceReviewsRow: View {
    let element: Element
    let count: Int

    var body: some View {
        NavigationLink {
            BTCMapPlaceCommentsListView(element: element)
        } label: {
            PlaceGroupedSurface(padding: EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)) {
                HStack(spacing: 12) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, alignment: .center)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Community Reviews")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Text(
                            String(
                                format: NSLocalizedString("%lld review%@", comment: "Review count label"),
                                count,
                                count == 1 ? "" : "s"
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .frame(minHeight: 36)
            }
        }
        .buttonStyle(.tactileRow(cornerRadius: 16))
    }
}

struct BTCMapPlaceCommentsListView: View {
    let element: Element

    @State private var comments: [V4PlaceCommentRecord] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var hasLoaded = false

    private let repository: BTCMapRepositoryProtocol = BTCMapRepository.shared

    var body: some View {
        List {
            if isLoading && comments.isEmpty {
                HStack {
                    ProgressView()
                    Text("Loading comments…")
                        .foregroundStyle(.secondary)
                }
            } else if let errorText, !errorText.isEmpty, comments.isEmpty {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.subheadline)
                Button("Retry") {
                    BitLocalHaptics.lightTap()
                    loadComments(force: true)
                }
            } else if comments.isEmpty {
                Text("No reviews yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(comments) { comment in
                    commentRow(comment)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Community Reviews")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: element.id) {
            loadComments()
        }
    }

    @ViewBuilder
    private func commentRow(_ comment: V4PlaceCommentRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                if let author = comment.authorDisplayName {
                    Text(author)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                } else {
                    Text("Anonymous")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let createdAt = comment.createdAt, !createdAt.isEmpty {
                    Text(createdAt.formattedBTCMapDate())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !comment.bodyText.isEmpty {
                TranslatableReviewBodyTextView(text: comment.bodyText)
            }

            if let sats = comment.amountSats, sats > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "bolt.fill")
                        .font(.caption2)
                    Text(String(format: NSLocalizedString("~%lld sats", comment: "Approximate sats amount label"), sats))
                        .font(.caption)
                }
                .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
        .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
    }

    private func loadComments(force: Bool = false) {
        guard !isLoading else { return }
        if hasLoaded && !force { return }

        isLoading = true
        errorText = nil

        repository.fetchPlaceComments(placeID: element.id) { result in
            DispatchQueue.main.async {
                isLoading = false
                hasLoaded = true
                switch result {
                case .success(let comments):
                    self.comments = comments
                        .filter { !$0.bodyText.isEmpty }
                        .sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
                case .failure(let error):
                    errorText = error.localizedDescription
                }
            }
        }
    }
}

private struct TranslatableReviewBodyTextView: View {
    let text: String

    @State private var translatedText: String?
    @State private var translationConfiguration: TranslationSession.Configuration?
    @State private var translationError: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hasSuccessfulTranslation: Bool {
        guard let translatedText else { return false }
        return !translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var detectedLanguageCode: String? {
        guard text.count >= 20 else { return nil }
        return NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue
    }

    private var preferredLanguageCode: String? {
        guard let preferredIdentifier = Locale.preferredLanguages.first else { return nil }
        return normalizedLanguageCode(preferredIdentifier)
    }

    private var sourceLanguage: Locale.Language? {
        guard let detectedLanguageCode else { return nil }
        return Locale.Language(identifier: detectedLanguageCode)
    }

    private var targetLanguage: Locale.Language? {
        guard let preferredLanguageCode else { return nil }
        return Locale.Language(identifier: preferredLanguageCode)
    }

    private var shouldOfferTranslation: Bool {
        guard let detectedLanguageCode, let preferredLanguageCode else { return false }
        return normalizedLanguageCode(detectedLanguageCode) != preferredLanguageCode
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text)
                .font(.body)
                .foregroundStyle(.primary)

            if let translatedText, !translatedText.isEmpty {
                Text(translatedText)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
                    )
            }

            if shouldOfferTranslation && !hasSuccessfulTranslation {
                Button(action: startTranslation) {
                    Label("Translate", systemImage: "translate")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.accent)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.tactilePress(scale: 0.96))
                .padding(.vertical, -8)
            }

            if hasSuccessfulTranslation {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Translated on device with Apple Translate")
                        .foregroundStyle(.secondary)
                }
                .font(.footnote)
                .transition(.opacity)
            }

            if let translationError, !translationError.isEmpty {
                Text(translationError)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .translationTask(translationConfiguration) { session in
            do {
                let response = try await session.translate(text)
                await MainActor.run {
                    withAnimation(
                        BitLocalMotion.animation(BitLocalMotion.strongEaseOut, reduceMotion: reduceMotion)
                    ) {
                        translatedText = response.targetText
                        translationError = nil
                    }
                }
            } catch {
                await MainActor.run {
                    withAnimation(
                        BitLocalMotion.animation(BitLocalMotion.fastExit, reduceMotion: reduceMotion)
                    ) {
                        translationError = error.localizedDescription
                    }
                }
            }
        }
    }

    private func startTranslation() {
        guard let sourceLanguage, let targetLanguage else { return }
        BitLocalHaptics.selection()
        translationError = nil
        translationConfiguration = TranslationSession.Configuration(
            source: sourceLanguage,
            target: targetLanguage
        )
    }

    private func normalizedLanguageCode(_ identifier: String) -> String {
        let normalized = identifier.replacingOccurrences(of: "_", with: "-").lowercased()
        return normalized.split(separator: "-", maxSplits: 1).first.map(String.init) ?? normalized
    }
}

// MARK: - Verification & Boost Footer Section

private struct PlaceTrustAndBoostSection: View {
    let element: Element
    let verificationState: PlaceVerificationState
    @Environment(\.openURL) private var openURL

    private var btcMapMerchantURL: URL? {
        BTCMapMerchantURLBuilder.makeURL(for: element)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Verification")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            PlaceGroupedSurface(padding: EdgeInsets(top: 12, leading: 14, bottom: 10, trailing: 14)) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        if verificationState == .loading {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 20, height: 20)
                        } else {
                            Image(systemName: verificationState.icon)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(verificationState.tint)
                                .frame(width: 20, alignment: .center)
                                .padding(.top, 1)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(verificationState.detailTitle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            if let dateText = verificationState.formattedDate {
                                Text(
                                    String(
                                        format: NSLocalizedString("Last verified: %@", comment: "Verification status date label"),
                                        dateText
                                    )
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            } else if verificationState == .unverified {
                                Text("No one has confirmed this location yet.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Text(verificationState.explanation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 2)
                        }
                    }

                    if let btcMapMerchantURL {
                        Divider()
                            .padding(.leading, 32)

                        Button {
                            BitLocalHaptics.lightTap()
                            openURL(btcMapMerchantURL)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "star.fill")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.orange)
                                    .frame(width: 20, alignment: .center)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text("Boost on BTC Map")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Text("Feature This Merchant")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer(minLength: 0)

                                Image(systemName: "arrow.up.forward")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.tactileRow(cornerRadius: 10))
                    }
                }
            }

            if btcMapMerchantURL != nil {
                Text("Opening the link above will direct you to btcmap.org where you can boost this merchant. Boosted merchants are featured on BitLocal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Helpers

private struct ShareURLItem: Identifiable {
    let id = UUID()
    let url: URL
    let merchantName: String?
}

private struct ShareActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private extension View {
    @ViewBuilder
    func copyValueContextMenu(_ value: String?, title: String = "Copy") -> some View {
        if let value, !value.isEmpty {
            self.contextMenu {
                Button(title, systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = value
                    BitLocalHaptics.success()
                }
            }
        } else {
            self
        }
    }
}

private func urlForSocialHandle(_ value: String, base: String) -> URL? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
        return URL(string: trimmed)
    }
    let sanitized = trimmed.hasPrefix("@") ? String(trimmed.dropFirst()) : trimmed
    return URL(string: base + sanitized)
}

private extension String {
    func parsedBTCMapDate() -> Date? {
        BTCMapDateParser.parse(self)
    }

    func formattedBTCMapDate() -> String {
        if let date = parsedBTCMapDate() {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return self
    }
}
