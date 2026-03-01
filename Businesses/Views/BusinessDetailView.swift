// BusinessDetailView.swift

import SwiftUI
import CoreLocation
import MapKit
import Contacts
import Foundation
import UIKit

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
    @StateObject var elementCellViewModel: ElementCellViewModel
    @EnvironmentObject var contentViewModel: ContentViewModel
    
    @AppStorage("distanceUnit") private var distanceUnit: DistanceUnit = .auto
    
    var element: Element
    var userLocation: CLLocation?
    var currentDetent: PresentationDetent?
    
    init(
        element: Element,
        userLocation: CLLocation?,
        contentViewModel: ContentViewModel,
        currentDetent: PresentationDetent? = nil
    ) {
        self.element = element
        self.userLocation = userLocation
        self.currentDetent = currentDetent
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
                .clearListRowBackground(if: shouldUseGlassyRows)
            BusinessDetailsSection(
                element: element,
                elementCellViewModel: elementCellViewModel
            )
                .clearListRowBackground(if: shouldUseGlassyRows)
            BTCMapSocialsSection(element: element)
                .clearListRowBackground(if: shouldUseGlassyRows)
            PaymentDetailsSection(element: element)
                .clearListRowBackground(if: shouldUseGlassyRows)
            BTCMapRequiredAppSection(element: element)
                .clearListRowBackground(if: shouldUseGlassyRows)
            BTCMapPhotoSection(element: element)
                .clearListRowBackground(if: shouldUseGlassyRows)
            BTCMapPlaceCommentsSection(element: element)
                .clearListRowBackground(if: shouldUseGlassyRows)
            BTCMapVerificationSection(element: element)
                .clearListRowBackground(if: shouldUseGlassyRows)
            BTCMapPaidActionsSection(element: element)
                .clearListRowBackground(if: shouldUseGlassyRows)
            BusinessMapSection(element: element)
                .clearListRowBackground(if: shouldUseGlassyRows)
        }
        .scrollContentBackground(shouldHideSheetBackground ? .hidden : .automatic)
        .onAppear {
            Debug.log("BusinessDetailView appeared for element: \(element.id)")
            Debug.log("ElementCellViewModel address: \(elementCellViewModel.address?.streetName ?? "nil")")
            elementCellViewModel.updateAddress()
        }
        .listStyle(InsetGroupedListStyle()) // Consistent list style
        .navigationTitle(element.displayName ?? NSLocalizedString("name_not_available", comment: "Fallback name when no name is available"))
        .navigationBarTitleDisplayMode(horizontalSizeClass == .compact ? .inline : .inline)
    }
}

extension BusinessDetailView {
    private var shouldHideSheetBackground: Bool {
        guard let detent = currentDetent else { return false }
        return detent != .large
    }
    
    private var shouldUseGlassyRows: Bool {
        guard let detent = currentDetent else { return false }
        guard #available(iOS 26.0, *) else { return false }
        return detent != .large
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
                Text(comment.bodyText)
                    .font(.body)
                    .foregroundStyle(.primary)
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

struct BTCMapPaidActionsSection: View {
    let element: Element

    @State private var commentQuoteSat: Int?
    @State private var boostQuote: V4PlaceBoostQuote?
    @State private var commentDraft = ""
    @State private var isLoadingQuotes = false
    @State private var isSubmitting = false
    @State private var actionError: String?
    @State private var invoice: V4InvoiceOrderResponse?
    @State private var invoiceStatus: String?
    @State private var pollTask: Task<Void, Never>?

    private let repository = BTCMapRepository.shared

    var body: some View {
        Section(header: Text("Boost This Listing")) {
            DisclosureGroup("Boost or comment on this listing") {
                if let invoice {
                    invoiceStatusBlock(invoice)
                }

                if isLoadingQuotes {
                    HStack {
                        ProgressView()
                        Text("Loading pricing…")
                            .foregroundColor(.secondary)
                    }
                } else {
                    if commentQuoteSat != nil || boostQuote != nil {
                        commentPurchaseBlock
                        boostPurchaseBlock
                    } else {
                        Button {
                            loadQuotes()
                        } label: {
                            Label("Load pricing", systemImage: "bolt.fill")
                        }
                    }
                }

                if let actionError, !actionError.isEmpty {
                    Label(actionError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.subheadline)
                }
            }
        }
        .onDisappear {
            pollTask?.cancel()
        }
    }

    @ViewBuilder
    private var commentPurchaseBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Leave a Review")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let commentQuoteSat {
                    HStack(spacing: 2) {
                        Image(systemName: "bolt.fill")
                            .font(.caption2)
                        Text("~\(commentQuoteSat) sats")
                            .font(.caption)
                    }
                    .foregroundColor(.orange)
                }
            }

