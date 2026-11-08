//
//  MerchantCardView.swift
//  bitlocal
//
//  Redesign phase 5: the merchant card (ui-redesign.md 4.5). Shown at the top
//  of every merchant detail: name and distance, category and open status,
//  payment chips and the action row. Swiping it sideways pages through the
//  current list, nearest first.
//

import SwiftUI
import MapKit
import BitLocalDomain
import BitLocalDesign
import BitLocalNavigation

struct MerchantCardView: View {
    let element: Element
    let distanceText: String?
    var hasPrevious = false
    var hasNext = false
    /// Called with +1 (next) or -1 (previous). Returns false when there is nothing that way.
    var onPage: ((Int) -> Bool)?
    var onClose: (() -> Void)?

    @State private var dragOffset: CGFloat = 0
    @State private var isPaging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var merchant: Merchant? { element.merchant }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            header
            if let methods = merchant?.summary.paymentMethods, !methods.isEmpty {
                PaymentChipsView(methods: methods)
            }
            actionRow
        }
        .padding(.vertical, Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .offset(x: dragOffset)
        .simultaneousGesture(pagingGesture, including: onPage == nil ? .none : .all)
        .accessibilityElement(children: .contain)
        .accessibilityActions {
            if hasNext {
                Button(String(localized: "Next place")) { _ = onPage?(1) }
            }
            if hasPrevious {
                Button(String(localized: "Previous place")) { _ = onPage?(-1) }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(merchant?.summary.name ?? element.displayNameForUI ?? String(localized: "Place"))
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                        .accessibilityAddTraits(.isHeader)
                    if element.isCurrentlyBoosted() {
                        Text(String(localized: "Featured"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BrandColor.boost)
                    }
                }
                subtitle
            }
            Spacer(minLength: Spacing.xs)
            if let distanceText {
                Text(distanceText)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(.thinMaterial, in: Circle())
                        .frame(width: LayoutMetrics.minimumHitTarget, height: LayoutMetrics.minimumHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Close"))
            }
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        let category = merchant.flatMap { ElementCategorySymbols.friendlyCategoryLabel(forIcon: $0.summary.category.rawValue) }
        let hours = OpeningHours.parse(merchant?.summary.openingHours)
        let status = hours.map { OpeningHoursText.status($0.status(at: .now)) }
        if category != nil || status != nil {
            HStack(spacing: 4) {
                if let category {
                    Text(category)
                }
                if category != nil, status != nil {
                    Text(verbatim: "·")
                }
                if let status {
                    Text(status.state)
                        .foregroundStyle(status.isOpen ? BrandColor.open : BrandColor.closed)
                    if let detail = status.detail {
                        Text(verbatim: "·")
                        Text(detail)
                    }
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Actions

    private var actionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                if let coordinate = element.mapCoordinate {
                    CardActionButton(title: String(localized: "Directions"), systemImage: "arrow.triangle.turn.up.right.diamond.fill", isPrimary: true) {
                        openLocationInMaps(coordinate: coordinate, name: element.displayNameForUI, address: element.address)
                    }
                }
                if let phone = merchant?.contact.phone, let url = phoneURL(phone) {
                    CardActionButton(title: String(localized: "Call"), systemImage: "phone.fill") {
                        UIApplication.shared.open(url)
                    }
                }
                if let website = merchant?.contact.website {
                    CardActionButton(title: String(localized: "Website"), systemImage: "safari.fill") {
                        UIApplication.shared.open(website)
                    }
                }
                if FeatureFlags.isSharePlaceLinksEnabled, let url = PlaceShareLinkBuilder.makeShareURL(forPlaceID: element.id) {
                    ShareLink(item: url, message: Text(shareMessage)) {
                        CardActionLabel(title: String(localized: "Share"), systemImage: "square.and.arrow.up", isPrimary: false)
                    }
                    .buttonStyle(.pressable)
                }
            }
        }
        .scrollClipDisabled()
    }

    private var shareMessage: String {
        if let name = element.displayName, !name.isEmpty {
            return String(localized: "Check out \(name) on BitLocal! 🟠")
        }
        return ""
    }

    private func phoneURL(_ phone: String) -> URL? {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        return digits.isEmpty ? nil : URL(string: "tel:\(digits)")
    }

    // MARK: Paging

    private var pagingGesture: some Gesture {
        DragGesture(minimumDistance: CardPaging.claimDistance)
            .onChanged { value in
                let dx = Double(value.translation.width)
                let dy = Double(value.translation.height)
                if !isPaging {
                    guard CardPaging.claims(dx: dx, dy: dy) else { return }
                    isPaging = true
                }
                dragOffset = CGFloat(CardPaging.offset(for: dx, hasPrevious: hasPrevious, hasNext: hasNext))
            }
            .onEnded { value in
                defer { isPaging = false }
                guard isPaging else { return }
                let step = CardPaging.step(
                    translation: Double(value.translation.width),
                    velocity: Double(value.velocity.width),
                    width: 360
                )
                let paged = step != 0 && (onPage?(step) ?? false)
                if paged {
                    UISelectionFeedbackGenerator().selectionChanged()
                    // The next merchant's detail replaces this view; just reset.
                    dragOffset = 0
                } else {
                    withAnimation(Motion.unlessReduced(Motion.select, reduceMotion: reduceMotion)) { dragOffset = 0 }
                }
            }
    }
}

// MARK: - Pieces

private struct CardActionButton: View {
    let title: String
    let systemImage: String
    var isPrimary = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CardActionLabel(title: title, systemImage: systemImage, isPrimary: isPrimary)
        }
        .buttonStyle(.pressable)
    }
}

