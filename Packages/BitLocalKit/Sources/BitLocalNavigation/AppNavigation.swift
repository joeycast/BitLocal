import Foundation
import Observation
import BitLocalDomain

/// Compact bottom-sheet stops (ui-redesign.md 4.3).
public enum SheetDetent: String, Codable, Sendable, CaseIterable {
    case peek
    case card
    case full
}

public enum BrowseMode: String, Codable, Sendable {
    case places
    case communities
}

public enum Selection: Hashable, Codable, Sendable {
    case merchant(MerchantID)
    case community(CommunityID)

    public var merchantID: MerchantID? {
        if case .merchant(let id) = self { return id }
        return nil
    }
}

/// Where a selection came from; decides camera and sheet side effects.
public enum SelectionSource: Sendable, Equatable {
    case map
    case list
    case search
    case deepLink
    case notification
    case cardSwipe
    case restoration
}

/// Destinations in the one browse path, rendered by sheet, sidebar or fold panel alike.
public enum Route: Hashable, Codable, Sendable {
    case merchant(MerchantID)
    case community(CommunityID)
    case allReviews(MerchantID)
}

public enum Modal: Hashable, Sendable {
    case settings
    case addBusiness
    case alerts
}

/// What a selection change should do around it. Computed by `NavigationReducer`.
public struct NavigationEffects: Equatable, Sendable {
    /// Compact only: move the sheet to this detent.
    public var detent: SheetDetent?
    /// Push the detail onto the browse container (sidebar / fold panel).
    public var pushDetail: Bool
    /// Show the detail in the inspector (expanded).
    public var showInspector: Bool
    /// Ask the map to reveal the selected pin (zoom until alone, center above the panel).
    public var revealOnMap: Bool

    public init(detent: SheetDetent? = nil, pushDetail: Bool = false, showInspector: Bool = false, revealOnMap: Bool = false) {
        self.detent = detent
        self.pushDetail = pushDetail
        self.showInspector = showInspector
        self.revealOnMap = revealOnMap
    }
}

public enum NavigationReducer {
    /// One pure function from (selection, posture, source, current detent) to side effects,
    /// so resizing and folding never need special cases in views.
    public static func effects(
        selection: Selection?,
        posture: LayoutPosture,
        source: SelectionSource,
        currentDetent: SheetDetent,
        detentBeforeSelection: SheetDetent
    ) -> NavigationEffects {
        guard let selection else {
            return NavigationEffects(detent: posture.usesSheet ? detentBeforeSelection : nil)
        }
        // The pin is already where the finger is; don't move the world on a map tap.
        let reveal = source != .map && source != .restoration
        var effects = NavigationEffects(revealOnMap: reveal)
        switch posture {
        case .compact:
            switch (selection, source) {
            case (_, .list), (_, .search):
                effects.detent = currentDetent == .full ? .full : .card
            default:
                effects.detent = currentDetent == .full && source == .cardSwipe ? .full : .card
            }
        case .expanded:
            effects.showInspector = true
        case .regular, .compactLandscape, .foldColumns, .foldStack:
            effects.pushDetail = true
        }
        return effects
    }
}

/// Saved per scene so multi-window and relaunch restore exactly.
public struct NavigationState: Codable, Equatable, Sendable {
    public var selection: Selection?
    public var mode: BrowseMode
    public var sheetDetent: SheetDetent
    public var path: [Route]
    public var searchQuery: String

    public init(selection: Selection? = nil, mode: BrowseMode = .places, sheetDetent: SheetDetent = .peek, path: [Route] = [], searchQuery: String = "") {
        self.selection = selection
        self.mode = mode
        self.sheetDetent = sheetDetent
        self.path = path
        self.searchQuery = searchQuery
    }
}

/// The single owner of "what is shown where" (architecture-redesign.md 7).
/// Layout containers read it; they never own selection state.
@MainActor
@Observable
public final class AppNavigation {
    public private(set) var posture: LayoutPosture = .compact(shortHeight: false)
    public private(set) var selection: Selection?
    public var mode: BrowseMode = .places
    public var sheetDetent: SheetDetent = .peek
    /// Restored when folding/resizing back to compact.
    public private(set) var lastCompactDetent: SheetDetent = .peek
    /// The detent before the current selection, restored on deselect.
    public private(set) var detentBeforeSelection: SheetDetent = .peek
    public var path: [Route] = []
    public var isSearching = false
    public var searchQuery = ""
    public var modal: Modal?
    /// Set when a selection should be revealed on the map; the map clears it after acting.
    public private(set) var pendingReveal: MerchantID?
    /// Latest geometry, for the map's unobscured-rect math.
    public private(set) var geometry: GeometrySnapshot?

    public init() {}

    public var selectedMerchantID: MerchantID? { selection?.merchantID }

    public var isInspectorPresented: Bool { posture.hasInspector && selection != nil }

    /// Resolves the posture from new geometry and re-homes state. Never animates.
    public func updateGeometry(_ snapshot: GeometrySnapshot) {
        geometry = snapshot
        let newPosture = PostureResolver.resolve(snapshot)
        guard newPosture != posture else { return }
        let old = posture
        posture = newPosture
        guard !old.sameFamily(as: newPosture) else { return }

        if old.usesSheet && !newPosture.usesSheet {
            lastCompactDetent = sheetDetent
            if let route = selectionRoute, path.isEmpty, !newPosture.hasInspector {
                path = [route]
            }
        } else if !old.usesSheet && newPosture.usesSheet {
            if selection != nil {
                sheetDetent = path.count > 1 ? .full : .card
            } else {
                sheetDetent = lastCompactDetent
            }
        }
        if newPosture.hasInspector {
            // The inspector shows the selection; the sidebar keeps the list.
            if let first = path.first, first == selectionRoute { path.removeFirst() }
        } else if old.hasInspector, let route = selectionRoute, path.first != route {
            path.insert(route, at: 0)
        }
    }

    /// Selects (or clears) and applies side effects for the current posture.
    @discardableResult
    public func select(_ newSelection: Selection?, source: SelectionSource) -> NavigationEffects {
        if selection == nil, newSelection != nil {
            detentBeforeSelection = sheetDetent
        }
        let effects = NavigationReducer.effects(
            selection: newSelection,
            posture: posture,
            source: source,
            currentDetent: sheetDetent,
            detentBeforeSelection: detentBeforeSelection
        )
        selection = newSelection
        if let detent = effects.detent { sheetDetent = detent }
        if newSelection == nil {
            path = []
        } else if effects.pushDetail, let route = selectionRoute {
            path = [route]
        } else if posture.usesSheet, let route = selectionRoute {
            path = [route]
        } else if effects.showInspector {
            path = []
        }
        pendingReveal = effects.revealOnMap ? newSelection?.merchantID : nil
        if case .merchant = newSelection, mode == .communities, source == .list {
            mode = .places
        }
        return effects
    }

    /// The map calls this once it has revealed `pendingReveal`.
    public func didReveal() { pendingReveal = nil }

    public func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
        if path.isEmpty, !posture.hasInspector { select(nil, source: .list) }
    }

    private var selectionRoute: Route? {
        switch selection {
        case .merchant(let id): .merchant(id)
        case .community(let id): .community(id)
        case nil: nil
        }
    }

    // MARK: Restoration

    public var restorationState: NavigationState {
        NavigationState(selection: selection, mode: mode, sheetDetent: sheetDetent, path: path, searchQuery: searchQuery)
    }

    public func restore(_ state: NavigationState) {
        mode = state.mode
        sheetDetent = state.sheetDetent
        searchQuery = state.searchQuery
        selection = state.selection
        path = state.path
    }
}
