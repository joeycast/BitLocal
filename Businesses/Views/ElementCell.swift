import SwiftUI
import CoreLocation

struct ElementCell: View {

    var viewModel: ElementCellViewModel
    var showsBottomDivider = false
    var isSaved = false
    @Environment(\.locale) private var locale
    @AppStorage("distanceUnit") private var distanceUnit: DistanceUnit = .auto

    private var categoryBadgeSymbolName: String {
        ElementCategoryBadgeHelper.badgeSymbolName(for: viewModel.element)
    }

    private var formattedDistance: String? {
        if let distance = localizedDistanceString(for: viewModel.element) {
            return distance
        }
        if let distance = viewModel.viewModel.distanceInMiles(element: viewModel.element) {
            let fractionDigits = distance < 1 ? 2 : 1
            return Measurement(value: distance, unit: UnitLength.miles).formatted(
                .measurement(
                    width: .abbreviated,
                    usage: .asProvided,
                    numberFormatStyle: .number.precision(.fractionLength(fractionDigits))
                )
                .locale(locale)
            )
        }
        return nil
    }

    private var addressLines: [String] {
        guard let formatted = viewModel.address?.formatted(.compact) else { return [] }
        return formatted
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                // Solid map-pin badge (MarkerColor circle + crisp white symbol)
                // links each row 1:1 to its map marker in both Light and Dark Mode.
                Image(systemName: categoryBadgeSymbolName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color("MarkerColor"), in: Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.75)
                    }
                    .padding(.top, 2)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(
                            viewModel.element.displayNameForUI ??
                            String(localized: "name_not_available", comment: "Fallback name for unavailable business name")
                        )
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if isSaved || formattedDistance != nil {
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                if isSaved {
                                    Image(systemName: "bookmark.fill")
                                        .font(.caption2)
                                        .foregroundStyle(Color.accentColor)
                                        .accessibilityLabel(String(localized: "Saved", comment: "VoiceOver label for saved place indicator"))
                                }

                                if let distance = formattedDistance {
                                    Text(distance)
                                        .font(.footnote.weight(.medium))
                                        .foregroundStyle(Color.primary.opacity(0.68))
                                        .fixedSize()
                                }
                            }
                        }
                    }

                    if let firstLine = addressLines.first {
                        Text(firstLine)
                            .font(.subheadline)
                            .foregroundStyle(Color.primary.opacity(0.72))
                            .lineLimit(1)
                    }

                    let secondaryLine = addressLines.dropFirst().joined(separator: ", ")
                    HStack(alignment: .center, spacing: 8) {
                        if !secondaryLine.isEmpty {
                            Text(secondaryLine)
                                .font(.footnote)
                                .foregroundStyle(Color.primary.opacity(0.65))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Spacer(minLength: 0)
                        }

                        PaymentIcons(element: viewModel.element)
                    }
                }
            }
            .padding(.vertical, 4)

            if showsBottomDivider {
                Rectangle()
                    .fill(Color(.separator))
                    .frame(height: 1)
                    .padding(.top, 8)
                    .padding(.trailing, -22)
            }
        }
        .contentShape(Rectangle())
        .onAppear {
            viewModel.onCellAppear()
        }
        .onDisappear {
            viewModel.onCellDisappear()
        }
    }
    
    private func localizedDistanceString(for element: Element) -> String? {
        guard let userLocation = viewModel.viewModel.userLocation, let coord = element.mapCoordinate else { return nil }
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
        let value = useMetric ? (distanceInMeters / 1000) : (distanceInMeters / 1609.344)
        let unit: UnitLength = useMetric ? .kilometers : .miles
        let fractionDigits = value < 1 ? 2 : 1
        return Measurement(value: value, unit: unit).formatted(
            .measurement(
                width: .abbreviated,
                usage: .asProvided,
                numberFormatStyle: .number.precision(.fractionLength(fractionDigits))
            )
            .locale(locale)
        )
    }
}

struct PaymentIcons: View {
    let element: Element

    var body: some View {
        HStack(spacing: 6) {
            if acceptsBitcoin(element: element) || acceptsBitcoinOnChain(element: element) {
                Image(systemName: "bitcoinsign.circle.fill")
                    .foregroundStyle(.accent)
                    .accessibilityLabel(String(localized: "On-chain Bitcoin", comment: "VoiceOver payment method"))
            }

            if acceptsLightning(element: element) {
                Image(systemName: "bolt.circle.fill")
                    .foregroundStyle(.accent)
                    .accessibilityLabel(String(localized: "Lightning", comment: "VoiceOver payment method"))
            }

            if acceptsContactlessLightning(element: element) {
                Image(systemName: "wave.3.right.circle.fill")
                    .foregroundStyle(.accent)
                    .accessibilityLabel(String(localized: "Contactless Lightning", comment: "VoiceOver payment method"))
            }
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(paymentMethodsAccessibilityLabel)
    }

    private var paymentMethodsAccessibilityLabel: String {
        var methods: [String] = []
        if acceptsBitcoin(element: element) || acceptsBitcoinOnChain(element: element) {
            methods.append(String(localized: "On-chain Bitcoin", comment: "VoiceOver payment method"))
        }
        if acceptsLightning(element: element) {
            methods.append(String(localized: "Lightning", comment: "VoiceOver payment method"))
        }
        if acceptsContactlessLightning(element: element) {
            methods.append(String(localized: "Contactless Lightning", comment: "VoiceOver payment method"))
        }
        if methods.isEmpty {
            return String(localized: "Payment methods unavailable", comment: "VoiceOver when no payment method icons are shown")
        }
        let formattedMethods = methods.formatted(.list(type: .and))
        return String(
            localized: "Accepts \(formattedMethods)",
            comment: "VoiceOver summary of accepted payment methods"
        )
    }
}
