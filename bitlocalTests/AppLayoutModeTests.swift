import MapKit
import SwiftUI
import Testing
@testable import bitlocal

@Suite(.tags(.layout))
struct AppLayoutModeTests {

    struct LayoutPoseCase: Sendable {
        let name: String
        let horizontal: UserInterfaceSizeClass?
        let vertical: UserInterfaceSizeClass?
        let size: CGSize
        let isVerticalToolbarActive: Bool
        let expected: AppLayoutMode

        init(
            _ name: String,
            horizontal: UserInterfaceSizeClass?,
            vertical: UserInterfaceSizeClass?,
            size: CGSize,
            isVerticalToolbarActive: Bool = false,
            expected: AppLayoutMode
        ) {
            self.name = name
            self.horizontal = horizontal
            self.vertical = vertical
            self.size = size
            self.isVerticalToolbarActive = isVerticalToolbarActive
            self.expected = expected
        }
    }

    // MARK: - Adaptive Layout Resolution

    @Test(arguments: [
        LayoutPoseCase("iPhone portrait", horizontal: .compact, vertical: .regular, size: CGSize(width: 393, height: 852), expected: .compactSheet),
        LayoutPoseCase("iPhone Duo outer portrait", horizontal: .compact, vertical: .regular, size: CGSize(width: 466, height: 678), expected: .compactSheet),
        LayoutPoseCase("iPhone Duo outer landscape", horizontal: .compact, vertical: .compact, size: CGSize(width: 678, height: 466), expected: .compactSheet),
        LayoutPoseCase("iPhone Duo Split View half-width", horizontal: .compact, vertical: .regular, size: CGSize(width: 470, height: 669), expected: .compactSheet),
        LayoutPoseCase("iPhone Duo unfolded landscape", horizontal: .regular, vertical: .regular, size: CGSize(width: 951, height: 669), isVerticalToolbarActive: true, expected: .compactSheet),
        LayoutPoseCase("iPhone Duo unfolded portrait", horizontal: .regular, vertical: .regular, size: CGSize(width: 669, height: 951), expected: .compactSheet),
        LayoutPoseCase("iPad mini portrait", horizontal: .regular, vertical: .regular, size: CGSize(width: 744, height: 1133), expected: .splitSidebar),
        LayoutPoseCase("iPad landscape", horizontal: .regular, vertical: .regular, size: CGSize(width: 1194, height: 834), expected: .splitSidebar),
        LayoutPoseCase("Regular width compact height", horizontal: .regular, vertical: .compact, size: CGSize(width: 932, height: 430), expected: .compactSheet),
        LayoutPoseCase("Nil size classes", horizontal: nil, vertical: nil, size: CGSize(width: 951, height: 669), expected: .compactSheet),
        LayoutPoseCase("Zero container size", horizontal: .regular, vertical: .regular, size: .zero, expected: .compactSheet),
        LayoutPoseCase("Regular horizontal with nil vertical", horizontal: .regular, vertical: nil, size: CGSize(width: 1024, height: 768), expected: .compactSheet)
    ])
    func resolvesExpectedShell(pose: LayoutPoseCase) {
        let mode = AppLayoutMode.resolve(
            horizontalSizeClass: pose.horizontal,
            verticalSizeClass: pose.vertical,
            containerSize: pose.size,
            isVerticalToolbarActive: pose.isVerticalToolbarActive
        )
        #expect(mode == pose.expected, "Unexpected mode for \(pose.name)")
    }

    // MARK: - ContentViewModel Layout Transitions

    @MainActor
    @Test func updatingLayoutModeToSplitSidebarClearsCompactPaddingAndViewportInsets() {
        let viewModel = ContentViewModel()
        viewModel.topPadding = 92
        viewModel.bottomPadding = 260

        let mapView = MKMapView(frame: CGRect(x: 0, y: 0, width: 600, height: 669))

        viewModel.updateLayoutMode(.compactSheet)
        let compactInsets = viewModel.mapListViewportInsets(for: mapView)
        #expect(compactInsets.top == 92)
        #expect(compactInsets.bottom > 0)

        viewModel.updateLayoutMode(.splitSidebar)
        #expect(viewModel.layoutMode == .splitSidebar)
        #expect(viewModel.topPadding == 0)
        #expect(viewModel.bottomPadding == 0)
        #expect(viewModel.leadingSheetInset == 0)
        #expect(viewModel.mapListViewportInsets(for: mapView) == .zero)
    }

    @MainActor
    @Test func leadingSheetInsetShiftsViewportLeftInsteadOfBottom() {
        let viewModel = ContentViewModel()
        viewModel.updateLayoutMode(.compactSheet)
        viewModel.topPadding = 0
        viewModel.bottomPadding = 260
        viewModel.leadingSheetInset = 420

        let mapView = MKMapView(frame: CGRect(x: 0, y: 0, width: 951, height: 669))
        let insets = viewModel.mapListViewportInsets(for: mapView)

        #expect(insets.left == 420)
        #expect(insets.bottom == 0)
        #expect(insets.top == 0)
        #expect(insets.right == 0)
    }

    // MARK: - AdaptiveLeadingSheetSizing

    @Test func leadingSheetWidthReturnsNilOnCompactOrPortrait() {
        #expect(
            AdaptiveLeadingSheetSizing.resolvedWidth(
                containerSize: CGSize(width: 393, height: 852),
                safeAreaInsets: EdgeInsets(),
                horizontalSizeClass: .compact
            ) == nil
        )
        #expect(
            AdaptiveLeadingSheetSizing.resolvedWidth(
                containerSize: CGSize(width: 669, height: 951),
                safeAreaInsets: EdgeInsets(),
                horizontalSizeClass: .regular
            ) == nil
        )
    }

    @Test func leadingSheetWidthClearsVerticalFoldInLTRAndRTL() throws {
        let containerSize = CGSize(width: 900, height: 669)
        let safeInsets = EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 40)
        // Asymmetric vertical fold shifted slightly left of center:
        // LTR leading space = 370 + 20 = 390 -> 390 - 16 = 374
        // RTL leading space = (900 - 380) + 40 = 560 -> capped at targetWidth (~403.2)
        let foldFrame = CGRect(x: 370, y: 0, width: 10, height: 669)

        let ltrWidth = try #require(
            AdaptiveLeadingSheetSizing.resolvedWidth(
                containerSize: containerSize,
                safeAreaInsets: safeInsets,
                horizontalSizeClass: .regular,
                layoutDirection: .leftToRight,
                verticalFoldFrame: foldFrame
            )
        )
        let rtlWidth = try #require(
            AdaptiveLeadingSheetSizing.resolvedWidth(
                containerSize: containerSize,
                safeAreaInsets: safeInsets,
                horizontalSizeClass: .regular,
                layoutDirection: .rightToLeft,
                verticalFoldFrame: foldFrame
            )
        )

        #expect(abs(ltrWidth - 374) <= 0.5)
        #expect(abs(rtlWidth - (960 * 0.42)) <= 0.5)
    }
}
