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
        containerSize: CGSize,
        isVerticalToolbarActive: Bool = false
    ) -> AppLayoutMode {
        // iPhone Duo poses with a vertical side bar (outer display, Split View,
        // and unfolded landscape) stay in the unified collapsible-sheet shell
        // (with a leading-side collapsible sheet in unfolded landscape).
        guard !isVerticalToolbarActive else {
            return .compactSheet
        }
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

/// Constrains the persistent bottom sheet width on wide unfolded poses (e.g.
/// iPhone Duo landscape) so it sits cleanly on the leading side while preserving
/// collapsible detents, and falls back to default full width everywhere else.
struct AdaptiveLeadingSheetSizing: PresentationSizing, Equatable {
    let maxWidth: CGFloat?
    let maxHeight: CGFloat

    func proposedSize(
        for root: PresentationSizingRoot,
        context: PresentationSizingContext
    ) -> ProposedViewSize {
        guard let maxWidth else {
            return AutomaticPresentationSizing.automatic.proposedSize(for: root, context: context)
        }
        let finiteHeight: CGFloat? = maxHeight > 1 ? maxHeight : nil
        let measured = root.sizeThatFits(ProposedViewSize(width: maxWidth, height: finiteHeight))
        let resolvedHeight = finiteHeight.map { max(measured.height, $0) } ?? measured.height
        return ProposedViewSize(
            width: maxWidth,
            height: resolvedHeight > 1 ? resolvedHeight : finiteHeight
        )
    }
}

extension GeometryProxy {
    /// Returns a left-column width (~1/3 of the display, clamped to 300–336 pt)
    /// for a leading-pinned collapsible sheet on wide regular displays (e.g.
    /// iPhone Duo unfolded landscape), or `nil` when the sheet should span full width.
    func leadingCollapsibleSheetWidth(
        horizontalSizeClass: UserInterfaceSizeClass?
    ) -> CGFloat? {
        let fullWidth = size.width + safeAreaInsets.leading + safeAreaInsets.trailing
        let fullHeight = size.height + safeAreaInsets.top + safeAreaInsets.bottom
        guard horizontalSizeClass == .regular, fullWidth > fullHeight else {
            return nil
        }

        let targetWidth = min(max(fullWidth * 0.33, 300), 336)

        #if compiler(>=6.4)
        if #available(iOS 27.1, *),
           let fold = reservedRegions(kind: .division, options: .includeInactive).first,
           fold.frame.height > fold.frame.width {
            let leftOfFold = fold.frame.minX + safeAreaInsets.leading
            return min(targetWidth, max(leftOfFold - 16, 280))
        }
        #endif

        return targetWidth
    }
}

extension EnvironmentValues {
    /// True when iOS 27.1+ places navigation/toolbar controls in iPhone Duo's
    /// vertical side rail (outer display, unfolded landscape detail, Split View).
    var isVerticalToolbarActive: Bool {
        #if compiler(>=6.4)
        if #available(iOS 27.1, *) {
            return toolbarVerticalEdge != nil
        }
        #endif
        return false
    }
}

extension View {
    /// Opts a sheet or presentation out of iPhone Duo's vertical side bar so its
    /// contents span full width without an empty trailing vertical-bar safe-area inset.
    @ViewBuilder
    func disableVerticalToolbarIfAvailable() -> some View {
        #if compiler(>=6.4)
        if #available(iOS 27.1, *) {
            self.toolbarVerticalBehavior(.disabled)
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// Pins a sheet to the leading edge on iOS 27+ when wide landscape space is
    /// available (e.g. iPhone Duo unfolded landscape), and leaves default placement otherwise.
    @ViewBuilder
    func adaptiveSheetPlacement(leading: Bool) -> some View {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            self.presentationPlacement(leading ? .leading : .automatic)
        } else {
            self
        }
        #else
        self
        #endif
    }
}
