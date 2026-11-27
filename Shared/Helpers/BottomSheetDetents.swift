import SwiftUI

enum BottomSheetDetents {
    /// Fixed collapsed height so the compact sheet lands consistently across iPhone sizes.
    static let collapsedHeight: CGFloat = 84
    static let collapsed: PresentationDetent = .height(collapsedHeight)
    /// Default mid-screen detent leaving the upper map viewport visible.
    static let standard: PresentationDetent = .fraction(0.37)
    /// Tall floating detent for wide leading-side sheets (e.g. iPhone Duo landscape)
    /// so the card keeps rounded bottom corners instead of docking flush to the bezel.
    static let expandedLeading: PresentationDetent = .fraction(0.92)

    /// Returns `true` only when the sheet covers the full height of the map (`.large`),
    /// excluding leading-side floating sheets that sit alongside the visible map.
    static func isFullScreen(_ detent: PresentationDetent?) -> Bool {
        guard let detent else { return false }
        return detent == .large
    }
}