            TextField("Write a review…", text: $commentDraft, axis: .vertical)
                .lineLimit(2...4)
                .textInputAutocapitalization(.sentences)
                .padding(10)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(.rect(cornerRadius: 10))

            Button {
                submitPaidComment()
            } label: {
                Label("Submit Review", systemImage: "bolt.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSubmitting || commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var boostPurchaseBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Boost Listing")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 8) {
                boostButton(days: 30, label: "30 days", sats: boostQuote?.quote30dSat)
                boostButton(days: 90, label: "90 days", sats: boostQuote?.quote90dSat)
                boostButton(days: 365, label: "1 year", sats: boostQuote?.quote365dSat)
            }
        }
    }

    private func boostButton(days: Int, label: String, sats: Int?) -> some View {
        Button {
            submitBoost(days: days)
        } label: {
            VStack(spacing: 2) {
                Text(label)
                    .font(.caption.weight(.semibold))
                if let sats {
                    HStack(spacing: 1) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 8))
                        Text("~\(sats)")
                            .font(.caption2)
                    }
                } else {
                    Text("—")
                        .font(.caption2)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background((sats == nil ? Color.gray : Color.orange).opacity(0.1))
            .clipShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(isSubmitting || sats == nil)
        .opacity((isSubmitting || sats == nil) ? 0.6 : 1.0)
    }

    @ViewBuilder
    private func invoiceStatusBlock(_ invoice: V4InvoiceOrderResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundColor(.orange)
                Text("Invoice")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(invoiceStatus ?? "pending")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.12))
                    .foregroundColor(statusColor)
                    .clipShape(Capsule())
            }

            HStack {
                Text(String(invoice.invoice.prefix(24)) + "…")
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer()
                Button {
                    UIPasteboard.general.string = invoice.invoice
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(10)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(.rect(cornerRadius: 10))

            Button("Refresh Status") {
                refreshInvoiceStatus()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isSubmitting)
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        let normalized = (invoiceStatus ?? "").lowercased()
        if normalized.contains("paid") || normalized.contains("settled") || normalized.contains("complete") {
            return .green
        }
        if normalized.contains("expired") || normalized.contains("failed") || normalized.contains("cancel") {
            return .red
        }
        return .orange
    }

    private func loadQuotes() {
        guard !isLoadingQuotes else { return }
        isLoadingQuotes = true
        actionError = nil

        let group = DispatchGroup()
        var loadedCommentQuote: Int?
        var loadedBoostQuote: V4PlaceBoostQuote?
        var firstError: Error?

        group.enter()
        repository.fetchPlaceCommentQuote { result in
            if case .success(let quote) = result {
                loadedCommentQuote = quote.quoteSat
            } else if case .failure(let error) = result, firstError == nil {
                firstError = error
            }
            group.leave()
        }

        group.enter()
        repository.fetchPlaceBoostQuote { result in
            if case .success(let quote) = result {
                loadedBoostQuote = quote
            } else if case .failure(let error) = result, firstError == nil {
                firstError = error
            }
            group.leave()
        }

        group.notify(queue: .main) {
            isLoadingQuotes = false
            commentQuoteSat = loadedCommentQuote
            boostQuote = loadedBoostQuote
            if let firstError {
                actionError = firstError.localizedDescription
            }
        }
    }

    private func submitPaidComment() {
        let trimmed = commentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSubmitting = true
        actionError = nil
        repository.createPlaceComment(placeID: element.id, comment: trimmed) { result in
            DispatchQueue.main.async {
                isSubmitting = false
                switch result {
                case .success(let invoiceResponse):
                    invoice = invoiceResponse
                    invoiceStatus = "pending"
                    startInvoicePolling(invoiceID: invoiceResponse.invoiceID)
                case .failure(let error):
                    actionError = error.localizedDescription
                }
            }
        }
    }

    private func submitBoost(days: Int) {
        isSubmitting = true
        actionError = nil
        repository.createPlaceBoost(placeID: element.id, days: days) { result in
            DispatchQueue.main.async {
                isSubmitting = false
                switch result {
                case .success(let invoiceResponse):
                    invoice = invoiceResponse
                    invoiceStatus = "pending"
                    startInvoicePolling(invoiceID: invoiceResponse.invoiceID)
                case .failure(let error):
                    actionError = error.localizedDescription
                }
            }
        }
    }

    private func refreshInvoiceStatus() {
        guard let invoiceID = invoice?.invoiceID else { return }
        repository.fetchInvoice(id: invoiceID) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let record):
                    invoiceStatus = record.status
                case .failure(let error):
                    actionError = error.localizedDescription
                }
            }
        }
    }

    private func startInvoicePolling(invoiceID: String) {
        pollTask?.cancel()
        pollTask = Task {
            for _ in 0..<40 {
                if Task.isCancelled { return }
                await withCheckedContinuation { continuation in
                    repository.fetchInvoice(id: invoiceID) { result in
                        DispatchQueue.main.async {
                            switch result {
                            case .success(let record):
                                invoiceStatus = record.status
                                let normalized = record.status.lowercased()
                                if normalized.contains("paid") || normalized.contains("settled") || normalized.contains("complete") || normalized.contains("expired") || normalized.contains("failed") || normalized.contains("cancel") {
                                    continuation.resume()
                                    return
                                }
                            case .failure(let error):
                                actionError = error.localizedDescription
                            }
                            continuation.resume()
                        }
                    }
                }

                let status = (invoiceStatus ?? "").lowercased()
                if status.contains("paid") || status.contains("settled") || status.contains("complete") || status.contains("expired") || status.contains("failed") || status.contains("cancel") {
                    break
                }

                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }
}

struct BTCMapSocialsSection: View {
    let element: Element

    private var metadata: ElementV4Metadata? { element.v4Metadata }

    private var socialLinks: [(label: String, value: String, url: URL?)] {
        guard let metadata else { return [] }
        return [
            ("Twitter", metadata.twitter, metadata.twitter.flatMap { urlForSocialHandle($0, base: "https://twitter.com/") }),
            ("Facebook", metadata.facebook, metadata.facebook.flatMap { urlForSocialHandle($0, base: "https://facebook.com/") }),
            ("Instagram", metadata.instagram, metadata.instagram.flatMap { urlForSocialHandle($0, base: "https://instagram.com/") }),
            ("Telegram", metadata.telegram, metadata.telegram.flatMap { urlForSocialHandle($0, base: "https://t.me/") }),
            ("LINE", metadata.line, metadata.line.flatMap(URL.init(string:)))
        ].compactMap { item in
            guard let value = item.1?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
                return nil
            }
            return (item.0, value, item.2)
        }
    }

    var body: some View {
        if hasContent {
            Section(header: Text("Socials")) {
                ForEach(socialLinks, id: \.label) { social in
                    if let url = social.url {
                        Link(destination: url) {
                            textLinkRow(icon: "link", label: social.label, value: social.value)
                        }
                        .buttonStyle(.plain)
                    } else {
                        textLinkRow(icon: "link", label: social.label, value: social.value)
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

    private func textLinkRow(icon: String, label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(.accentColor)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(value)
                    .foregroundColor(.accentColor)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
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

struct BTCMapPhotoSection: View {
    let element: Element

    private var imageURL: URL? {
        guard let raw = element.v4Metadata?.imageURL else { return nil }
        return URL(string: raw)
    }

    var body: some View {
        if let imageURL {
            Section(header: Text("Photo")) {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(height: 180)
                            .frame(maxWidth: .infinity)
                            .clipShape(.rect(cornerRadius: 12))
                    case .failure:
                        Text("Photo unavailable")
                            .foregroundStyle(.secondary)
                    case .empty:
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                            ProgressView()
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 120)
                    @unknown default:
                        EmptyView()
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
        }
    }
}

struct BTCMapVerificationSection: View {
    let element: Element

    private var metadata: ElementV4Metadata? { element.v4Metadata }

    private var verifiedDateText: String? {
        guard let raw = metadata?.verifiedAt else { return nil }
        return raw.formattedBTCMapDate()
    }

    var body: some View {
        if hasContent {
            Section(header: Text("Verification")) {
                if let verifiedDateText {
                    detailRow(icon: "checkmark.seal.fill", tint: .green, label: "Verified", value: verifiedDateText)
                }
            }
        }
    }

    private var hasContent: Bool {
        verifiedDateText != nil
    }

    private func detailRow(icon: String, tint: Color, label: String, value: String) -> some View {
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
    func formattedBTCMapDate() -> String {
        if let date = ISO8601DateFormatter.fullPrecision.date(from: self) ?? ISO8601DateFormatter().date(from: self) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return self
    }
}

private extension ISO8601DateFormatter {
    static let fullPrecision: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

// BusinessDescriptionSection
struct BusinessDescriptionSection: View {
    var element: Element
    
    var body: some View {
        if let description = element.osmJSON?.tags?.description ?? element.osmJSON?.tags?.descriptionEn {
            Section(header: Text(NSLocalizedString("business_description_section", comment: "Section header for business description"))) {
                Text(description)
            }
        } else {
        }
    }
}

// Business Details Section
@available(iOS 17.0, *)
struct BusinessDetailsSection: View {
    var element: Element
    @ObservedObject var elementCellViewModel: ElementCellViewModel
    
    var body: some View {
        Section(header: Text(NSLocalizedString("business_details_section", comment: "Section header for business details"))) {
            // Business Address
            if let coord = element.mapCoordinate {
                Button(action: {
                    openLocationInMaps(coordinate: coord, name: element.displayName, address: elementCellViewModel.address)
                }) {
                    VStack (alignment: .leading, spacing: 3) {
                        HStack {
                            Text(NSLocalizedString("address_label", comment: "Label for address"))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text("\(elementCellViewModel.address?.streetNumber != nil && !elementCellViewModel.address!.streetNumber!.isEmpty ? elementCellViewModel.address!.streetNumber! + " " : "")\(elementCellViewModel.address?.streetName ?? "")\n\(elementCellViewModel.address?.cityOrTownName ?? "")\(elementCellViewModel.address?.cityOrTownName != nil && elementCellViewModel.address?.cityOrTownName != "" ? ", " : "")\(elementCellViewModel.address?.regionOrStateName ?? "") \(elementCellViewModel.address?.postalCode ?? "")")
                                .multilineTextAlignment(.leading)
                                .foregroundColor(.accentColor)

                            Spacer()
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            
            // Business Website - Only show if valid
            if let website = element.osmJSON?.tags?.website ?? element.osmJSON?.tags?.contactWebsite,
               let validURL = website.cleanedWebsiteURL() {

                Link(destination: validURL) {
                    VStack (alignment: .leading, spacing: 3) {
                        HStack {
                            Text(NSLocalizedString("website_label", comment: "Label for website"))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Text(website.cleanedForDisplay())
                                .lineLimit(1)
                                .foregroundColor(.accentColor)

                            Spacer()
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            
            // Business Phone - Simple worldwide approach
            if let phone = element.osmJSON?.tags?.phone ?? element.osmJSON?.tags?.contactPhone {
                let (cleanPhone, isValid) = phone.cleanedPhoneNumber()

                if isValid, let url = URL(string: "tel:\(cleanPhone)") {
                    Link(destination: url) {
                        VStack (alignment: .leading, spacing: 3) {
                            HStack {
                                Text(NSLocalizedString("phone_label", comment: "Label for phone"))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            HStack {
                                Text(phone.displayablePhoneNumber()) // Show original with minimal cleanup
                                    .lineLimit(1)
                                    .foregroundColor(.accentColor)

                                Spacer()
                            }
                        }
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
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("Email")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Text(email)
                                .lineLimit(1)
                                .foregroundStyle(.accent)
                            Spacer()
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            
            // Opening Hours
            if let openingHours = element.osmJSON?.tags?.openingHours {
                VStack (alignment: .leading, spacing: 3) {
                    Text(NSLocalizedString("opening_hours_label", comment: "Label for opening hours"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text(openingHours)
                }
            }
        }
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
                view?.markerTintColor = UIColor(named: "MarkerColor")
                view?.glyphText = nil
                view?.glyphTintColor = .white
                if let element = annotation.element {
                    let symbolName = ElementCategorySymbols.symbolName(for: element)
                    Debug.logMap("MiniMap: Rendering annotation for \(element.osmJSON?.tags?.name ?? "unknown") amenity=\(element.osmTagsDict?["amenity"] ?? "none"), symbol=\(symbolName)")
                    view?.glyphImage = UIImage(systemName: symbolName)?.withTintColor(.white, renderingMode: .alwaysOriginal)
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
