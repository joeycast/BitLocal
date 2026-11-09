import Foundation
import Observation
import BitLocalDomain
import BitLocalData

/// Where the map reads merchants from. `MerchantStore` is the real one; tests use fakes.
public protocol MerchantViewportSource: Sendable {
    func summaries(in rect: GeoRect, filter: MerchantFilter, limit: Int) async throws -> [MerchantSummary]
}

extension MerchantStore: MerchantViewportSource {}

/// Owns what the map draws (architecture-redesign.md section 6):
///
/// camera idle → debounce → R-tree query (+25% margin) → cluster off the main
/// actor → publish `items`. Each camera change cancels the previous pass, so
/// results never land out of order.
@MainActor
@Observable
public final class MapModel {
    public struct Configuration: Sendable {
        public var debounce: Duration
        /// Fraction of the visible span added on every side before querying, so short pans need no new query to show pins.
        public var margin: Double
        public var queryLimit: Int
        /// Rows handed to the list: the nearest merchants inside the visible rect.
        public var listLimit: Int
        public var cellSize: Double

        public init(
            debounce: Duration = .milliseconds(150),
            margin: Double = 0.25,
            queryLimit: Int = 30_000,
            listLimit: Int = 200,
            cellSize: Double = 60
        ) {
            self.debounce = debounce
            self.margin = margin
            self.queryLimit = queryLimit
            self.listLimit = listLimit
            self.cellSize = cellSize
        }
    }

    /// Pins and clusters to draw.
    public private(set) var items: [MapItem] = []
    /// Merchants inside the visible rect, nearest to the viewport center first, capped at `listLimit`.
    public private(set) var visibleSummaries: [MerchantSummary] = []
    /// Total merchants inside the visible rect (before the list cap).
    public private(set) var visibleCount = 0
    /// The viewport the current `items` were computed for.
    public private(set) var renderedViewport: MapViewport?
    /// Bumps each time a pass lands, so a UIKit map can tell new results from re-renders.
    public private(set) var revision = 0

    public var filter: MerchantFilter = .all {
        didSet { if filter != oldValue { refresh(immediately: true) } }
    }

    /// When set, only these merchants are drawn and listed (search results, an alert
    /// digest). Nil draws everything the filter allows. Applied after the viewport
    /// query, so the set can be any size without a SQL `IN` list.
    public var restriction: Set<MerchantID>? {
        didSet { if restriction != oldValue { refresh(immediately: true) } }
    }

    /// Always drawn as its own pin.
    public var selectedID: MerchantID? {
        didSet { if selectedID != oldValue { recluster() } }
    }

    @ObservationIgnored private let source: any MerchantViewportSource
    @ObservationIgnored private let configuration: Configuration
    @ObservationIgnored private var viewport: MapViewport?
    @ObservationIgnored private var pass: Task<Void, Never>?
    @ObservationIgnored private var lastSummaries: [MerchantSummary] = []

    public init(source: any MerchantViewportSource, configuration: Configuration = Configuration()) {
        self.source = source
        self.configuration = configuration
    }

    /// Call when the camera settles.
    public func cameraDidChange(_ viewport: MapViewport) {
        guard viewport != self.viewport else { return }
        self.viewport = viewport
        refresh(immediately: false)
    }

    /// Re-runs the query for the current viewport (after a sync or a filter change).
    public func refresh(immediately: Bool = true) {
        guard let viewport else { return }
        pass?.cancel()
        let source = source
        let configuration = configuration
        let filter = filter
        let selected = selectedID
        let restriction = restriction
        pass = Task { [weak self] in
            if !immediately, configuration.debounce > .zero {
                try? await Task.sleep(for: configuration.debounce)
            }
            guard !Task.isCancelled else { return }
            let queryRect = viewport.rect.expanded(by: configuration.margin)
            guard let queried = try? await source.summaries(in: queryRect, filter: filter, limit: configuration.queryLimit),
                  !Task.isCancelled else { return }
            let summaries = restriction.map { allowed in queried.filter { allowed.contains($0.id) } } ?? queried
            let result = await Self.compute(summaries, viewport: viewport, selected: selected, configuration: configuration)
            guard !Task.isCancelled else { return }
            self?.apply(result, summaries: summaries, viewport: viewport)
        }
    }

    /// Waits for the pass in flight. For tests and for callers that need the result before continuing.
    public func settle() async {
        await pass?.value
    }

    /// Follows store changes: every committed sync batch refreshes the map once.
    public func follow(_ changes: AsyncStream<StoreChange>) -> Task<Void, Never> {
        Task { [weak self] in
            for await _ in changes {
                guard let self else { return }
                self.refresh(immediately: true)
            }
        }
    }

    private func recluster() {
        guard let viewport = renderedViewport else { return }
        let summaries = lastSummaries
        let selected = selectedID
        let configuration = configuration
        pass?.cancel()
        pass = Task { [weak self] in
            let result = await Self.compute(summaries, viewport: viewport, selected: selected, configuration: configuration)
            guard !Task.isCancelled else { return }
            self?.apply(result, summaries: summaries, viewport: viewport)
        }
    }

    private func apply(_ result: PassResult, summaries: [MerchantSummary], viewport: MapViewport) {
        lastSummaries = summaries
        renderedViewport = viewport
        if items != result.items { items = result.items }
        if visibleSummaries != result.visible {
            visibleSummaries = result.visible
        }
        if visibleCount != result.visibleCount { visibleCount = result.visibleCount }
        revision &+= 1
    }

    struct PassResult: Sendable {
        let items: [MapItem]
        let visible: [MerchantSummary]
        let visibleCount: Int
    }

    struct Ranked: Sendable {
        let summary: MerchantSummary
        let distance: Double

        static func nearerFirst(_ lhs: Ranked, _ rhs: Ranked) -> Bool {
            if lhs.distance != rhs.distance { return lhs.distance < rhs.distance }
            return lhs.summary.id.rawValue < rhs.summary.id.rawValue
        }
    }

    /// Pure and nonisolated, so it runs off the main actor.
    nonisolated static func compute(
        _ summaries: [MerchantSummary],
        viewport: MapViewport,
        selected: MerchantID?,
        configuration: Configuration
    ) async -> PassResult {
        let items = MerchantClusterer.cluster(summaries, viewport: viewport, cellSize: configuration.cellSize, selected: selected)
        let inside = summaries.filter { viewport.rect.contains($0.coordinate) }
        let center = viewport.center
        let ranked: [Ranked] = inside.map { Ranked(summary: $0, distance: $0.coordinate.distance(to: center)) }
        let sorted = ranked.sorted(by: Ranked.nearerFirst)
        let nearest: [MerchantSummary] = sorted.prefix(configuration.listLimit).map { $0.summary }
        return PassResult(items: items, visible: nearest, visibleCount: inside.count)
    }
}
