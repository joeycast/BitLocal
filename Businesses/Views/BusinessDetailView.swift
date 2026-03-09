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

@available(iOS 17.0, *)
struct BusinessDetailView: View {
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @State private var region = MKCoordinateRegion()
    @State private var showingShareErrorAlert = false
    @StateObject var elementCellViewModel: ElementCellViewModel
    @EnvironmentObject var contentViewModel: ContentViewModel
    
    @AppStorage("distanceUnit") private var distanceUnit: DistanceUnit = .auto
    
    var element: Element
    var userLocation: CLLocation?
    @Binding private var currentDetent: PresentationDetent?
    
    init(
        element: Element,
        userLocation: CLLocation?,
        contentViewModel: ContentViewModel,
        currentDetent: Binding<PresentationDetent?> = .constant(nil)
    ) {
        self.element = element
        self.userLocation = userLocation
        self._currentDetent = currentDetent
        self._elementCellViewModel = StateObject(wrappedValue: ElementCellViewModel(element: element, userLocation: userLocation, viewModel: contentViewModel))
    }
    
    fileprivate func localizedDistanceString() -> String? {
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
        List {
            BusinessDescriptionSection(element: element)
                .featuredHeader(isFeatured: element.isCurrentlyBoosted())
                .groupedCardListRowBackground(if: shouldUseGlassyRows)
            BusinessDetailsSection(
                element: element,
                elementCellViewModel: elementCellViewModel,
                isFirstVisibleSection: element.isCurrentlyBoosted() && !element.hasBusinessDescription
            )
                .groupedCardListRowBackground(if: shouldUseGlassyRows)
            BTCMapSocialsSection(element: element)
                .groupedCardListRowBackground(if: shouldUseGlassyRows)
            PaymentDetailsSection(element: element)
                .groupedCardListRowBackground(if: shouldUseGlassyRows)
            BTCMapRequiredAppSection(element: element)
                .groupedCardListRowBackground(if: shouldUseGlassyRows)
            BTCMapPlaceCommentsSection(element: element)
                .groupedCardListRowBackground(if: shouldUseGlassyRows)
            BTCMapVerificationSection(element: element)
                .groupedCardListRowBackground(if: shouldUseGlassyRows)
            BTCMapPaidActionsSection(element: element)
                .groupedCardListRowBackground(if: shouldUseGlassyRows)
            BusinessMapSection(element: element)
                .groupedCardListRowBackground(if: shouldUseGlassyRows)
        }
        .opacity(shouldShowCollapsedHeaderOnly ? 0 : 1)
        .allowsHitTesting(!shouldShowCollapsedHeaderOnly)
        .accessibilityHidden(shouldShowCollapsedHeaderOnly)
        .scrollContentBackground(shouldHideSheetBackground ? .hidden : .automatic)
        .onAppear {
            Debug.log("BusinessDetailView appeared for element: \(element.id)")
            Debug.log("ElementCellViewModel address: \(elementCellViewModel.address?.streetName ?? "nil")")
            elementCellViewModel.onCellAppear()
        }
        .listStyle(InsetGroupedListStyle()) // Consistent list style
        .navigationTitle(element.displayName ?? NSLocalizedString("name_not_available", comment: "Fallback name when no name is available"))
        .navigationBarTitleDisplayMode(horizontalSizeClass == .compact ? .inline : .inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                shareToolbarItem
            }
        }
        .alert("Unable to share this place", isPresented: $showingShareErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The place link could not be created.")
        }
    }
}

