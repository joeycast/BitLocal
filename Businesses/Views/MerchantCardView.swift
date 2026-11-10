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
import BitLocalNavigation
import BitLocalDomain
import BitLocalDesign

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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(AppNavigation.self) private var navigation: AppNavigation?

    /// Accessibility text sizes stack the card instead of truncating it (ui-redesign 7).
    private var isAccessibilitySize: Bool { dynamicTypeSize.isAccessibilitySize }

    /// The sheet can grow to show the full detail; VoiceOver gets an explicit action for it.
    private var canExpandDetails: Bool {
        horizontalSizeClass == .compact && navigation != nil && navigation?.sheetDetent != .full
    }

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
            if canExpandDetails {
                Button(String(localized: "Expand details")) { navigation?.sheetDetent = .full }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            if !isAccessibilitySize {
                MerchantCategoryBadge(element: element, size: 52)
            }
            VStack(alignment: .leading, spacing: 3) {
                // At accessibility sizes "Featured" goes under the name so the name keeps the width.
                let nameLayout = isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 6))
                nameLayout {
                    Text(merchant?.summary.name ?? element.displayNameForUI ?? String(localized: "Place"))
                        .font(.title2.weight(.bold))
                        .lineLimit(isAccessibilitySize ? 4 : 2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if element.isCurrentlyBoosted() {
                        Text(String(localized: "Featured"))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(BrandColor.boost)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(BrandColor.boost.opacity(0.14), in: Capsule())
                    }
                }
                subtitle
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .legibleSurface(.thinMaterial, in: Circle())
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
        if isAccessibilitySize, category != nil || status != nil || distanceText != nil {
            // One fact per line, so long words never hyphenate.
            VStack(alignment: .leading, spacing: 2) {
                if let distanceText {
                    Text(distanceText).monospacedDigit()
                }
                if let category {
                    Text(category)
                }
                if let status {
                    Text(status.state)
                        .foregroundStyle(status.isOpen ? BrandColor.open : BrandColor.closed)
                    if let detail = status.detail {
                        Text(detail)
                    }
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        } else if category != nil || status != nil || distanceText != nil {
            // One wrapping line: "0.2 mi · Shopping · Closed · Opens 10 AM".
            let lead = [distanceText, category].compactMap { $0 }.joined(separator: " · ")
            Group {
                if let status {
                    let tail = status.detail.map { " · \($0)" } ?? ""
                    let separator = lead.isEmpty ? "" : " · "
                    Text("\(lead)\(separator)\(Text(status.state).foregroundStyle(status.isOpen ? BrandColor.open : BrandColor.closed))\(tail)")
                } else {
                    Text(lead)
                }
            }
            .font(.subheadline)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Actions

    /// Equal-width tiles, icon over label, so the row reads as one control strip
    /// at any width. Accessibility sizes stack full-width buttons instead, so no
    /// label breaks mid-word.
    @ViewBuilder
    private var actionRow: some View {
        if isAccessibilitySize {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                actionButtons(iconOnly: false)
            }
        } else {
            HStack(spacing: Spacing.xs) {
                actionButtons(iconOnly: false)
            }
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private func actionButtons(iconOnly: Bool) -> some View {
        if let coordinate = element.mapCoordinate {
            CardActionButton(title: String(localized: "Directions"), systemImage: "arrow.triangle.turn.up.right.diamond.fill", isPrimary: true) {
                openLocationInMaps(coordinate: coordinate, name: element.displayNameForUI, address: element.address)
            }
        }
        if let phone = merchant?.contact.phone, let url = phoneURL(phone) {
            CardActionButton(title: String(localized: "Call"), systemImage: "phone.fill", iconOnly: iconOnly) {
                UIApplication.shared.open(url)
            }
        }
        if let website = merchant?.contact.website {
            CardActionButton(title: String(localized: "Website"), systemImage: "safari.fill", iconOnly: iconOnly) {
                UIApplication.shared.open(website)
            }
        }
        if FeatureFlags.isSharePlaceLinksEnabled, let url = PlaceShareLinkBuilder.makeShareURL(forPlaceID: element.id) {
            ShareLink(item: url, message: Text(shareMessage)) {
                CardActionLabel(title: String(localized: "Share"), systemImage: "square.and.arrow.up", isPrimary: false, iconOnly: iconOnly)
            }
            .buttonStyle(.pressable)
        }
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
    var iconOnly = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CardActionLabel(title: title, systemImage: systemImage, isPrimary: isPrimary, iconOnly: iconOnly)
        }
        .buttonStyle(.pressable)
    }
}

private struct CardActionLabel: View {
    let title: String
    let systemImage: String
    let isPrimary: Bool
    var iconOnly = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .padding(.horizontal, Spacing.s)
                .padding(.vertical, Spacing.xs)
                .frame(maxWidth: .infinity, minHeight: LayoutMetrics.minimumHitTarget, alignment: .leading)
                .foregroundStyle(isPrimary ? BrandColor.onBrandFill : BrandColor.brandInk)
                .background(tileFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(height: 20)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isPrimary ? BrandColor.onBrandFill : BrandColor.brandInk)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(tileFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(title))
        }
    }

    private var tileFill: Color {
        isPrimary ? BrandColor.brandFill : BrandColor.brand.opacity(0.12)
    }
}

struct PaymentChipsView: View {
    let methods: PaymentMethods
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Chips sit in a row when they fit and stack otherwise, so no label breaks.
    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Spacing.xs) { chips }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Spacing.xs) { chips }
                    VStack(alignment: .leading, spacing: Spacing.xs) { chips }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var chips: some View {
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

    private func chip(_ title: String, _ systemImage: String) -> some View {
        Label {
            Text(title)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize()
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

/// A merchant's category glyph on a soft brand-tinted disc. Used at the start of
/// every list row and in the merchant card header, so a place has the same face
/// in the list, on the card and (in orange) on its pin.
struct MerchantCategoryBadge: View {
    let element: Element
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: ElementCategorySymbols.symbolName(for: element))
            .font(.system(size: size * 0.42, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(BrandColor.brandInk)
            .frame(width: size, height: size)
            .background(BrandColor.brand.opacity(0.14), in: Circle())
            .overlay {
                if element.isCurrentlyBoosted() {
                    Circle().strokeBorder(BrandColor.boost, lineWidth: 2)
                }
            }
            .accessibilityHidden(true)
    }
}

/// Lays chips out left to right and wraps to a new line instead of scrolling,
/// for columns wide enough that every category fits in two rows.
struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
