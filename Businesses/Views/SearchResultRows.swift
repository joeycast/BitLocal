import SwiftUI
import CoreLocation

// MARK: - Merchant Search Result Row

@available(iOS 17.0, *)
struct MerchantSearchResultRow: View {
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
        let useMetric = Locale.current.measurementSystem == .metric

        if useMetric {
            let km = meters / 1000
            return km < 10 ? String(format: "%.1f km", km) : String(format: "%.0f km", km)
        } else {
            let miles = meters / 1609.34
            return miles < 10 ? String(format: "%.1f mi", miles) : String(format: "%.0f mi", miles)
        }
    }
}

// MARK: - Event Row

@available(iOS 17.0, *)
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
        case let (nil, e?): return "Until \(e)"
        case (nil, nil): return nil
        }
    }

    private func formattedEventDate(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty, !raw.hasPrefix("1970-01-01") else { return nil }
        if let date = btcMapISO8601WithFractional.date(from: raw) ?? btcMapISO8601Basic.date(from: raw) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return raw
    }
}

// MARK: - Area Row

@available(iOS 17.0, *)
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

// MARK: - Shared date formatters

let btcMapISO8601WithFractional: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

let btcMapISO8601Basic: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()
