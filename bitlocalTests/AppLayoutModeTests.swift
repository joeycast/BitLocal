import MapKit
import SwiftUI
import XCTest
@testable import bitlocal

final class AppLayoutModeTests: XCTestCase {

    // MARK: - iPhone & iPhone Duo outer display

    func testStandardIPhonePortraitUsesCompactSheet() {
        let mode = AppLayoutMode.resolve(
            horizontalSizeClass: .compact,
            verticalSizeClass: .regular,
            containerSize: CGSize(width: 393, height: 852)
        )
        XCTAssertEqual(mode, .compactSheet)
    }

    func testIPhoneDuoOuterDisplayPortraitUsesCompactSheet() {
        let mode = AppLayoutMode.resolve(
            horizontalSizeClass: .compact,
            verticalSizeClass: .regular,
            containerSize: CGSize(width: 466, height: 678)
        )
        XCTAssertEqual(mode, .compactSheet)
    }

    func testIPhoneDuoOuterDisplayLandscapeUsesCompactSheet() {
        let mode = AppLayoutMode.resolve(
            horizontalSizeClass: .compact,
            verticalSizeClass: .compact,
            containerSize: CGSize(width: 678, height: 466)
        )
        XCTAssertEqual(mode, .compactSheet)
    }

    func testIPhoneDuoSplitViewHalfWidthUsesCompactSheet() {
        let mode = AppLayoutMode.resolve(
            horizontalSizeClass: .compact,
            verticalSizeClass: .regular,
            containerSize: CGSize(width: 470, height: 669)
        )
        XCTAssertEqual(mode, .compactSheet)
    }

    // MARK: - iPhone Duo unfolded inner display

    func testIPhoneDuoUnfoldedLandscapeUsesCollapsibleLeadingSheetShell() {
        let mode = AppLayoutMode.resolve(
            horizontalSizeClass: .regular,
            verticalSizeClass: .regular,
            containerSize: CGSize(width: 951, height: 669),
            isVerticalToolbarActive: true
        )
        XCTAssertEqual(mode, .compactSheet)
    }

    func testIPhoneDuoUnfoldedPortraitUsesCompactSheet() {
        let mode = AppLayoutMode.resolve(
            horizontalSizeClass: .regular,
            verticalSizeClass: .regular,
            containerSize: CGSize(width: 669, height: 951)
        )
        XCTAssertEqual(mode, .compactSheet)
    }

    // MARK: - iPad & edge cases

    func testIPadMiniPortraitUsesSplitSidebar() {
        let mode = AppLayoutMode.resolve(
            horizontalSizeClass: .regular,
            verticalSizeClass: .regular,
            containerSize: CGSize(width: 744, height: 1133)
        )
        XCTAssertEqual(mode, .splitSidebar)
    }

    func testIPadLandscapeUsesSplitSidebar() {
        let mode = AppLayoutMode.resolve(
            horizontalSizeClass: .regular,
            verticalSizeClass: .regular,
            containerSize: CGSize(width: 1194, height: 834)
        )
        XCTAssertEqual(mode, .splitSidebar)
    }

    func testRegularWidthCompactHeightUsesCompactSheet() {
        let mode = AppLayoutMode.resolve(
            horizontalSizeClass: .regular,
            verticalSizeClass: .compact,
            containerSize: CGSize(width: 932, height: 430)
        )
        XCTAssertEqual(mode, .compactSheet)
    }

    func testNilSizeClassesOrZeroSizeFallBackToCompactSheet() {
        XCTAssertEqual(
            AppLayoutMode.resolve(
                horizontalSizeClass: nil,
                verticalSizeClass: nil,
                containerSize: CGSize(width: 951, height: 669)
            ),
            .compactSheet
        )
        XCTAssertEqual(
            AppLayoutMode.resolve(
                horizontalSizeClass: .regular,
                verticalSizeClass: .regular,
                containerSize: .zero
            ),
            .compactSheet
        )
    }

    // MARK: - ContentViewModel layout transition

