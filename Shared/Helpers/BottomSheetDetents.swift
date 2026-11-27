import SwiftUI

enum BottomSheetDetents {
    /// Fixed collapsed height so the compact sheet lands consistently across iPhone sizes.
    static let collapsedHeight: CGFloat = 84
    static let collapsed: PresentationDetent = .height(collapsedHeight)
    /// Tall floating detent for wide leading-side sheets (e.g. iPhone Duo landscape)
    /// so the card keeps rounded bottom corners instead of docking flush to the bezel.
    static let expandedLeading: PresentationDetent = .fraction(0.92)
}
