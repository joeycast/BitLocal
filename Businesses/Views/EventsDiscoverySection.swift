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
                    NavigationLink {
                        AllEventsListView()
                            .environmentObject(viewModel)
                    } label: {
                        Text("See All")
                            .font(.subheadline)
                    }
                    .accessibilityLabel("See all events")
                }
                .padding(.horizontal, 16)

                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(events) { event in
                            EventCarouselCard(event: event, userLocation: viewModel.userLocation)
                                .onTapGesture {
                                    viewModel.selectEvent(event)
                                }
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 16)
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.hidden)
                .frame(height: 88)
            }
            .padding(.vertical, 8)
        }
    }

    private var carouselEvents: [V4EventRecord] {
        let withCoords = viewModel.eventsResults.filter { $0.lat != nil && $0.lon != nil }

        let futureEvents = withCoords.filter { event in
            guard let startsAt = event.startsAt,
                  let date = btcMapISO8601WithFractional.date(from: startsAt) ?? btcMapISO8601Basic.date(from: startsAt) else {
                return true // include events without a parseable date
            }
            return date >= Date()
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
        .frame(width: 160, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
                )
        }
        .clipShape(.rect(cornerRadius: 12))
    }

    private var formattedStartDate: String? {
        guard let raw = event.startsAt, !raw.isEmpty, !raw.hasPrefix("1970-01-01") else { return nil }
        if let date = btcMapISO8601WithFractional.date(from: raw) ?? btcMapISO8601Basic.date(from: raw) {
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
        let useMetric = Locale.current.measurementSystem == .metric
        if useMetric {
            let km = meters / 1000
            return km < 10 ? String(format: "%.1f km away", km) : String(format: "%.0f km away", km)
        } else {
            let miles = meters / 1609.34
            return miles < 10 ? String(format: "%.1f mi away", miles) : String(format: "%.0f mi away", miles)
        }
    }
}
