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
        guard verticalSizeClass == .regular else {
            return .compactSheet
        }
        guard containerSize.width > 0, containerSize.height > 0 else {
            return .compactSheet
        }

        let isWiderThanTall = containerSize.width > containerSize.height
        let hasRoomForPortraitSplit = containerSize.width >= portraitSplitMinimumWidth
        return (isWiderThanTall || hasRoomForPortraitSplit) ? .splitSidebar : .compactSheet
    }

    /// True when map controls (`Merchants/Communities`, `Map`, `Location`) should live
    /// in the native SwiftUI `.toolbar` instead of the compact bottom-trailing pill.
    ///
    /// Keeps all iPhone Duo poses consistent: outer display & unfolded landscape use
    /// the vertical side rail (`isVerticalToolbarActive`), while unfolded portrait
    /// (`horizontalSizeClass == .regular` on iOS 26+) keeps the same controls in the
    /// native top toolbar instead of falling back to the compact-iPhone floating pill.
    static func usesToolbarMapControls(
        horizontalSizeClass: UserInterfaceSizeClass?,
        isVerticalToolbarActive: Bool,
        usesNativeHorizontalBar: Bool
    ) -> Bool {
        isVerticalToolbarActive || (horizontalSizeClass == .regular && usesNativeHorizontalBar)
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
    /// Pure width resolver for wide leading-pinned collapsible sheets, factoring in
    /// horizontal size class, orientation, optional vertical fold frame, and LTR/RTL layout direction.
    static func resolvedWidth(
        containerSize: CGSize,
        safeAreaInsets: EdgeInsets,
        horizontalSizeClass: UserInterfaceSizeClass?,
        layoutDirection: LayoutDirection = .leftToRight,
        verticalFoldFrame: CGRect? = nil
    ) -> CGFloat? {
        let fullWidth = containerSize.width + safeAreaInsets.leading + safeAreaInsets.trailing
        let fullHeight = containerSize.height + safeAreaInsets.top + safeAreaInsets.bottom
        guard horizontalSizeClass == .regular, fullWidth > fullHeight else {
            return nil
        }

        let targetWidth = min(max(fullWidth * 0.42, 380), 420)

        if let foldFrame = verticalFoldFrame, foldFrame.height > foldFrame.width {
            let leadingOfFold: CGFloat = layoutDirection == .rightToLeft
                ? containerSize.width - foldFrame.maxX + safeAreaInsets.trailing
                : foldFrame.minX + safeAreaInsets.leading
            return min(targetWidth, max(leadingOfFold - 16, 340))
        }

        return targetWidth
    }
}

extension GeometryProxy {
    /// Returns a leading-column width (~42% of the display, clamped to 380–420 pt)
    /// for a leading-pinned collapsible sheet on wide regular displays (e.g.
    /// iPhone Duo unfolded landscape), staying comfortably clear of the center fold
    /// in both LTR and RTL layouts.
    func leadingCollapsibleSheetWidth(
        horizontalSizeClass: UserInterfaceSizeClass?,
        layoutDirection: LayoutDirection = .leftToRight
    ) -> CGFloat? {
        var foldFrame: CGRect?
        #if compiler(>=6.4)
        if #available(iOS 27.1, *),
           let fold = reservedRegions(kind: .division, options: .includeInactive).first {
            foldFrame = fold.frame
        }
        #endif

        return AdaptiveLeadingSheetSizing.resolvedWidth(
            containerSize: size,
            safeAreaInsets: safeAreaInsets,
            horizontalSizeClass: horizontalSizeClass,
            layoutDirection: layoutDirection,
            verticalFoldFrame: foldFrame
        )
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
    /// Opts a modal or bottom sheet out of iPhone Duo's vertical side bar using
    /// `.toolbarVerticalBehavior(.disabled)`.
    ///
    /// On iPhone Duo's outer display, the main map scene already occupies the
    /// outer vertical toolbar rail; disabling the vertical toolbar inside
    /// presented sheets avoids reserving a duplicate empty trailing safe-area
    /// inset so sheet content can span the full sheet width.
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

/// Top-level sheet presented by `IPhoneLayoutView` so `SettingsView` is never
/// stacked as a nested child detent sheet on top of `BottomSheetContentView`
/// (which caused UIKit to drag the bottom sheet up and down behind Settings on
/// unfolded iPhone Duo).
enum IPhoneActiveSheet: String, Identifiable, Equatable, Sendable {
    case browse
    case settings

    var id: String { rawValue }
}

enum IPhoneSheetPresentationResolver {
    static func targetSheet(
        shouldPresentBottomSheet: Bool,
        showingSettings: Bool
    ) -> IPhoneActiveSheet? {
        if showingSettings {
            return .settings
        }
        return shouldPresentBottomSheet ? .browse : nil
    }

    static func stateAfterDismiss(
        currentActiveSheet: IPhoneActiveSheet?,
        shouldPresentBottomSheet: Bool,
        showingSettings: Bool
    ) -> (nextSheet: IPhoneActiveSheet?, nextShowingSettings: Bool) {
        // Ignore intermediate dismiss callbacks when another sheet is already scheduled.
        guard currentActiveSheet == nil else {
            return (currentActiveSheet, showingSettings)
        }
        let nextShowingSettings = false
        let nextSheet = targetSheet(
            shouldPresentBottomSheet: shouldPresentBottomSheet,
            showingSettings: nextShowingSettings
        )
        return (nextSheet, nextShowingSettings)
    }
}