extension BusinessDetailView {
    @ViewBuilder
    private var shareToolbarItem: some View {
        if FeatureFlags.isSharePlaceLinksEnabled {
            if let shareURL = PlaceShareLinkBuilder.makeShareURL(forPlaceID: element.id) {
                ShareLink(
                    item: shareURL,
                    subject: Text("BitLocal Place"),
                    message: Text("Check out \(element.displayName ?? "this place") on BitLocal")
                ) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share place")
            } else {
                Button {
                    Debug.log("Share link generation failed for place id: \(element.id)")
                    showingShareErrorAlert = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share place")
            }
        }
    }

    private var shouldHideSheetBackground: Bool {
        guard let detent = currentDetent else { return false }
        return detent != .large
    }
    
    private var shouldUseGlassyRows: Bool {
        guard let detent = currentDetent else { return false }
        guard #available(iOS 26.0, *) else { return false }
        return detent != .large
    }

    private var shouldShowCollapsedHeaderOnly: Bool {
        guard let detent = currentDetent else { return false }
        return detentIdentifier(detent).contains("fraction 0.11")
    }

    private func detentIdentifier(_ detent: PresentationDetent) -> String {
        String(describing: detent).lowercased()
    }
}

struct BTCMapPlaceCommentsSection: View {
    let element: Element

    private var expectedCount: Int? { element.v4Metadata?.commentsCount }

