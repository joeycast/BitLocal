import SwiftUI
import UIKit

/// Layout shell selected purely from size classes and available container geometry
/// rather than `UIDevice.current.userInterfaceIdiom`, so iPhone Duo, iPad
/// multitasking, and resizable windows adapt seamlessly across poses.
enum AppLayoutMode: Equatable, Sendable {
    /// Full-bleed map with a floating header and draggable bottom sheet.
    case compactSheet
    /// Two-column `NavigationSplitView` with a leading sidebar and trailing map.
    case splitSidebar

    /// Minimum portrait container width that comfortably fits a side-by-side
    /// sidebar + map split (iPad mini portrait is 744pt; iPhone Duo unfolded
    /// portrait is ~669pt and uses `.compactSheet`, aligning with its horizontal hinge).
    static let portraitSplitMinimumWidth: CGFloat = 720

    static func resolve(
        horizontalSizeClass: UserInterfaceSizeClass?,
        verticalSizeClass: UserInterfaceSizeClass?,
        containerSize: CGSize
    ) -> AppLayoutMode {
        guard horizontalSizeClass == .regular else {
            return .compactSheet
        }
        guard verticalSizeClass != .compact else {
            return .compactSheet
        }
        guard containerSize.width > 0, containerSize.height > 0 else {
            return .compactSheet
        }

        let isWiderThanTall = containerSize.width > containerSize.height
        let hasRoomForPortraitSplit = containerSize.width >= portraitSplitMinimumWidth
        return (isWiderThanTall || hasRoomForPortraitSplit) ? .splitSidebar : .compactSheet
    }
}

/// Active-scene lookup that avoids `.connectedScenes.first` in multi-scene
/// environments such as iPhone Duo inner display and iPad multitasking.
@MainActor
enum ActiveWindowScene {
    static var current: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first(where: { $0.activationState == .foregroundActive })
            ?? scenes.first(where: { $0.activationState == .foregroundInactive })
            ?? scenes.first
    }

    static var keyWindow: UIWindow? {
        guard let scene = current else { return nil }
        return scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first
    }
}
