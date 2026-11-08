import SwiftUI

/// Every layout threshold in one place so they can be tuned after testing
/// (docs/redesign/ui-redesign.md 4.1, duo.md 7).
public enum LayoutMetrics {
    /// Regular width at or above this gets sidebar + map + inspector.
    public static let expandedMinWidth: CGFloat = 1000
    /// Below this height a wide-enough window uses a narrow sidebar instead of a sheet.
    public static let shortHeightSidebarMaxHeight: CGFloat = 500
    /// Below this height the compact `card` detent shows the horizontal card row.
    public static let cardRowMaxHeight: CGFloat = 740

    public static let sidebarMinWidth: CGFloat = 320
    public static let sidebarIdealWidth: CGFloat = 360
    public static let inspectorMinWidth: CGFloat = 340
    public static let inspectorIdealWidth: CGFloat = 380
    public static let inspectorMaxWidth: CGFloat = 420

    /// Compact sheet detent heights.
    public static let peekDetentHeight: CGFloat = 120
    public static let cardDetentRange: ClosedRange<CGFloat> = 260...380

    /// Map clustering grid cell, in points.
    public static let clusterCellSize: CGFloat = 60
    public static let pinDiameter: CGFloat = 28
    public static let selectedPinDiameter: CGFloat = 36

    public static let minimumHitTarget: CGFloat = 44
    /// Debounce for size-class changes during live resize.
    public static let sizeClassDebounce: Duration = .milliseconds(100)
    /// Debounce before re-querying pins after the camera settles.
    public static let cameraIdleDebounce: Duration = .milliseconds(150)
}

/// Spacing scale (4, 8, 12, 16, 20, 24, 32).
public enum Spacing {
    public static let xxs: CGFloat = 4
    public static let xs: CGFloat = 8
    public static let s: CGFloat = 12
    public static let m: CGFloat = 16
    public static let l: CGFloat = 20
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32

    /// Screen-edge margin on compact layouts.
    public static let screenEdge: CGFloat = 16
    /// Edge margin in the sidebar and inspector.
    public static let columnEdge: CGFloat = 20
}

/// Corner radii (nested rule: inner = outer − padding).
public enum Radius {
    public static let card: CGFloat = 16
    public static let image: CGFloat = 12
}
