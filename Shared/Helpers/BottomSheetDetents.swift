import SwiftUI
import BitLocalDesign

enum BottomSheetDetents {
    /// Peek shows the header row (wordmark + settings) and the search field
    /// (ui-redesign.md 4.3, DECISIONS.md phase 3).
    static let collapsedHeight: CGFloat = LayoutMetrics.peekDetentHeight
    static let collapsed: PresentationDetent = .height(collapsedHeight)
}
