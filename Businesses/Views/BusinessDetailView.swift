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

enum PlaceVerificationState: Equatable {
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
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL
    @State private var showingShareErrorAlert = false
    @State private var showingFeaturedInfo = false
    @State private var shareItem: ShareURLItem?
    @State private var isHeroScrolledPast = false
    @State private var hydratedVerifiedAt: String?
    @State private var isLoadingVerifiedAt = false
    @State private var hasAttemptedVerificationHydration = false
    @State var elementCellViewModel: ElementCellViewModel
    @Environment(ContentViewModel.self) var contentViewModel
    private let savedPlacesStore = SavedPlacesStore.shared

    @AppStorage("distanceUnit") private var distanceUnit: DistanceUnit = .auto

    var element: Element
    var userLocation: CLLocation?
    @Binding private var currentDetent: PresentationDetent?
    private let parsedOpeningSchedule: OSMOpeningHoursWeekSchedule?

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
        let rawHours = element.osmJSON?.tags?.openingHours?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.parsedOpeningSchedule = (rawHours?.isEmpty == false)
            ? rawHours.flatMap(OSMOpeningHoursParser.parseWeekSchedule)
            : nil
        self._elementCellViewModel = State(
            initialValue: ElementCellViewModel(
                element: element,
                userLocation: userLocation,
                viewModel: contentViewModel
            )
        )
    }

    private var displayName: String {
        _ = contentViewModel.merchantStoreRevision
        let liveElement = contentViewModel.merchantElementStore.element(id: element.id) ?? element
        return liveElement.displayNameForUI ?? NSLocalizedString("name_not_available", comment: "Fallback name when no name is available")
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

    private var verificationState: PlaceVerificationState {
        let raw = hydratedVerifiedAt ?? element.v4Metadata?.verifiedAt
        if let raw, let verifiedDate = raw.parsedBTCMapDate(),
           let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: .now) {
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
            useMetric = locale.measurementSystem == .metric
        case .miles:
            useMetric = false
        case .kilometers:
            useMetric = true
        }
        let measurement = useMetric
            ? Measurement(value: distanceInMeters / 1000, unit: UnitLength.kilometers)
            : Measurement(value: distanceInMeters / 1609.344, unit: UnitLength.miles)
        return measurement.formatted(
            .measurement(
                width: .abbreviated,
                usage: .asProvided,
                numberFormatStyle: .number.precision(.fractionLength(1))
            )
            .locale(locale)
        )
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
            elementCellViewModel.onDetailAppear()
        }
        .onDisappear {
            elementCellViewModel.onCellDisappear()
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
        } message: {
            Text("The place link could not be created.")
        }
        .alert("Featured Merchant", isPresented: $showingFeaturedInfo) {
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
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.24), lineWidth: 0.75)
                    }
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

                let isSaved = savedPlacesStore.isSaved(element.id)
                Button {
                    let willSave = !isSaved
                    withAnimation(BitLocalMotion.animation(BitLocalMotion.morphSpring, reduceMotion: reduceMotion)) {
                        savedPlacesStore.toggleSaved(element.id)
                    }
                    if willSave {
                        BitLocalHaptics.success()
                    } else {
                        BitLocalHaptics.selection()
                    }
                } label: {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isSaved ? Color.accentColor : Color.secondary)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 44, height: 44)
                        .background(.regularMaterial, in: Circle())
                        .overlay {
                            Circle()
                                .strokeBorder(Color(.separator).opacity(0.35), lineWidth: 0.5)
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.tactilePress(scale: 0.92))
                .accessibilityLabel(isSaved ? "Remove from Saved" : "Save Place")
            }

            // Quiet inline status metadata (no extra capsule clutter)
            if parsedOpeningSchedule != nil || verificationState != .loading || shouldShowFeaturedBadgeInExpandedContent {
                BitLocalFlowLayout(horizontalSpacing: 12, verticalSpacing: 0) {
                    if let schedule = parsedOpeningSchedule {
                        let status = OpeningHoursLiveStatus.evaluate(schedule: schedule, now: .now, calendar: calendar)
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
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.accentColor)
                } else {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(.regularMaterial)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        isPrimary ? Color.clear : Color(.separator).opacity(0.35),
                        lineWidth: 0.5
                    )
            }
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

extension View {
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

func urlForSocialHandle(_ value: String, base: String) -> URL? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
        return URL(string: trimmed)
    }
    let sanitized = trimmed.hasPrefix("@") ? String(trimmed.dropFirst()) : trimmed
    return URL(string: base + sanitized)
}

extension String {
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
