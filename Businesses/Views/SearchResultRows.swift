import SwiftUI
import CoreLocation

// MARK: - Merchant Search Result Row

struct MerchantSearchResultRow: View {
    @Environment(\.locale) private var locale
    let result: V4PlaceRecord
    let referenceLocation: CLLocation?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                HStack(spacing: 4) {
                    Text(result.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    if result.verifiedAt != nil {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                            .accessibilityLabel("Verified")
                    }
                }

                Spacer()

                if let distanceText {
                    Text(distanceText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let address = result.address, !address.isEmpty {
                Text(address)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
    }

    private var distanceText: String? {
        guard let referenceLocation,
              let lat = result.lat,
              let lon = result.lon else { return nil }

        let target = CLLocation(latitude: lat, longitude: lon)
        let meters = referenceLocation.distance(from: target)
        let useMetric = locale.measurementSystem == .metric
        let value = useMetric ? (meters / 1000) : (meters / 1609.344)
        let unit: UnitLength = useMetric ? .kilometers : .miles
        let fractionDigits = value < 10 ? 1 : 0

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

// MARK: - Event Row

struct BTCMapEventRow: View {
    let event: V4EventRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "calendar")
                    .font(.caption)
                    .foregroundStyle(.accent)
                Text(event.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Spacer()
                if event.lat != nil, event.lon != nil {
                    Image(systemName: "location.fill")
                        .font(.caption)
                        .foregroundStyle(.accent)
                        .accessibilityLabel("Has map location")
                }
            }

            if let dateRange = formattedDateRange {
                Text(dateRange)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .opacity((event.lat == nil || event.lon == nil) ? 0.5 : 1.0)
    }

    private var formattedDateRange: String? {
        let start = formattedEventDate(event.startsAt)
        let end = formattedEventDate(event.endsAt)
        switch (start, end) {
        case let (s?, e?): return "\(s) – \(e)"
        case let (s?, nil): return s
        case let (nil, e?): return String(localized: "Until \(e)", comment: "Event date range label when only the end date is known")
        case (nil, nil): return nil
        }
    }

    private func formattedEventDate(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty, !raw.hasPrefix("1970-01-01") else { return nil }
        if let date = parseBTCMapISO8601Date(raw) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return raw
    }
}

// MARK: - Area Row

struct BTCMapAreaRow: View {
    let area: V3AreaRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(area.displayName)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)

            if let subtitle = areaSubtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
    }

    private var areaSubtitle: String? {
        if let place = area.tags?["place"], !place.isEmpty {
            return place.capitalized
        }
        if let boundary = area.tags?["boundary"], !boundary.isEmpty {
            return boundary.capitalized
        }
        if let alias = area.urlAlias, !alias.isEmpty {
            return alias
        }
        return nil
    }
}

// MARK: - Shared ISO8601 Date Parsing

func parseBTCMapISO8601Date(_ raw: String) -> Date? {
    (try? Date(raw, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
        ?? (try? Date(raw, strategy: .iso8601))
}
