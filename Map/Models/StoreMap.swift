//
//  StoreMap.swift
//  bitlocal
//
//  Redesign phase 4: the map reads merchants from the SQLite store through
//  `MapModel` (viewport query + clustering, no 25-mile cap). Search results,
//  alert digests and community members narrow it with `MapModel.restriction`
//  (phases 8i, 8j).
//

import Foundation
import Observation
import MapKit
import BitLocalData
import BitLocalDomain
import BitLocalMap

@MainActor
@Observable
final class StoreMap {
    static let shared = StoreMap()

    /// Nil when the store could not be opened; the map then stays on the legacy path.
    let model: MapModel?
    /// True once the store holds merchants (after the JSON import or the first sync).
    private(set) var isReady = false

    @ObservationIgnored private var followTask: Task<Void, Never>?

    private init() {
        guard let store = MerchantStoreBootstrap.environment?.store else {
            model = nil
            return
        }
        let model = MapModel(source: store)
        model.filter = MerchantFilter(hideATMs: UserDefaults.standard.bool(forKey: "hideATMsFromMapAndList"))
        self.model = model
        Task { [weak self] in
            let changes = await store.changes()
            self?.followTask = model.follow(changes)
        }
    }

    func markReady() {
        if !isReady { isReady = true }
    }

    func setHideATMs(_ hide: Bool) {
        model?.filter.hideATMs = hide
    }

    func setSelected(_ id: MerchantID?) {
        model?.selectedID = id
    }

    /// Changes whenever the map has something new to draw.
    var renderToken: Int {
        isReady ? (model?.revision ?? 0) : -1
    }
}

/// A merchant pin drawn from the store pass. Clustering is BitLocal's own, so
/// MapKit's clustering stays off for these.
final class StoreMerchantAnnotation: Annotation {
    let storeKey: String

    init(element: Element, storeKey: String) {
        self.storeKey = storeKey
        super.init(element: element)
    }
}

/// A cluster bubble from `MerchantClusterer`.
final class StoreClusterAnnotation: NSObject, MKAnnotation {
    let storeKey: String
    let count: Int
    let memberIDs: [MerchantID]
    let isColocated: Bool
    let coordinate: CLLocationCoordinate2D

    init(storeKey: String, coordinate: Coordinate, count: Int, memberIDs: [MerchantID], isColocated: Bool) {
        self.storeKey = storeKey
        self.coordinate = CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
        self.count = count
        self.memberIDs = memberIDs
        self.isColocated = isColocated
    }

    var title: String? {
        String.localizedStringWithFormat(
            NSLocalizedString("%d Bitcoin merchants", comment: "VoiceOver label for a map cluster of merchants"),
            count
        )
    }

    /// "8", "240", "1.2k", "12k": short enough to sit in the bubble.
    var glyphText: String {
        switch count {
        case ..<1_000: return "\(count)"
        case ..<10_000:
            let tenths = (count / 100) % 10
            return tenths == 0 ? "\(count / 1_000)k" : "\(count / 1_000).\(tenths)k"
        default: return "\(count / 1_000)k"
        }
    }
}
