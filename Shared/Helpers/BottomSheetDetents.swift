import SwiftUI

enum BottomSheetDetents {
    /// Fixed collapsed height so the compact sheet lands consistently across iPhone sizes.
    static let collapsedHeight: CGFloat = 84
    static let collapsed: PresentationDetent = .height(collapsedHeight)
}