private struct CardActionLabel: View {
    let title: String
    let systemImage: String
    let isPrimary: Bool

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, Spacing.s)
            .frame(minHeight: LayoutMetrics.minimumHitTarget)
            .foregroundStyle(isPrimary ? BrandColor.onBrandFill : BrandColor.brandInk)
            .background(
                isPrimary ? BrandColor.brandFill : Color.secondary.opacity(0.14),
                in: Capsule()
            )
    }
}

struct PaymentChipsView: View {
    let methods: PaymentMethods

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if methods.contains(.lightning) {
                chip(String(localized: "Lightning"), "bolt.fill")
            }
            if methods.contains(.onchain) {
                chip(String(localized: "On-chain"), "bitcoinsign.circle.fill")
            }
            if methods.contains(.lightningContactless) {
                chip(String(localized: "Contactless"), "wave.3.right")
            }
            if methods.contains(.bitcoinUnspecified) && !methods.contains(.onchain) && !methods.contains(.lightning) {
                chip(String(localized: "Bitcoin"), "bitcoinsign.circle.fill")
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func chip(_ title: String, _ systemImage: String) -> some View {
        Label {
            Text(title).foregroundStyle(.primary)
        } icon: {
            Image(systemName: systemImage).foregroundStyle(BrandColor.brandInk)
        }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.12), in: Capsule())
    }
}

/// Words for an opening-hours status: "Open" + "Closes 6 PM", "Closed" + "Opens Mon 9 AM".
enum OpeningHoursText {
    struct Line {
        let isOpen: Bool
        let state: String
        let detail: String?
    }

    static func status(_ status: OpeningHours.Status, calendar: Calendar = .current, now: Date = .now) -> Line {
        switch status {
        case .open(let closesAt):
            guard let closesAt else {
                return Line(isOpen: true, state: String(localized: "Open 24 hours"), detail: nil)
            }
            return Line(isOpen: true, state: String(localized: "Open"), detail: String(localized: "Closes \(time(closesAt, calendar: calendar, now: now))"))
        case .closed(let opensAt, let daysAhead):
            guard let opensAt, let daysAhead else {
                return Line(isOpen: false, state: String(localized: "Closed"), detail: nil)
            }
            let timeText = time(opensAt, calendar: calendar, now: now)
            if daysAhead == 0 {
                return Line(isOpen: false, state: String(localized: "Closed"), detail: String(localized: "Opens \(timeText)"))
            }
            let day = calendar.date(byAdding: .day, value: daysAhead, to: now)
                .map { $0.formatted(.dateTime.weekday(.abbreviated)) } ?? ""
            return Line(isOpen: false, state: String(localized: "Closed"), detail: String(localized: "Opens \(day) \(timeText)"))
        }
    }

    /// "6 PM" or "6:30 PM" in the user's locale.
    static func time(_ minutes: Int, calendar: Calendar = .current, now: Date = .now) -> String {
        let start = calendar.startOfDay(for: now)
        let date = calendar.date(byAdding: .minute, value: minutes % (24 * 60), to: start) ?? start
        if minutes % 60 == 0 {
            return date.formatted(.dateTime.hour())
        }
        return date.formatted(.dateTime.hour().minute())
    }
}