    @MainActor
    func testUpdatingLayoutModeToSplitSidebarClearsCompactPaddingAndViewportInsets() {
        let viewModel = ContentViewModel()
        viewModel.topPadding = 92
        viewModel.bottomPadding = 260

        let mapView = MKMapView(frame: CGRect(x: 0, y: 0, width: 600, height: 669))

        viewModel.updateLayoutMode(.compactSheet)
        let compactInsets = viewModel.mapListViewportInsets(for: mapView)
        XCTAssertEqual(compactInsets.top, 92)
        XCTAssertGreaterThan(compactInsets.bottom, 0)

        viewModel.updateLayoutMode(.splitSidebar)
        XCTAssertEqual(viewModel.layoutMode, .splitSidebar)
        XCTAssertEqual(viewModel.topPadding, 0)
        XCTAssertEqual(viewModel.bottomPadding, 0)
        XCTAssertEqual(viewModel.leadingSheetInset, 0)
        XCTAssertEqual(viewModel.mapListViewportInsets(for: mapView), .zero)
    }

    @MainActor
    func testLeadingSheetInsetShiftsViewportLeftInsteadOfBottom() {
        let viewModel = ContentViewModel()
        viewModel.updateLayoutMode(.compactSheet)
        viewModel.topPadding = 0
        viewModel.bottomPadding = 260
        viewModel.leadingSheetInset = 420

        let mapView = MKMapView(frame: CGRect(x: 0, y: 0, width: 951, height: 669))
        let insets = viewModel.mapListViewportInsets(for: mapView)

        XCTAssertEqual(insets.left, 420)
        XCTAssertEqual(insets.bottom, 0)
        XCTAssertEqual(insets.top, 0)
        XCTAssertEqual(insets.right, 0)
    }

    // MARK: - AdaptiveLeadingSheetSizing & Optional Size Classes

    func testRegularHorizontalWithNilVerticalSizeClassFallsBackToCompactSheet() {
        let mode = AppLayoutMode.resolve(
            horizontalSizeClass: .regular,
            verticalSizeClass: nil,
            containerSize: CGSize(width: 1024, height: 768)
        )
        XCTAssertEqual(mode, .compactSheet)
    }

    func testLeadingSheetWidthReturnsNilOnCompactOrPortrait() {
        XCTAssertNil(
            AdaptiveLeadingSheetSizing.resolvedWidth(
                containerSize: CGSize(width: 393, height: 852),
                safeAreaInsets: EdgeInsets(),
                horizontalSizeClass: .compact
            )
        )
        XCTAssertNil(
            AdaptiveLeadingSheetSizing.resolvedWidth(
                containerSize: CGSize(width: 669, height: 951),
                safeAreaInsets: EdgeInsets(),
                horizontalSizeClass: .regular
            )
        )
    }

    func testLeadingSheetWidthClearsVerticalFoldInLTRAndRTL() {
        let containerSize = CGSize(width: 900, height: 669)
        let safeInsets = EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 40)
        // Asymmetric vertical fold shifted slightly left of center:
        // LTR leading space = 370 + 20 = 390 -> 390 - 16 = 374
        // RTL leading space = (900 - 380) + 40 = 560 -> capped at targetWidth (~403.2)
        let foldFrame = CGRect(x: 370, y: 0, width: 10, height: 669)

        let ltrWidth = AdaptiveLeadingSheetSizing.resolvedWidth(
            containerSize: containerSize,
            safeAreaInsets: safeInsets,
            horizontalSizeClass: .regular,
            layoutDirection: .leftToRight,
            verticalFoldFrame: foldFrame
        )
        let rtlWidth = AdaptiveLeadingSheetSizing.resolvedWidth(
            containerSize: containerSize,
            safeAreaInsets: safeInsets,
            horizontalSizeClass: .regular,
            layoutDirection: .rightToLeft,
            verticalFoldFrame: foldFrame
        )

        XCTAssertEqual(ltrWidth ?? 0, 374, accuracy: 0.5)
        XCTAssertEqual(rtlWidth ?? 0, 960 * 0.42, accuracy: 0.5)
    }
}