    var body: some View {
        if shouldShowSection {
            Section(header: Text("Community Reviews")) {
                NavigationLink {
                    BTCMapPlaceCommentsListView(element: element)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(expectedCount ?? 0) review\((expectedCount ?? 0) == 1 ? "" : "s")")
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
    }

    private var shouldShowSection: Bool {
        (expectedCount ?? 0) > 0
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
                if #available(iOS 18.0, *) {
                    TranslatableReviewBodyTextView(text: comment.bodyText)
                } else {
                    Text(comment.bodyText)
                        .font(.body)
                        .foregroundStyle(.primary)
                }
            }

            if let sats = comment.amountSats, sats > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "bolt.fill")
                        .font(.caption2)
                    Text("~\(sats) sats")
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

@available(iOS 18.0, *)
private struct TranslatableReviewBodyTextView: View {
    let text: String

    @State private var translatedText: String?
    @State private var translationConfiguration: TranslationSession.Configuration?
    @State private var translationError: String?

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
            }

            if shouldOfferTranslation && !hasSuccessfulTranslation {
                Button(action: startTranslation) {
                    Label("Translate", systemImage: "translate")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
            }

            if hasSuccessfulTranslation {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Translated on device with Apple Translate")
                        .foregroundStyle(.secondary)
                }
                .font(.footnote)
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
                    translatedText = response.targetText
                    translationError = nil
                }
            } catch {
                await MainActor.run {
                    translationError = error.localizedDescription
                }
            }
        }
    }

    private func startTranslation() {
        guard let sourceLanguage, let targetLanguage else { return }
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

struct BTCMapPaidActionsSection: View {
    let element: Element
    
    private var btcMapMerchantURL: URL? {
        BTCMapMerchantURLBuilder.makeURL(for: element)
    }

    var body: some View {
        if let btcMapMerchantURL {
            Section(
                header: Text("Feature This Merchant"),
                footer: Text("Opening the link above will direct you to btcmap.org where you can boost this merchant. Boosted merchants are featured on BitLocal.")
            ) {
                Link(destination: btcMapMerchantURL) {
                    HStack(spacing: 12) {
                        Image(systemName: "star.circle.fill")
                            .foregroundStyle(.orange)
                            .frame(width: 18)

                        Text("Boost on BTC Map")
                            .foregroundStyle(.primary)

                        Spacer(minLength: 0)

                        Image(systemName: "arrow.up.forward")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct BTCMapSocialsSection: View {
    let element: Element

    private var metadata: ElementV4Metadata? { element.v4Metadata }

    private var socialLinks: [(label: String, icon: String, value: String, url: URL?)] {
        guard let metadata else { return [] }
        return [
            ("X", "xmark.circle.fill", metadata.twitter, metadata.twitter.flatMap { urlForSocialHandle($0, base: "https://twitter.com/") }),
            ("Facebook", "f.cursive.circle.fill", metadata.facebook, metadata.facebook.flatMap { urlForSocialHandle($0, base: "https://facebook.com/") }),
            ("Instagram", "camera.circle.fill", metadata.instagram, metadata.instagram.flatMap { urlForSocialHandle($0, base: "https://instagram.com/") }),
            ("Telegram", "paperplane.circle.fill", metadata.telegram, metadata.telegram.flatMap { urlForSocialHandle($0, base: "https://t.me/") }),
            ("LINE", "message.circle.fill", metadata.line, metadata.line.flatMap(URL.init(string:)))
        ].compactMap { item in
            guard let value = item.2?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
                return nil
            }
            return (item.0, item.1, value.cleanedForDisplay(), item.3)
        }
    }

    var body: some View {
        if hasContent {
            Section(header: Text("Socials")) {
                ForEach(socialLinks, id: \.label) { social in
                    if let url = social.url {
                        Link(destination: url) {
                            businessLinkValueRow(icon: social.icon, label: social.label, value: social.value)
                        }
                        .buttonStyle(.plain)
                    } else {
                        businessLinkValueRow(icon: social.icon, label: social.label, value: social.value)
                    }
                }

            }
        }
    }

    private var hasContent: Bool {
        guard let metadata else { return false }
        return [
            metadata.twitter,
            metadata.facebook,
            metadata.instagram,
            metadata.telegram,
            metadata.line
        ].contains { ($0?.isEmpty == false) }
    }

}

struct BTCMapRequiredAppSection: View {
    let element: Element

    private var requiredAppURL: String? { element.v4Metadata?.requiredAppURL }

    var body: some View {
        if let requiredAppURL,
           !requiredAppURL.isEmpty,
           let url = URL(string: requiredAppURL) {
            Section(header: Text("Required App")) {
                Link(destination: url) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "app.badge.fill")
                                .foregroundStyle(.orange)
                            Text("Required App")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Text(requiredAppURL)
                            .font(.footnote)
                            .foregroundStyle(.accent)
                            .lineLimit(2)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct BTCMapVerificationSection: View {
    let element: Element

    @State private var hydratedVerifiedAt: String?
    @State private var isLoadingVerifiedAt = false
    @State private var hasAttemptedHydration = false

    private let repository: BTCMapRepositoryProtocol = BTCMapRepository.shared
    private var metadata: ElementV4Metadata? { element.v4Metadata }
    private var effectiveVerifiedAt: String? { hydratedVerifiedAt ?? metadata?.verifiedAt }

    private enum VerificationStatus {
        case verified
        case outdated

        var icon: String {
            switch self {
            case .verified:
                return "checkmark.seal.fill"
            case .outdated:
                return "exclamationmark.triangle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .verified:
                return .green
            case .outdated:
                return .orange
            }
        }

        var title: LocalizedStringKey {
            switch self {
            case .verified:
                return "Verified"
            case .outdated:
                return "Not Recently Verified"
            }
        }

        var explanation: LocalizedStringKey {
            switch self {
            case .verified:
                return "Someone physically confirmed this place accepts bitcoin within the past year."
            case .outdated:
                return "It has been more than a year since someone reported that this location accepts bitcoin. It likely still does, but no one has confirmed so recently."
            }
        }
    }

    private var verifiedDate: Date? {
        guard let raw = effectiveVerifiedAt else { return nil }
        return raw.parsedBTCMapDate()
    }

    private var verifiedDateText: String? {
        guard let verifiedDate else { return nil }
        return verifiedDate.formatted(date: .abbreviated, time: .omitted)
    }

    private var status: VerificationStatus? {
        guard let verifiedDate else { return nil }
        guard let oneYearAgo = Calendar.current.date(byAdding: .year, value: -1, to: Date()) else {
            return nil
        }
        return verifiedDate > oneYearAgo ? .verified : .outdated
    }

    var body: some View {
        Section(header: Text("Verification")) {
            if let status, let verifiedDateText {
                detailRow(icon: status.icon, tint: status.tint, label: status.title, value: LocalizedStringKey("Last verified: \(verifiedDateText)"))
                Text(status.explanation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if isLoadingVerifiedAt {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading verification status…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                detailRow(
                    icon: "questionmark.circle.fill",
                    tint: .secondary,
                    label: "Not Yet Verified",
                    value: "No one has confirmed this location yet."
                )
                Text("This place was added to BitLocal but hasn't been physically checked by a community member.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            hydrateVerificationIfNeeded()
        }
    }

    private func detailRow(icon: String, tint: Color, label: LocalizedStringKey, value: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(value)
                    .foregroundStyle(.primary)
            }
        }
    }

    private func hydrateVerificationIfNeeded() {
        guard effectiveVerifiedAt == nil else { return }
        guard !isLoadingVerifiedAt else { return }
        guard !hasAttemptedHydration else { return }

        hasAttemptedHydration = true
        isLoadingVerifiedAt = true

        repository.fetchPlace(id: element.id) { result in
            DispatchQueue.main.async {
                if case .success(let record) = result, let verifiedAt = record.verifiedAt, !verifiedAt.isEmpty {
                    hydratedVerifiedAt = verifiedAt
                }
                isLoadingVerifiedAt = false
            }
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

// BusinessDescriptionSection
struct BusinessDescriptionSection: View {
    var element: Element
    
    var body: some View {
        if let description = element.osmJSON?.tags?.description ?? element.osmJSON?.tags?.descriptionEn {
            Section(header: businessSectionHeader(
                NSLocalizedString("business_description_section", comment: "Section header for business description")
            )) {
                if #available(iOS 18.0, *) {
                    TranslatableBusinessDescriptionView(description: description)
                } else {
                    Text(description)
                }
            }
        } else {
        }
    }
}

@available(iOS 18.0, *)
private struct TranslatableBusinessDescriptionView: View {
    let description: String

    @State private var translatedDescription: String?
    @State private var translationConfiguration: TranslationSession.Configuration?
    @State private var translationError: String?
    
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

            if let translatedDescription, !translatedDescription.isEmpty {
                Text(translatedDescription)
                    .foregroundStyle(.secondary)
            }

            if shouldOfferTranslation && !hasSuccessfulTranslation {
                Button(action: startTranslation) {
                    Label("Translate", systemImage: "translate")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
            }
            
            if hasSuccessfulTranslation {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Translated on device with Apple Translate")
                        .foregroundStyle(.secondary)
                }
                .font(.footnote)
            }

            if let translationError, !translationError.isEmpty {
                Text(translationError)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .translationTask(translationConfiguration) { session in
            do {
                let response = try await session.translate(description)
                await MainActor.run {
                    translatedDescription = response.targetText
                    translationError = nil
                }
            } catch {
                await MainActor.run {
                    translationError = error.localizedDescription
                }
            }
        }
    }

    private func startTranslation() {
        guard let sourceLanguage, let targetLanguage else { return }
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

// Business Details Section
@available(iOS 17.0, *)
struct BusinessDetailsSection: View {
    var element: Element
    @ObservedObject var elementCellViewModel: ElementCellViewModel
    var isFirstVisibleSection = false
    
    var body: some View {
        Section(header: businessSectionHeader(
            NSLocalizedString("business_details_section", comment: "Section header for business details"),
            includesFeaturedBadge: isFirstVisibleSection
        )) {
            // Business Address
            if let coord = element.mapCoordinate {
                Button(action: {
                    openLocationInMaps(coordinate: coord, name: element.displayName, address: elementCellViewModel.address)
                }) {
                    businessLinkValueRow(
                        icon: "map",
                        label: NSLocalizedString("address_label", comment: "Label for address"),
                        value: addressDisplayText,
                        valueLineLimit: 3
                    )
                }
                .buttonStyle(.plain)
            }
            
            // Business Website - Only show if valid
            if let website = element.osmJSON?.tags?.website ?? element.osmJSON?.tags?.contactWebsite,
               let validURL = website.cleanedWebsiteURL() {

                Link(destination: validURL) {
                    businessLinkValueRow(
                        icon: "globe",
                        label: NSLocalizedString("website_label", comment: "Label for website"),
                        value: website.cleanedForDisplay()
                    )
                }
                .buttonStyle(.plain)
            }
            
            // Business Phone - Simple worldwide approach
            if let phone = element.osmJSON?.tags?.phone ?? element.osmJSON?.tags?.contactPhone {
                let (cleanPhone, isValid) = phone.cleanedPhoneNumber()

                if isValid, let url = URL(string: "tel:\(cleanPhone)") {
                    Link(destination: url) {
                        businessLinkValueRow(
                            icon: "phone.fill",
                            label: NSLocalizedString("phone_label", comment: "Label for phone"),
                            value: phone.displayablePhoneNumber()
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    let _ = Debug.log("Invalid phone number: '\(phone)'")
                }
            }

            // Business Email
            if let email = element.v4Metadata?.email,
               !email.isEmpty,
               let url = URL(string: "mailto:\(email)") {
                Link(destination: url) {
                    businessLinkValueRow(
                        icon: "envelope.fill",
                        label: "Email",
                        value: email
                    )
                }
                .buttonStyle(.plain)
            }
            
            // Opening Hours
            if let openingHours = element.osmJSON?.tags?.openingHours {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "clock.fill")
                        .foregroundStyle(.accent)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(NSLocalizedString("opening_hours_label", comment: "Label for opening hours"))
                            .foregroundStyle(.accent)
                        OpeningHoursDisplayView(rawOpeningHours: openingHours)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

        }
    }
}

private func businessLinkValueRow(
    icon: String,
    label: String,
    value: String,
    valueLineLimit: Int = 2
) -> some View {
    HStack(alignment: .top, spacing: 12) {
        Image(systemName: icon)
            .foregroundStyle(.accent)
            .frame(width: 18)
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .foregroundStyle(.accent)
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(valueLineLimit)
                .multilineTextAlignment(.leading)
        }
        Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(.rect)
}

private extension BusinessDetailsSection {
    var addressDisplayText: String {
        let streetNumber = elementCellViewModel.address?.streetNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let streetName = elementCellViewModel.address?.streetName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let streetLine = [streetNumber, streetName]
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        let city = elementCellViewModel.address?.cityOrTownName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let region = elementCellViewModel.address?.regionOrStateName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let postalCode = elementCellViewModel.address?.postalCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let localityParts = [city, region]
            .filter { !$0.isEmpty }
        let locality = localityParts.joined(separator: ", ")
        let secondLine = [locality, postalCode]
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return [streetLine, secondLine]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

private extension View {
    @ViewBuilder
    func featuredHeader(isFeatured: Bool) -> some View {
        self
            .environment(\.businessSectionShowsFeaturedBadge, isFeatured)
    }
}

private extension Element {
    var hasBusinessDescription: Bool {
        let description = osmJSON?.tags?.description ?? osmJSON?.tags?.descriptionEn
        guard let description else { return false }
        return !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct BusinessSectionShowsFeaturedBadgeKey: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    var businessSectionShowsFeaturedBadge: Bool {
        get { self[BusinessSectionShowsFeaturedBadgeKey.self] }
        set { self[BusinessSectionShowsFeaturedBadgeKey.self] = newValue }
    }
}

private struct BusinessSectionHeader: View {
    let title: String
    var includesFeaturedBadge = false

    @Environment(\.businessSectionShowsFeaturedBadge) private var showsFeaturedBadge

    private var shouldShowBadge: Bool {
        includesFeaturedBadge || showsFeaturedBadge
    }

    var body: some View {
        VStack(alignment: .leading, spacing: shouldShowBadge ? 10 : 0) {
            if shouldShowBadge {
                HStack {
                    Spacer(minLength: 0)
                    Label("Featured Merchant", systemImage: "star.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(red: 0.71, green: 0.49, blue: 0.08))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color(red: 0.96, green: 0.93, blue: 0.84))
                        )
                    Spacer(minLength: 0)
                }
                .padding(.bottom, -2)
            }

            Text(title)
        }
        .padding(.top, shouldShowBadge ? -4 : 0)
    }
}

private func businessSectionHeader(_ title: String, includesFeaturedBadge: Bool = false) -> some View {
    BusinessSectionHeader(title: title, includesFeaturedBadge: includesFeaturedBadge)
}

private struct OpeningHoursDisplayView: View {
    let rawOpeningHours: String

    private var parsedSchedule: OSMOpeningHoursWeekSchedule? {
        OSMOpeningHoursParser.parseWeekSchedule(rawOpeningHours)
    }
    
    private var todayWeekday: WeeklyHours.Weekday {
        switch Calendar.current.component(.weekday, from: Date()) {
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

    var body: some View {
        if let parsedSchedule {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(parsedSchedule.days, id: \.weekday) { day in
                    HStack(alignment: .top, spacing: 12) {
                        Text(shortWeekdayLabel(for: day.weekday))
                            .fontWeight(day.weekday == todayWeekday ? .semibold : .regular)
                            .foregroundStyle(day.weekday == todayWeekday ? .primary : .secondary)
                            .lineLimit(1)
                            .frame(width: 36, alignment: .leading)

                        hoursText(for: day)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else {
            Text(rawOpeningHours)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
    }

    @ViewBuilder
    private func hoursText(for day: OSMOpeningHoursDaySchedule) -> some View {
        if day.ranges.isEmpty {
            Text(NSLocalizedString("hours_closed", comment: "Closed label for business hours"))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
            .font(.body)
            .fontWeight(day.weekday == todayWeekday ? .semibold : .regular)
            .foregroundStyle(.secondary)
        } else if day.ranges.count == 1, day.ranges[0].isAllDay {
            Text("24/7")
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
            .font(.body)
            .fontWeight(day.weekday == todayWeekday ? .semibold : .regular)
            .foregroundStyle(.primary)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(day.ranges.enumerated()), id: \.offset) { _, range in
                    Text(formattedTime(range.startMinutes) + " \u{2013} " + formattedTime(range.endMinutes))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    .font(.body)
                    .fontWeight(day.weekday == todayWeekday ? .semibold : .regular)
                    .foregroundStyle(.primary)
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


// Payment Details Section
struct PaymentDetailsSection: View {
    var element: Element
    
    var body: some View {
        Section(header: Text(NSLocalizedString("payment_details_section", comment: "Section header for payment details"))) {
            // Accepts Bitcoin (details regarding on chain/lightning/contactless lightning not available)
            if acceptsBitcoin(element: element) {
                HStack {
                    Image(systemName: "bitcoinsign.circle.fill")
                        .foregroundColor(.accentColor)
                    Text(NSLocalizedString("accepts_bitcoin", comment: "Label for accepting Bitcoin"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            
            // Business Accepts Bitcoin
            if acceptsBitcoinOnChain(element: element) {
                HStack {
                    Image(systemName: "bitcoinsign.circle.fill")
                        .foregroundColor(.accentColor)
                    Text(NSLocalizedString("accepts_bitcoin_onchain", comment: "Label for accepting Bitcoin on Chain"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            
            // Business Accepts Lightning
            if acceptsLightning(element: element) {
                HStack {
                    Image(systemName: "bolt.circle.fill")
                        .foregroundColor(.accentColor)
                    Text(NSLocalizedString("accepts_bitcoin_lightning", comment: "Label for accepting Bitcoin over Lightning"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            if acceptsContactlessLightning(element: element) {
                HStack {
                    Image(systemName: "wave.3.right.circle.fill")
                        .foregroundColor(.accentColor)
                    Text(NSLocalizedString("accepts_contactless_lightning", comment: "Label for accepting Contactless Lightning"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
        }
    }
}

// BusinessMapSection
struct BusinessMapSection: View {
    var element: Element
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    var body: some View {
        BusinessMiniMapView(element: element)
            .frame(height: horizontalSizeClass == .compact ? 200 : 300) // Adjust height based on device
            .cornerRadius(10)
    }
}

// Map View
// TODO: Refactor to reuse annotation customization code from ContentViewModel
struct BusinessMiniMapView: UIViewRepresentable {
    var element: Element
    
    // Read the persisted map type using AppStorage.
    // This value is stored as an Int (the rawValue of MKMapType)
    @AppStorage("selectedMapType") private var storedMapType: Int = Int(MKMapType.standard.rawValue)
    
    // Convert the stored integer back to MKMapType
    var mapType: MKMapType {
        MKMapType(rawValue: UInt(storedMapType)) ?? .standard
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        
        // Set the map type based on the persisted value
        mapView.mapType = mapType
        
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        // Update map type if it has changed
        if uiView.mapType != mapType {
            uiView.mapType = mapType
        }
        updateAnnotations(from: uiView)
    }
    
    private func updateAnnotations(from mapView: MKMapView) {
        mapView.removeAnnotations(mapView.annotations)
        
        let annotation = Annotation(element: element)
        mapView.addAnnotation(annotation)
        
        let coordinate = annotation.coordinate
        let region = MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005))
        mapView.setRegion(region, animated: true)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: BusinessMiniMapView
        
        init(_ parent: BusinessMiniMapView) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            let reuseIdentifier = "AnnotationView"
            var view: MKMarkerAnnotationView?
            
            if let annotation = annotation as? Annotation {
                view = mapView.dequeueReusableAnnotationView(withIdentifier: reuseIdentifier) as? MKMarkerAnnotationView ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: reuseIdentifier)
                view?.canShowCallout = true
                view?.glyphText = nil
                view?.glyphTintColor = .white
                if let element = annotation.element {
                    view?.markerTintColor = element.isCurrentlyBoosted() ? .systemOrange : UIColor(named: "MarkerColor")
                    let symbolName = ElementCategorySymbols.symbolName(for: element)
                    Debug.logMap("MiniMap: Rendering annotation for \(element.osmJSON?.tags?.name ?? "unknown") amenity=\(element.osmTagsDict?["amenity"] ?? "none"), symbol=\(symbolName)")
                    view?.glyphImage = UIImage(systemName: symbolName)?.withTintColor(.white, renderingMode: .alwaysOriginal)
                } else {
                    view?.markerTintColor = UIColor(named: "MarkerColor")
                }
                view?.displayPriority = .required
            }
            return view
        }
    }
}

// Troubleshooting Section
//struct TroubleshootingSection: View {
//    var element: Element
//
//    var body: some View {
//        Section(header: Text("Troubleshooting")) {
//            Text("ID: \(element.id)")
//            Text("Created at: \(element.createdAt)")
//            Text("Updated at: \(element.updatedAt ?? "")")
//            Text("Deleted at: \(element.deletedAt ?? "")")
//            Text("Description: \(element.osmJSON?.tags?.description ?? "")")
//            Text("Phone: \(element.osmJSON?.tags?.phone ?? "")")
//            Text("Contact:Phone: \(element.osmJSON?.tags?.contactPhone ?? "")")
//            Text("Website: \(element.osmJSON?.tags?.website ?? "")")
//            Text("Contact:Website: \(element.osmJSON?.tags?.contactWebsite ?? "")")
//            Text("Opening Hours: \(element.osmJSON?.tags?.openingHours ?? "")")
//            Text("Accepts payment:bitcoin: \(element.osmJSON?.tags?.paymentBitcoin ?? "no")")
//            Text("Accepts currency:XBT: \(element.osmJSON?.tags?.currencyXBT ?? "no")")
//            Text("Accepts Bitcoin on Chain: \(element.osmJSON?.tags?.paymentOnchain ?? "no")")
//            Text("Accepts Lightning: \(element.osmJSON?.tags?.paymentLightning ?? "no")")
//            Text("Accepts Contactless Lightning: \(element.osmJSON?.tags?.paymentLightningContactless ?? "no")")
//            Text("House Number: \(element.osmJSON?.tags?.addrHousenumber ?? "")")
//            Text("Street: \(element.osmJSON?.tags?.addrStreet ?? "")")
//            Text("City: \(element.osmJSON?.tags?.addrCity ?? "")")
//            Text("State: \(element.osmJSON?.tags?.addrState ?? "")")
//            Text("Post Code: \(element.osmJSON?.tags?.addrPostcode ?? "")")
//        }
//    }
//}
