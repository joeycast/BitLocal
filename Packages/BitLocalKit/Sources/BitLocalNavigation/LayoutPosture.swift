import CoreGraphics
import Foundation

/// Horizontal/vertical size class, mirrored so this module has no SwiftUI dependency.
public enum SizeClass: Sendable, Equatable {
    case compact
    case regular
}

/// A fold reported by the system as a `.division` reserved region (iOS 27.1+).
public struct Division: Hashable, Sendable {
    public var frame: CGRect
    public var isActive: Bool

    public init(frame: CGRect, isActive: Bool) {
        self.frame = frame
        self.isActive = isActive
    }

    public var isVertical: Bool { frame.height > frame.width }
}

/// Everything layout resolution needs, as plain values so tests never need a device.
public struct GeometrySnapshot: Equatable, Sendable {
    public var size: CGSize
    public var horizontal: SizeClass?
    public var vertical: SizeClass?
    public var divisions: [Division]
    public var occlusions: [CGRect]

    public init(size: CGSize, horizontal: SizeClass?, vertical: SizeClass?, divisions: [Division] = [], occlusions: [CGRect] = []) {
        self.size = size
        self.horizontal = horizontal
        self.vertical = vertical
        self.divisions = divisions
        self.occlusions = occlusions
    }
}

/// Which container shows the content (ui-redesign.md 4.1, duo.md 7.2).
public enum LayoutPosture: Equatable, Sendable {
    /// Full-bleed map + bottom sheet. `shortHeight` turns the card detent into a card row.
    case compact(shortHeight: Bool)
    /// Short, wide window: narrow sidebar beside the map instead of a sheet.
    case compactLandscape
    /// Sidebar + map; detail pushes inside the sidebar.
    case regular
    /// Sidebar + map + inspector for detail.
    case expanded
    /// Browse column on one side of a vertical fold, map on the other.
    case foldColumns(divisionFrame: CGRect, isActive: Bool)
    /// Map above a horizontal fold, browse panel below.
    case foldStack(divisionFrame: CGRect, isActive: Bool)

    public var usesSheet: Bool {
        if case .compact = self { return true }
        return false
    }

    public var hasInspector: Bool { self == .expanded }

    public var isFold: Bool {
        switch self {
        case .foldColumns, .foldStack: true
        default: false
        }
    }

    /// Same kind of container, ignoring fold frames and the short-height flag.
    func sameFamily(as other: LayoutPosture) -> Bool {
        switch (self, other) {
        case (.compact, .compact), (.compactLandscape, .compactLandscape), (.regular, .regular),
             (.expanded, .expanded), (.foldColumns, .foldColumns), (.foldStack, .foldStack):
            true
        default:
            false
        }
    }
}

/// Thresholds (mirrors `LayoutMetrics` in BitLocalDesign; kept here so this module stays UI-free).
public enum PostureThresholds {
    public static let expandedMinWidth: CGFloat = 1000
    public static let shortHeightSidebarMaxHeight: CGFloat = 500
    public static let cardRowMaxHeight: CGFloat = 740
    /// A division whose aspect ratio is within this of 1 has no clear direction.
    public static let ambiguousDivisionRatio: CGFloat = 1.2
}

public enum PostureResolver {
    /// Pure posture resolution. Order: short-and-wide → compact width → fold → width.
    public static func resolve(_ snapshot: GeometrySnapshot) -> LayoutPosture {
        let size = snapshot.size
        if size.height < PostureThresholds.shortHeightSidebarMaxHeight && size.width > size.height {
            return .compactLandscape
        }
        guard snapshot.horizontal == .regular else {
            return .compact(shortHeight: size.height < PostureThresholds.cardRowMaxHeight)
        }
        if let division = snapshot.divisions
            .filter({ !$0.frame.isEmpty })
            .max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) {
            let long = max(division.frame.width, division.frame.height)
            let short = max(min(division.frame.width, division.frame.height), 0.5)
            if long / short >= PostureThresholds.ambiguousDivisionRatio {
                return division.isVertical
                    ? .foldColumns(divisionFrame: division.frame, isActive: division.isActive)
                    : .foldStack(divisionFrame: division.frame, isActive: division.isActive)
            }
        }
        return size.width >= PostureThresholds.expandedMinWidth ? .expanded : .regular
    }
}
