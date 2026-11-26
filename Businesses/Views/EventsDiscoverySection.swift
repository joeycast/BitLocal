import SwiftUI
import CoreLocation

// MARK: - Events Discovery Carousel

struct EventsDiscoverySection: View {
    @EnvironmentObject var viewModel: ContentViewModel

    var body: some View {
        let events = carouselEvents
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Upcoming Events", systemImage: "calendar")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    NavigationLink(value: BitLocalNavigationRoute.allEvents) {
                        Text("See All")
                            .font(.subheadline)
                    }
                    .accessibilityLabel("See all events")
                }
                .padding(.horizontal, 16)

                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(events) { event in
                            Button {
                                viewModel.selectEvent(event)
                            } label: {
                                EventCarouselCard(event: event, userLocation: viewModel.userLocation)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 16)
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden)
                .frame(minHeight: 88)
            }
            .padding(.vertical, 8)
        }
    }

    private var carouselEvents: [V4EventRecord] {
        let withCoords = viewModel.eventsResults.filter { $0.lat != nil && $0.lon != nil }

        let futureEvents = withCoords.filter { event in
            guard let startsAt = event.startsAt,
                  let date = parseBTCMapISO8601Date(startsAt) else {
                return true // include events without a parseable date
            }
            return date >= Date.now
        }

        let filtered: [V4EventRecord]
        if let userLoc = viewModel.userLocation {
            filtered = futureEvents.filter { event in
                guard let lat = event.lat, let lon = event.lon else { return false }
                let eventLoc = CLLocation(latitude: lat, longitude: lon)
                return userLoc.distance(from: eventLoc) <= 500_000 // 500 km
            }
        } else {
            filtered = futureEvents
        }

        return Array(filtered.prefix(8))
    }
}

// MARK: - Event Carousel Card

private struct EventCarouselCard: View {
    @Environment(\.locale) private var locale
    let event: V4EventRecord
    let userLocation: CLLocation?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(event.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)

            Spacer(minLength: 0)

            if let dateText = formattedStartDate {
                Text(dateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let distText = distanceText {
                Text(distText)
                    .font(.caption2)
                    .foregroundStyle(.accent)
            }
        }
        .padding(12)
        .frame(width: 160, minHeight: 88, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
                }
        }
        .clipShape(.rect(cornerRadius: 12))
    }

    private var formattedStartDate: String? {
        guard let raw = event.startsAt, !raw.isEmpty, !raw.hasPrefix("1970-01-01") else { return nil }
        if let date = parseBTCMapISO8601Date(raw) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return raw
    }

    private var distanceText: String? {
        guard let userLocation,
              let lat = event.lat,
              let lon = event.lon else { return nil }
        let eventLoc = CLLocation(latitude: lat, longitude: lon)
        let meters = userLocation.distance(from: eventLoc)
        let useMetric = locale.measurementSystem == .metric
        let value = useMetric ? (meters / 1000) : (meters / 1609.344)
        let unit: UnitLength = useMetric ? .kilometers : .miles
        let fractionDigits = value < 10 ? 1 : 0
        let formatted = Measurement(value: value, unit: unit).formatted(
            .measurement(
                width: .abbreviated,
                usage: .asProvided,
                numberFormatStyle: .number.precision(.fractionLength(fractionDigits))
            )
            .locale(locale)
        )
        return String(localized: "\(formatted) away", comment: "Distance to an upcoming event")
    }
}
